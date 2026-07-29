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

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.createDashboardWindow()

            // Check system uptime. If < 120s, start hidden in the Menu Bar
            let uptime = self.getSystemUptime()
            if uptime < 120.0 {
                NSApp.setActivationPolicy(.accessory)
            } else {
                self.openDashboardWindow()
            }
        }
    }

    @objc private func handlePowerOff(_ notification: Notification) {
        isSystemShuttingDown = true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isQuittingFromMenu || isSystemShuttingDown {
            return .terminateNow
        } else {
            // Intercept Cmd+Q, Dock Quit, App Menu Quit
            // Just hide the window and keep the app running in the Menu Bar
            DispatchQueue.main.async { [weak self] in
                if let window = self?.dashboardWindow {
                    NSApp.setActivationPolicy(.accessory)
                    window.orderOut(nil)
                }
            }
            return .terminateCancel
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Open the window when the user clicks the Dock icon
        openDashboardWindow()
        return true
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
        menu.addItem(NSMenuItem(title: "About NetGauge", action: #selector(showAboutPanelAction), keyEquivalent: "a"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitAppAction), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    @objc private func openDashboardAction() {
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
            if #available(macOS 14.0, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    func updateStatusItemText(download: Double, upload: Double) {
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
        // Intercept close button and hide the window instead of destroying it
        NSApp.setActivationPolicy(.accessory)
        sender.orderOut(nil)
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
