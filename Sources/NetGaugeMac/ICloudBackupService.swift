import Foundation
import AppKit
import UniformTypeIdentifiers

// MARK: - iCloud Backup Model

struct ICloudBackupItem: Identifiable, Equatable, Sendable {
    var id: String { fileName }
    let url: URL
    let fileName: String
    let createdAt: Date
    let fileSizeBytes: Int64
    let sampleCount: Int
    let networksCount: Int
    let totalBytes: UInt64

    var formattedDate: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt.string(from: createdAt)
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }

    var formattedTraffic: String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: totalBytes), countStyle: .binary)
    }
}

// MARK: - iCloud Backup Service

@MainActor
final class ICloudBackupService: ObservableObject {
    static let shared = ICloudBackupService()

    @Published private(set) var backups: [ICloudBackupItem] = []
    @Published private(set) var isBackingUp = false
    @Published private(set) var isRestoring = false
    @Published private(set) var currentFolderURL: URL?
    @Published private(set) var isUsingCustomFolder = false
    @Published private(set) var lastBackupDate: Date?

    private let bookmarkKey = "iCloudBackupFolderBookmark"
    private let lastBackupDateKey = "iCloudLastBackupTimestamp"

    private init() {
        if let ts = UserDefaults.standard.object(forKey: lastBackupDateKey) as? Date {
            self.lastBackupDate = ts
        }
        refreshFolderAndBackups()
    }

    // MARK: – Folder Management

    func refreshFolderAndBackups() {
        let (folder, isCustom) = resolveBackupFolder()
        self.currentFolderURL = folder
        self.isUsingCustomFolder = isCustom
        loadBackups(from: folder, isSecurityScoped: isCustom)
    }

    var folderDisplayName: String {
        guard let url = currentFolderURL else { return "Default Storage" }
        if url.path.contains("Mobile Documents") || url.path.contains("CloudDocs") {
            return "iCloud Drive (\(url.lastPathComponent))"
        }
        return url.lastPathComponent
    }

    private func resolveBackupFolder() -> (url: URL, isCustom: Bool) {
        // 1. Try saved user-selected security-scoped bookmark (e.g. in iCloud Drive)
        if let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) {
            var isStale = false
            if let resolvedURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                if isStale, let newBookmark = try? resolvedURL.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                    UserDefaults.standard.set(newBookmark, forKey: bookmarkKey)
                }
                return (resolvedURL, true)
            }
        }

        // 2. Try ubiquity container Documents/Backups if system provisions it
        if let ubiquity = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            let cloudDocs = ubiquity.appendingPathComponent("Documents/NetGaugeBackups", isDirectory: true)
            try? FileManager.default.createDirectory(at: cloudDocs, withIntermediateDirectories: true)
            return (cloudDocs, false)
        }

        // 3. Fallback: Sandboxed Application Support NetGaugeMac/iCloudBackups
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let localBackupDir = support.appendingPathComponent("NetGaugeMac/iCloudBackups", isDirectory: true)
        try? FileManager.default.createDirectory(at: localBackupDir, withIntermediateDirectories: true)
        return (localBackupDir, false)
    }

    func promptSelectICloudFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select iCloud Drive Backup Folder"
        panel.message = "Choose a folder in iCloud Drive where NetGauge should automatically save and load backups."
        panel.prompt = "Select Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        // Default to iCloud Drive if accessible in Finder
        let home = FileManager.default.homeDirectoryForCurrentUser
        let cloudDocs = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        if FileManager.default.fileExists(atPath: cloudDocs.path) {
            panel.directoryURL = cloudDocs
        }

        if panel.runModal() == .OK, let selectedURL = panel.url {
            do {
                let bookmark = try selectedURL.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
                refreshFolderAndBackups()
                AppLogger.info(.store, "Configured custom backup directory: \(selectedURL.path)")
            } catch {
                AppLogger.error(.store, "Failed to create security-scoped bookmark: \(error.localizedDescription)")
            }
        }
    }

    func resetToDefaultFolder() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        refreshFolderAndBackups()
    }

    // MARK: – Backups Scanning

    func loadBackups(from folderURL: URL, isSecurityScoped: Bool) {
        let accessing = isSecurityScoped ? folderURL.startAccessingSecurityScopedResource() : false
        defer {
            if accessing { folderURL.stopAccessingSecurityScopedResource() }
        }

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            self.backups = []
            return
        }

        var items: [ICloudBackupItem] = []
        for file in contents {
            let ext = file.pathExtension.lowercased()
            guard ext == "ngbackup" || ext == "db" else { continue }

            let resourceValues = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let modDate = resourceValues?.contentModificationDate ?? Date()
            let size = Int64(resourceValues?.fileSize ?? 0)

            // Inspect metadata
            let meta = UsageStore.inspectBackupFile(at: file)

            items.append(
                ICloudBackupItem(
                    url: file,
                    fileName: file.lastPathComponent,
                    createdAt: modDate,
                    fileSizeBytes: size,
                    sampleCount: meta.sampleCount,
                    networksCount: meta.networksCount,
                    totalBytes: meta.totalBytes
                )
            )
        }

        // Sort latest backups first
        self.backups = items.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: – Backup Execution

    func performBackup(model: DashboardModel) async throws -> ICloudBackupItem {
        isBackingUp = true
        defer { isBackingUp = false }

        let (folder, isCustom) = resolveBackupFolder()
        let accessing = isCustom ? folder.startAccessingSecurityScopedResource() : false
        defer {
            if accessing { folder.stopAccessingSecurityScopedResource() }
        }

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestampStr = fmt.string(from: Date())
        let fileName = "NetGauge-Backup-\(timestampStr).ngbackup"
        let targetURL = folder.appendingPathComponent(fileName)

        try await model.backupDatabase(to: targetURL)

        let now = Date()
        self.lastBackupDate = now
        UserDefaults.standard.set(now, forKey: lastBackupDateKey)

        let values = try? targetURL.resourceValues(forKeys: [.fileSizeKey])
        let size = Int64(values?.fileSize ?? 0)
        let meta = UsageStore.inspectBackupFile(at: targetURL)

        let newItem = ICloudBackupItem(
            url: targetURL,
            fileName: fileName,
            createdAt: now,
            fileSizeBytes: size,
            sampleCount: meta.sampleCount,
            networksCount: meta.networksCount,
            totalBytes: meta.totalBytes
        )

        loadBackups(from: folder, isSecurityScoped: isCustom)
        return newItem
    }

    func promptExportBackup(model: DashboardModel) async throws -> URL? {
        let panel = NSSavePanel()
        panel.title = "Export NetGauge Backup"
        panel.message = "Choose a destination to export a full standalone snapshot of your network history."
        panel.prompt = "Export Backup"
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd-HHmmss"
        panel.nameFieldStringValue = "NetGauge-Backup-\(fmt.string(from: Date())).ngbackup"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType(filenameExtension: "ngbackup") ?? .data]

        // Suggest iCloud Drive
        let home = FileManager.default.homeDirectoryForCurrentUser
        let cloudDocs = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        if FileManager.default.fileExists(atPath: cloudDocs.path) {
            panel.directoryURL = cloudDocs
        }

        if panel.runModal() == .OK, let targetURL = panel.url {
            try await model.backupDatabase(to: targetURL)
            return targetURL
        }
        return nil
    }

    // MARK: – Restore Execution

    func performRestore(from fileURL: URL, model: DashboardModel) async throws {
        isRestoring = true
        defer { isRestoring = false }

        let folderAccessing = isUsingCustomFolder ? currentFolderURL?.startAccessingSecurityScopedResource() ?? false : false
        let fileAccessing = fileURL.startAccessingSecurityScopedResource()
        defer {
            if fileAccessing { fileURL.stopAccessingSecurityScopedResource() }
            if folderAccessing { currentFolderURL?.stopAccessingSecurityScopedResource() }
        }

        try await model.restoreDatabase(from: fileURL)
    }

    func promptImportAndRestore(model: DashboardModel) async throws -> Bool {
        let panel = NSOpenPanel()
        panel.title = "Select NetGauge Backup to Restore"
        panel.message = "Choose a .ngbackup or .db file to restore recorded network usage history."
        panel.prompt = "Restore Backup"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "ngbackup") ?? .data,
            UTType(filenameExtension: "db") ?? .data
        ]

        if let currentFolderURL {
            panel.directoryURL = currentFolderURL
        }

        if panel.runModal() == .OK, let selectedURL = panel.url {
            let accessing = selectedURL.startAccessingSecurityScopedResource()
            defer {
                if accessing { selectedURL.stopAccessingSecurityScopedResource() }
            }

            try await performRestore(from: selectedURL, model: model)
            return true
        }
        return false
    }

    // MARK: – Delete & Reveal

    func deleteBackup(item: ICloudBackupItem) throws {
        let isSecurityScoped = isUsingCustomFolder
        let accessing = isSecurityScoped ? currentFolderURL?.startAccessingSecurityScopedResource() ?? false : false
        defer {
            if accessing { currentFolderURL?.stopAccessingSecurityScopedResource() }
        }

        try FileManager.default.removeItem(at: item.url)
        if let currentFolderURL {
            loadBackups(from: currentFolderURL, isSecurityScoped: isSecurityScoped)
        }
    }

    func revealInFinder(item: ICloudBackupItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    // MARK: – Auto Backup Trigger

    func checkAndPerformAutoBackupIfNeeded(model: DashboardModel) async {
        let isAutoEnabled = UserDefaults.standard.bool(forKey: "isICloudAutoBackupEnabled")
        // Default to true if not set yet
        let enabled = UserDefaults.standard.object(forKey: "isICloudAutoBackupEnabled") == nil ? true : isAutoEnabled
        guard enabled else { return }

        let intervalHours: Double = 24.0 // Daily auto-backup
        if let last = lastBackupDate, Date().timeIntervalSince(last) < intervalHours * 3600 {
            // Already backed up within last 24h
            return
        }

        do {
            _ = try await performBackup(model: model)
            AppLogger.info(.store, "Automated background iCloud backup created successfully")
        } catch {
            AppLogger.error(.store, "Automated iCloud backup failed: \(error.localizedDescription)")
        }
    }
}
