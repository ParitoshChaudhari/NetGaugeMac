import Foundation
import OSLog

// MARK: - Log Categories

/// Logging categories that map to separate os.Logger instances.
/// Each category gets its own named subsystem channel visible in Console.app.
enum NGCategory: String {
    case app        = "app"
    case network    = "network"
    case store      = "store"
    case ui         = "ui"
    case lifecycle  = "lifecycle"
}

// MARK: - Crash Context

/// Lightweight crash context written to disk on a fault-level log event.
/// Survives process death; read on next launch to detect crash loops.
struct CrashContext: Codable {
    let timestamp: Date
    let category: String
    let message: String
    let appVersion: String
    let osVersion: String
}

// MARK: - AppLogger

/// Centralized logging facade wrapping Apple's Unified Logging System (os.Logger).
///
/// Usage:
/// ```swift
/// AppLogger.info(.lifecycle, "App launched")
/// AppLogger.error(.store, "DB open failed: \(error.localizedDescription)")
/// AppLogger.fault(.network, "getifaddrs returned nil — sampling impossible")
/// ```
///
/// Logs are visible in Console.app filtered by subsystem
/// `com.paritoshchaudhari.NetGaugeMac`, or via:
/// ```
/// log stream --predicate 'subsystem == "com.paritoshchaudhari.NetGaugeMac"'
/// ```
enum AppLogger {

    // MARK: - Internal

    private static let subsystem = "com.paritoshchaudhari.NetGaugeMac"

    /// One Logger per category, created lazily.
    private static let loggers: [NGCategory: Logger] = {
        var map: [NGCategory: Logger] = [:]
        for cat in [NGCategory.app, .network, .store, .ui, .lifecycle] {
            map[cat] = Logger(subsystem: subsystem, category: cat.rawValue)
        }
        return map
    }()

    private static func logger(for category: NGCategory) -> Logger {
        loggers[category] ?? Logger(subsystem: subsystem, category: category.rawValue)
    }

    // MARK: - Crash Context Path

    static var crashContextURL: URL? {
        guard let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return support
            .appendingPathComponent("NetGaugeMac", isDirectory: true)
            .appendingPathComponent("crash_context.json")
    }

    // MARK: - Public Logging API

    /// Debug-level log (stripped in release builds, visible in Instruments/Console with debug filter).
    static func debug(_ category: NGCategory, _ message: String) {
        logger(for: category).debug("\(message, privacy: .public)")
    }

    /// Info-level log — general operational milestones.
    static func info(_ category: NGCategory, _ message: String) {
        logger(for: category).info("\(message, privacy: .public)")
    }

    /// Notice-level log — important but non-error events (e.g., memory cap flush triggered).
    static func notice(_ category: NGCategory, _ message: String) {
        logger(for: category).notice("\(message, privacy: .public)")
    }

    /// Error-level log — recoverable error. Included in crash reports by the OS.
    static func error(_ category: NGCategory, _ message: String) {
        logger(for: category).error("\(message, privacy: .public)")
    }

    /// Fault-level log — non-recoverable, crash-worthy condition.
    /// Also writes a `crash_context.json` sidecar file for next-launch diagnosis.
    static func fault(_ category: NGCategory, _ message: String) {
        logger(for: category).fault("\(message, privacy: .public)")
        writeCrashContext(category: category, message: message)
    }

    // MARK: - Crash Context I/O

    /// Reads the crash context written by a previous run (if any).
    /// Returns `nil` if no crash context exists.
    static func readLastCrashContext() -> CrashContext? {
        guard let url = crashContextURL,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CrashContext.self, from: data)
    }

    /// Removes the crash context file after it has been processed.
    static func clearCrashContext() {
        guard let url = crashContextURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Private Helpers

    private static func writeCrashContext(category: NGCategory, message: String) {
        guard let url = crashContextURL else { return }
        let context = CrashContext(
            timestamp: Date(),
            category: category.rawValue,
            message: message,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(context) else { return }
        // Create directory if needed (best-effort — may not exist at fault time)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

// MARK: - os_signpost Log Handle (Performance Profiling)

/// Signpost log for profiling the capture loop in Instruments.
/// Usage:
/// ```swift
/// let id = NGSignposter.captureLoop.beginInterval("captureOnce")
/// defer { NGSignposter.captureLoop.endInterval("captureOnce", id) }
/// ```
enum NGSignposter {
    static let captureLoop = OSSignposter(
        subsystem: "com.paritoshchaudhari.NetGaugeMac",
        category: "CaptureLoop"
    )
}
