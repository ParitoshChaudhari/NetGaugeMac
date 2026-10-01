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

    // Export Data State
    @State private var exportScope: ExportScope = .all
    @State private var exportStartDate: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var exportEndDate: Date = Date()
    @State private var isExporting: Bool = false
    @State private var exportingFormat: ExportFormat? = nil
    @State private var exportToastMessage: String? = nil
    @State private var exportedFileURL: URL? = nil
    @State private var showExportErrorAlert = false
    @State private var exportErrorMessage = ""

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

                    exportCard

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
            } else if let msg = exportToastMessage {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(NotesTheme.green)
                    Text(msg)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NotesTheme.textPrimary)

                    if let url = exportedFileURL {
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "folder")
                                Text("Reveal in Finder")
                            }
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(NotesTheme.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(NotesTheme.accentBg)
                            .clipShape(Capsule())
                            .overlay {
                                Capsule().strokeBorder(NotesTheme.accentBorder, lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
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
        .animation(.snappy(duration: 0.25), value: exportToastMessage)
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
        .alert("Export Error", isPresented: $showExportErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(exportErrorMessage)
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

    // MARK: - Card: Export Data

    private var exportCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.up.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NotesTheme.accent)
                Text("Export Network Usage Data")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NotesTheme.textPrimary)

                Spacer()

                Text("PDF · Excel · JSON")
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

            NotesTheme.divider.frame(height: 1)

            Text("Export your network usage history with detailed Wi-Fi / Personal Hotspot breakdowns, download & upload statistics, and monthly summaries.")
                .font(.caption)
                .foregroundStyle(NotesTheme.textSecondary)

            // Scope Selector: All Data vs Date Range
            VStack(alignment: .leading, spacing: 8) {
                Text("Export Scope:")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NotesTheme.textSecondary)

                HStack(spacing: 10) {
                    ForEach(ExportScope.allCases) { scope in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                exportScope = scope
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: exportScope == scope ? "record.circle.fill" : "circle")
                                    .font(.system(size: 13))
                                Text(scope.rawValue)
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundStyle(exportScope == scope ? NotesTheme.accent : NotesTheme.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(exportScope == scope ? NotesTheme.accentBg : NotesTheme.bgCardHover)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(exportScope == scope ? NotesTheme.accentBorder : NotesTheme.border, lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()
                }
            }

            // Date Range pickers when .dateRange is chosen
            if exportScope == .dateRange {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("From Date:")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(NotesTheme.textSecondary)
                        DatePicker("", selection: $exportStartDate, in: ...exportEndDate, displayedComponents: [.date])
                            .datePickerStyle(.compact)
                            .labelsHidden()
                    }

                    Image(systemName: "arrow.right")
                        .font(.system(size: 12))
                        .foregroundStyle(NotesTheme.textMuted)
                        .padding(.top, 14)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("To Date:")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(NotesTheme.textSecondary)
                        DatePicker("", selection: $exportEndDate, in: exportStartDate...Date(), displayedComponents: [.date])
                            .datePickerStyle(.compact)
                            .labelsHidden()
                    }

                    Spacer()

                    // Quick presets
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Presets:")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(NotesTheme.textSecondary)
                        HStack(spacing: 6) {
                            presetButton(title: "7D") {
                                exportStartDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
                                exportEndDate = Date()
                            }
                            presetButton(title: "30D") {
                                exportStartDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
                                exportEndDate = Date()
                            }
                            presetButton(title: "This Month") {
                                let start = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
                                exportStartDate = start
                                exportEndDate = Date()
                            }
                        }
                    }
                }
                .padding(12)
                .background(NotesTheme.bgCardHover)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(NotesTheme.borderAccent, lineWidth: 1)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            NotesTheme.divider.frame(height: 1)

            // 3 Format Export Options
            VStack(spacing: 10) {
                exportFormatRow(
                    format: .pdf,
                    icon: "doc.richtext.fill",
                    color: NotesTheme.accent,
                    badge: "PDF Document",
                    title: "Visual PDF Report (.pdf)",
                    description: "Formatted document with KPI cards, monthly summaries, Wi-Fi & Hotspot breakdown, and daily details.",
                    buttonTitle: "Export PDF..."
                )

                exportFormatRow(
                    format: .excel,
                    icon: "tablecells.fill",
                    color: NotesTheme.green,
                    badge: "Excel (.xlsx)",
                    title: "Excel Spreadsheet (.xlsx)",
                    description: "Multi-sheet workbook with Executive Overview, Monthly Summary, Hotspots, and Daily Records.",
                    buttonTitle: "Export Excel..."
                )

                exportFormatRow(
                    format: .json,
                    icon: "curlybraces",
                    color: NotesTheme.upload,
                    badge: "JSON Archive",
                    title: "Raw JSON Dataset (.json)",
                    description: "Structured raw data export for backups, scripting, custom analytics, and data science.",
                    buttonTitle: "Export JSON..."
                )
            }

            if isExporting {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Generating \(exportingFormat?.rawValue ?? "export")...")
                        .font(.caption)
                        .foregroundStyle(NotesTheme.accent)
                }
                .padding(.top, 4)
            }
        }
        .padding(18)
        .notesCard()
    }

    private func presetButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(NotesTheme.textPrimary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(NotesTheme.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay {
                    RoundedRectangle(cornerRadius: 4).strokeBorder(NotesTheme.border, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func exportFormatRow(
        format: ExportFormat,
        icon: String,
        color: Color,
        badge: String,
        title: String,
        description: String,
        buttonTitle: String
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(NotesTheme.textPrimary)
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(color.opacity(0.12))
                        .clipShape(Capsule())
                }
                Text(description)
                    .font(.caption2)
                    .foregroundStyle(NotesTheme.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            Button {
                performExport(format: format)
            } label: {
                HStack(spacing: 5) {
                    if isExporting && exportingFormat == format {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.down.doc.fill")
                    }
                    Text(buttonTitle)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NotesTheme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(NotesTheme.bgCardHover)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6).strokeBorder(NotesTheme.border, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .disabled(isExporting)
        }
        .padding(10)
        .background(NotesTheme.bgCardHover.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func performExport(format: ExportFormat) {
        Task { @MainActor in
            isExporting = true
            exportingFormat = format
            defer {
                isExporting = false
                exportingFormat = nil
            }
            do {
                let report = try await model.buildExportReport(
                    scope: exportScope,
                    startDate: exportStartDate,
                    endDate: exportEndDate
                )

                let data: Data
                let ext = format.fileExtension
                let dateStr: String
                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd"
                if exportScope == .all {
                    dateStr = "All_Data_\(df.string(from: Date()))"
                } else {
                    dateStr = "\(df.string(from: exportStartDate))_to_\(df.string(from: exportEndDate))"
                }
                let defaultFilename = "NetGauge_\(format == .json ? "Data" : "Report")_\(dateStr).\(ext)"

                switch format {
                case .pdf:
                    data = DataExportService.shared.generatePDF(report: report)
                case .excel:
                    data = DataExportService.shared.generateExcel(report: report)
                case .json:
                    data = try DataExportService.shared.generateJSON(report: report)
                }

                if let savedURL = try await DataExportService.shared.promptSave(
                    format: format,
                    data: data,
                    defaultFilename: defaultFilename
                ) {
                    exportedFileURL = savedURL
                    withAnimation {
                        exportToastMessage = "\(format.rawValue) saved to \(savedURL.lastPathComponent)"
                    }
                    AppLogger.info(.ui, "Successfully exported \(format.rawValue) to \(savedURL.path)")
                    Task {
                        try? await Task.sleep(for: .seconds(6))
                        await MainActor.run {
                            withAnimation {
                                exportToastMessage = nil
                            }
                        }
                    }
                }
            } catch {
                exportErrorMessage = error.localizedDescription
                showExportErrorAlert = true
                AppLogger.error(.ui, "Export failed for \(format.rawValue): \(error.localizedDescription)")
            }
        }
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
