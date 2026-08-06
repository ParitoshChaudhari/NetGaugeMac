import AppKit
import SwiftUI

@main
struct NetGaugeMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    static private(set) var shared: AppDelegate?

    private let model = DashboardModel()
    private var statusItem: NSStatusItem?
    private var dashboardWindow: NSWindow?

    private var isQuittingFromMenu = false
    private var isSystemShuttingDown = false

    // Bug 5 fix: cancel any in-flight restore before scheduling a new one
    private var pendingRestoreItem: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self

        // Set dynamic application icon
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = image
        }

        setupStatusItem()

        // Activate app but allow starting in background if booted recently
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApplication.shared.activate(ignoringOtherApps: false)
        }

        // Register for system power off/logout notification to allow termination in those cases
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handlePowerOff),
            name: NSWorkspace.willPowerOffNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWakeFromSleep),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.createDashboardWindow()

            // Check system uptime. If < 120s, start hidden in the Menu Bar
            let uptime = self.getSystemUptime()
            if uptime < 120.0 {
                NSApp.setActivationPolicy(.accessory)
                self.restoreStatusItem()
            } else {
                self.openDashboardWindow()
            }
        }
    }

    @objc private func handlePowerOff(_ notification: Notification) {
        Task { @MainActor in
            self.isSystemShuttingDown = true
        }
    }

    @objc private func handleWakeFromSleep(_ notification: Notification) {
        restoreStatusItem()
    }

    private func restoreStatusItem() {
        // Bug 5 fix: cancel any previously-scheduled restore before scheduling a new one
        // so rapid show/hide cycles don't race.
        pendingRestoreItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.statusItem?.isVisible = true
            let dl = self.model.currentDownloadBytesPerSecond
            let ul = self.model.currentUploadBytesPerSecond
            self.updateStatusItemText(download: dl, upload: ul)
        }
        pendingRestoreItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isQuittingFromMenu || isSystemShuttingDown {
            // Bug 4 fix: flush with a hard 3-second timeout.
            // If flushPendingData() hangs (DB lock, corrupt file), reply is still
            // called so the process terminates instead of getting stuck indefinitely.
            Task { @MainActor in
                await withTaskGroup(of: Void.self) { group in
                    group.addTask { await self.model.flushPendingData() }
                    group.addTask {
                        try? await Task.sleep(for: .seconds(3))
                    }
                    // Wait for whichever finishes first
                    await group.next()
                    group.cancelAll()
                }
                NSApplication.shared.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        } else {
            // Intercept Cmd+Q, Dock Quit, App Menu Quit.
            // Cancel any in-flight SwiftUI/AppKit animations before hiding the window.
            // Without this, a spring animation on AppTabPicker (VisualEffectView pill)
            // can race with orderOut and corrupt SwiftUI state, causing a crash.
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.dashboardWindow else { return }
                NSAnimationContext.beginGrouping()
                NSAnimationContext.current.duration = 0
                NSAnimationContext.current.allowsImplicitAnimation = false
                NSApp.setActivationPolicy(.accessory)
                self.restoreStatusItem()
                // Bug 7 (partial): tell model the window is no longer visible
                self.model.windowIsVisible = false
                window.orderOut(nil)
                NSAnimationContext.endGrouping()
            }
            return .terminateCancel
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Open the window when the user clicks the Dock icon.
        // Return false to signal we handled it ourselves; returning true would let
        // AppKit attempt its own reopen handling and potentially open a second window.
        openDashboardWindow()
        return false
    }

    // MARK: – Status Menu

    private func setupStatusItem() {
        // Variable length to adjust dynamically to the speed digits
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.cell?.wraps = true
            updateStatusItemText(download: 0, upload: 0)
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Dashboard", action: #selector(openDashboardAction), keyEquivalent: "d"))
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettingsAction), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "About NetGauge", action: #selector(showAboutPanelAction), keyEquivalent: "a"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitAppAction), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    @objc private func openDashboardAction() {
        model.selectedTab = .dashboard
        openDashboardWindow()
    }

    @objc private func openSettingsAction() {
        model.selectedTab = .settings
        openDashboardWindow()
    }

    @objc private func quitAppAction() {
        isQuittingFromMenu = true
        NSApplication.shared.terminate(nil)
    }

    @objc private func showAboutPanelAction() {
        showAboutPanel()
    }

    private func createDashboardWindow() {
        guard dashboardWindow == nil else { return }

        let contentView = DashboardView()
            .environmentObject(model)
            .frame(minWidth: 1120, minHeight: 760)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // Bug 3 fix: set isReleasedWhenClosed immediately after creation,
        // before any other configuration or potential display, to prevent
        // a dangling pointer on window close if the window is shown before
        // this flag is set.
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("NetGaugeDashboard")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.title = "NetGauge"
        window.delegate = self
        window.contentView = NSHostingView(rootView: contentView)

        self.dashboardWindow = window

        Task {
            await model.start()
        }
    }

    private func openDashboardWindow() {
        createDashboardWindow()

        if let window = dashboardWindow {
            NSApp.setActivationPolicy(.regular)
            window.makeKeyAndOrderFront(nil)
            // Bug 7 (partial): tell model the window is visible so capture loop
            // can use the faster 1s interval and enable refreshEvents().
            model.windowIsVisible = true
            if #available(macOS 14.0, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    func updateStatusItemText(download: Double, upload: Double) {
        // Bug 6 fix: never call setupStatusItem() here — doing so creates a SECOND
        // NSStatusItem, leaking the original and producing duplicate menu bar icons.
        // If the button is somehow nil, return early and let the next tick retry.
        guard let button = statusItem?.button else { return }

        let dlString = download.speedString
        let ulString = upload.speedString
        let text = "↓ \(dlString)\n↑ \(ulString)"

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 1
        paragraphStyle.paragraphSpacing = 0
        paragraphStyle.alignment = .left

        let font = NSFont.monospacedSystemFont(ofSize: 8.5, weight: .semibold)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: NSColor.labelColor
        ]

        let attrString = NSMutableAttributedString(string: text, attributes: attributes)

        // Color arrow symbols for visual clarity
        let rangeOfDown = (text as NSString).range(of: "↓")
        if rangeOfDown.location != NSNotFound {
            attrString.addAttribute(.foregroundColor, value: NSColor.systemTeal, range: rangeOfDown)
        }
        let rangeOfUp = (text as NSString).range(of: "↑")
        if rangeOfUp.location != NSNotFound {
            attrString.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: rangeOfUp)
        }

        button.attributedTitle = attrString
    }

    // MARK: – NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Intercept close button and hide the window instead of destroying it.
        // Cancel in-flight animations first to prevent VisualEffectView crash.
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        NSAnimationContext.current.allowsImplicitAnimation = false
        NSApp.setActivationPolicy(.accessory)
        restoreStatusItem()
        // Bug 7 (partial): window hidden — switch model to low-power accessory mode
        model.windowIsVisible = false
        sender.orderOut(nil)
        NSAnimationContext.endGrouping()
        return false
    }

    // MARK: – Custom About Panel

    @objc func showAboutPanel() {
        let logo: NSImage
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            logo = img
        } else {
            logo = NSApplication.shared.applicationIconImage ?? NSImage()
        }

        let credits = NSMutableAttributedString()
        let style = NSMutableParagraphStyle()
        style.alignment = .center

        let devAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 12),
            .paragraphStyle: style,
            .foregroundColor: NSColor.labelColor
        ]
        credits.append(NSAttributedString(string: "Paritosh Chaudhari\n\n", attributes: devAttributes))

        let infoAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .paragraphStyle: style,
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        credits.append(NSAttributedString(string: "A native real-time network usage monitor with tiered SQLite retention strategy.", attributes: infoAttributes))

        let options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationIcon: logo,
            .credits: credits,
            .applicationName: "NetGauge",
            .version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        ]

        NSApplication.shared.orderFrontStandardAboutPanel(options: options)
    }

    // MARK: – Helpers

    private func getSystemUptime() -> TimeInterval {
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.size
        var mib = [CTL_KERN, KERN_BOOTTIME]
        let result = sysctl(&mib, 2, &bootTime, &size, nil, 0)
        if result == 0 {
            let bootDate = Date(timeIntervalSince1970: Double(bootTime.tv_sec) + Double(bootTime.tv_usec) / 1_000_000.0)
            return Date().timeIntervalSince(bootDate)
        }
        return 999.0
    }
}
