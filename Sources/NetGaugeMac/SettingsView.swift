import SwiftUI
import AppKit

// MARK: - View Modifier for Notes Theme Card

private struct NotesCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .background(NotesTheme.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(NotesTheme.borderAccent, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.20), radius: 8, x: 0, y: 3)
    }
}

extension View {
    func notesCard(cornerRadius: CGFloat = 12) -> some View {
        modifier(NotesCardModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Settings View

public struct SettingsView: View {
    @EnvironmentObject private var model: DashboardModel

    @State private var showClearConfirmation = false
    @State private var showSuccessToast = false
    @State private var didCopyPath = false
    @State private var showCrashReportsSheet = false
    @State private var crashReports: [[String: Any]] = []
    @State private var didCopiedDiagnostics = false

    public init() {}

    public var body: some View {
        ZStack(alignment: .top) {
            // Notes Paper Canvas Background
            NotesTheme.bgBase
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 20) {
                    headerView

                    generalCard

                    networkCard

                    storageCard

                    diagnosticsCard

                    dangerCard
                }
                .padding(24)
            }

            // Toast feedback banner
            if showSuccessToast {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(NotesTheme.green)
                    Text("All network speed data cleared. Reset complete.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NotesTheme.textPrimary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(NotesTheme.bgCardHover)
                .clipShape(Capsule())
                .overlay {
                    Capsule().strokeBorder(NotesTheme.green.opacity(0.6), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
                .padding(.top, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: showSuccessToast)
        .frame(minWidth: 580, idealWidth: 620, maxWidth: 740, minHeight: 600, idealHeight: 700)
        .alert("Clear All Network Data?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All Data", role: .destructive) {
                Task { @MainActor in
                    await model.clearAllData()
                    withAnimation { showSuccessToast = true }
                    try? await Task.sleep(for: .seconds(3.5))
                    withAnimation { showSuccessToast = false }
                }
            }
        } message: {
            Text("This will permanently delete all recorded network speed and usage history and reset NetGauge to its fresh install state. This action cannot be undone.")
        }
        .sheet(isPresented: $showCrashReportsSheet) {
            NotesCrashReportsSheet(reports: crashReports)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(NotesTheme.accentBg)
                    .frame(width: 44, height: 44)
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(NotesTheme.accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("NetGauge Settings")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(NotesTheme.textPrimary)

                    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.6"
                    Text("v\(version)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(NotesTheme.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(NotesTheme.accentBg)
                        .clipShape(Capsule())
                        .overlay {
                            Capsule().strokeBorder(NotesTheme.accentBorder, lineWidth: 1)
                        }
                }
                Text("Configure startup preferences, appearance, permissions, and storage.")
                    .font(.caption)
                    .foregroundStyle(NotesTheme.textSecondary)
            }

            Spacer()
        }
        .padding(.bottom, 4)
    }

    // MARK: - Card 1: General Preferences

    private var generalCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "switch.2")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NotesTheme.accent)
                Text("General Preferences")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NotesTheme.textPrimary)
            }

            NotesTheme.divider.frame(height: 1)

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Launch at Login")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(NotesTheme.textPrimary)
                    Text("Automatically start NetGauge in the Menu Bar when you log in to macOS.")
                        .font(.caption)
                        .foregroundStyle(NotesTheme.textSecondary)
                }

                Spacer()

                Toggle("", isOn: $model.isLaunchAtLoginEnabled)
                    .toggleStyle(.switch)
                    .tint(NotesTheme.accent)
            }
        }
        .padding(18)
        .notesCard()
    }

    // MARK: - Card 2: Network & Wi-Fi Permissions

    private var networkCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "wifi")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NotesTheme.accent)
                Text("Wi-Fi SSID Resolution & Permissions")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NotesTheme.textPrimary)
            }

            NotesTheme.divider.frame(height: 1)

            HStack(spacing: 12) {
                let isGranted = LocationHelper.shared.authorizationStatus == .authorized
                Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(isGranted ? NotesTheme.green : NotesTheme.accent)

                VStack(alignment: .leading, spacing: 3) {
                    Text(isGranted ? "Location Permission Granted" : "Location Permission Required for SSIDs")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(NotesTheme.textPrimary)
                    Text(isGranted
                         ? "NetGauge accurately identifies exact Wi-Fi network names (SSIDs)."
                         : "Without location access, Wi-Fi traffic is categorized by hardware interface (e.g. en0).")
                        .font(.caption)
                        .foregroundStyle(NotesTheme.textSecondary)
                }

                Spacer()

                if !isGranted {
                    Button("Request Permission") {
                        LocationHelper.shared.requestPermission()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NotesTheme.bgBase)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(NotesTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(18)
        .notesCard()
    }

    // MARK: - Card 4: Storage & Database

    private var storageCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "cylinder.split.1x2.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NotesTheme.accent)
                Text("Local SQLite Storage & Retention")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NotesTheme.textPrimary)
            }

            NotesTheme.divider.frame(height: 1)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Database File Location:")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(NotesTheme.textSecondary)
                    Spacer()
                    Button {
                        let path = databasePath
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(path, forType: .string)
                        withAnimation { didCopyPath = true }
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            await MainActor.run { withAnimation { didCopyPath = false } }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: didCopyPath ? "checkmark" : "doc.on.doc")
                            Text(didCopyPath ? "Copied" : "Copy Path")
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(didCopyPath ? NotesTheme.green : NotesTheme.accent)
                    }
                    .buttonStyle(.plain)
                }

                Text(verbatim: databasePath)
                    .font(.caption.monospaced())
                    .foregroundStyle(NotesTheme.textPrimary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NotesTheme.bgCardHover)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .textSelection(.enabled)
            }

            Text("Tiered Strategy: 1-minute samples (7 days) · 1-hour rollups (30 days) · 1-day rollups (permanent).")
                .font(.caption2)
                .foregroundStyle(NotesTheme.textMuted)
        }
        .padding(18)
        .notesCard()
    }

    private var databasePath: String {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "NetGaugeMac/netgauge.db").path ?? "Unknown"
    }

    // MARK: - Card 5: Diagnostics & Logs

    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "stethoscope")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NotesTheme.accent)
                Text("Diagnostics & System Logs")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NotesTheme.textPrimary)
            }

            NotesTheme.divider.frame(height: 1)

            // Console.app Action
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Apple Unified System Logs")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(NotesTheme.textPrimary)
                    Text("Stream real-time Console.app events filtered to subsystem 'com.paritoshchaudhari.NetGaugeMac'.")
                        .font(.caption)
                        .foregroundStyle(NotesTheme.textSecondary)
                }
                Spacer()
                Button {
                    openSystemLogs()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.forward.app")
                        Text("Open Console")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NotesTheme.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(NotesTheme.bgCardHover)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6).strokeBorder(NotesTheme.border, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }

            NotesTheme.divider.frame(height: 1)

            // Crash Reports
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Crash Reports on Disk")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(NotesTheme.textPrimary)
                    Text("Inspect signal traps and uncaught exception reports generated by CrashGuard.")
                        .font(.caption)
                        .foregroundStyle(NotesTheme.textSecondary)
                }
                Spacer()
                Button {
                    crashReports = CrashGuard.existingCrashReports()
                    showCrashReportsSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "list.bullet.rectangle")
                        Text("View Reports")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NotesTheme.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(NotesTheme.bgCardHover)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6).strokeBorder(NotesTheme.border, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }

            NotesTheme.divider.frame(height: 1)

            // Copy Report
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Export Diagnostic Summary")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(NotesTheme.textPrimary)
                    Text("Copy structured system specs, crash history, and fault context to the clipboard.")
                        .font(.caption)
                        .foregroundStyle(NotesTheme.textSecondary)
                }
                Spacer()
                Button {
                    copyDiagnosticReport()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: didCopiedDiagnostics ? "checkmark" : "doc.on.clipboard")
                        Text(didCopiedDiagnostics ? "Copied!" : "Copy Report")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(didCopiedDiagnostics ? NotesTheme.green : NotesTheme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(NotesTheme.accentBg)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6).strokeBorder(NotesTheme.accentBorder, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .notesCard()
    }

    private func openSystemLogs() {
        let subsystem = "com.paritoshchaudhari.NetGaugeMac"
        let escapedSubsystem = subsystem.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subsystem
        let consoleURL = URL(fileURLWithPath: "/System/Applications/Utilities/Console.app")
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = ["--predicate", "subsystem == \"\(escapedSubsystem)\""]
        NSWorkspace.shared.openApplication(at: consoleURL, configuration: config)
        AppLogger.info(.ui, "User opened System Logs from Settings")
    }

    private func copyDiagnosticReport() {
        let version  = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.6"
        let build    = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "6"
        let os       = ProcessInfo.processInfo.operatingSystemVersionString
        let reports  = CrashGuard.existingCrashReports()
        let ctx      = AppLogger.readLastCrashContext()

        var lines: [String] = [
            "=== NetGauge Diagnostic Report ===",
            "App Version : \(version) (\(build))",
            "macOS       : \(os)",
            "Generated   : \(Date())",
            "",
            "--- Crash Reports on Disk: \(reports.count) ---"
        ]
        for report in reports.prefix(5) {
            if let type = report["type"] as? String,
               let ts   = report["timestamp"] as? String {
                let sig = report["signal"] as? String ?? report["exceptionName"] as? String ?? "?"
                lines.append("  [\(ts)] type=\(type) signal/exception=\(sig)")
            }
        }
        if let ctx {
            lines.append("")
            lines.append("--- Last Fault Context ---")
            lines.append("  Category : \(ctx.category)")
            lines.append("  Message  : \(ctx.message)")
            lines.append("  At       : \(ctx.timestamp)")
            lines.append("  Version  : \(ctx.appVersion)")
        }
        lines.append("")
        lines.append("To view full logs: open Console.app and filter by subsystem 'com.paritoshchaudhari.NetGaugeMac'")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        AppLogger.info(.ui, "User copied diagnostic report from Settings")
        withAnimation { didCopiedDiagnostics = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run { withAnimation { didCopiedDiagnostics = false } }
        }
    }

    // MARK: - Card 6: Danger Zone

    private var dangerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NotesTheme.red)
                Text("Reset & Clear All Data")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NotesTheme.textPrimary)
            }

            NotesTheme.divider.frame(height: 1)

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Wipe All Network History")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(NotesTheme.textPrimary)
                    Text("Erases all recorded bandwidth stats, interface baselines, and database tables back to fresh install state.")
                        .font(.caption)
                        .foregroundStyle(NotesTheme.textSecondary)
                }

                Spacer()

                Button {
                    showClearConfirmation = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash.fill")
                        Text("Clear All Data...")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(NotesTheme.red)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: NotesTheme.red.opacity(0.35), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .background(NotesTheme.red.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(NotesTheme.red.opacity(0.35), lineWidth: 1)
        }
    }
}

// MARK: - Crash Reports Sheet (Notes Theme)

private struct NotesCrashReportsSheet: View {
    let reports: [[String: Any]]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            NotesTheme.bgBase.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Crash Reports", systemImage: "exclamationmark.triangle.fill")
                            .font(.title2.bold())
                            .foregroundStyle(NotesTheme.accent)
                        Text("Reports recorded to Application Support prior to system crash re-raising.")
                            .font(.caption)
                            .foregroundStyle(NotesTheme.textSecondary)
                    }
                    Spacer()
                    Button("Done") { dismiss() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NotesTheme.bgBase)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(NotesTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .padding(20)

                NotesTheme.divider.frame(height: 1)

                if reports.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 36))
                            .foregroundStyle(NotesTheme.green)
                        Text("No Crash Reports")
                            .font(.headline)
                            .foregroundStyle(NotesTheme.textPrimary)
                        Text("No crash reports found on disk — the application is running stably.")
                            .font(.caption)
                            .foregroundStyle(NotesTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(reports.enumerated()), id: \.offset) { _, report in
                                NotesCrashReportRow(report: report)
                            }
                        }
                        .padding(16)
                    }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 400)
    }
}

private struct NotesCrashReportRow: View {
    let report: [String: Any]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                let type = report["type"] as? String ?? "unknown"
                Label(type == "signal" ? "Signal Crash" : "Exception Crash",
                      systemImage: type == "signal" ? "bolt.trianglebadge.exclamationmark.fill" : "xmark.octagon.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NotesTheme.accent)
                Spacer()
                if let ts = report["timestamp"] as? String {
                    Text(ts)
                        .font(.caption.monospaced())
                        .foregroundStyle(NotesTheme.textSecondary)
                }
            }

            NotesTheme.divider.frame(height: 1)

            VStack(alignment: .leading, spacing: 4) {
                if let sig = report["signal"] as? String {
                    row(label: "Signal", value: sig)
                }
                if let exc = report["exceptionName"] as? String {
                    row(label: "Exception", value: exc)
                }
                if let reason = report["reason"] as? String {
                    row(label: "Reason", value: reason)
                }
                if let version = report["appVersion"] as? String {
                    row(label: "App Version", value: version)
                }
                if let os = report["osVersion"] as? String {
                    row(label: "macOS", value: os)
                }
                if let pid = report["pid"] {
                    row(label: "PID", value: "\(pid)")
                }
            }

            if let callStack = report["callStack"] as? [String], !callStack.isEmpty {
                DisclosureGroup("Call Stack (\(callStack.count) frames)") {
                    Text(callStack.joined(separator: "\n"))
                        .font(.caption.monospaced())
                        .foregroundStyle(NotesTheme.textSecondary)
                        .textSelection(.enabled)
                        .padding(.top, 4)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(NotesTheme.accent)
            }
        }
        .padding(14)
        .background(NotesTheme.bgCardHover)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10).strokeBorder(NotesTheme.borderAccent, lineWidth: 1)
        }
    }

    private func row(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label + ":")
                .font(.caption.weight(.semibold))
                .foregroundStyle(NotesTheme.textSecondary)
                .frame(width: 90, alignment: .trailing)
            Text(value)
                .font(.caption)
                .foregroundStyle(NotesTheme.textPrimary)
                .textSelection(.enabled)
        }
    }
}
