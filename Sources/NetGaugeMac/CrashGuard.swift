import Foundation
import Darwin

// MARK: - CrashGuard

/// Installs pre-launch crash safety nets:
///   1. `NSSetUncaughtExceptionHandler` — catches Obj-C / bridged Swift exceptions
///   2. POSIX signal handlers for `SIGABRT`, `SIGSEGV`, `SIGBUS`, `SIGILL`, `SIGFPE`
///
/// Both handlers write a JSON crash report file to Application Support before re-raising
/// so the system's crash reporter (and .crash file generation) still fires normally.
///
/// Call `CrashGuard.install()` as the **very first thing** before `NSApplication.main()`.
enum CrashGuard {

    // MARK: - Constants

    private static let maxCrashReports = 5
    private static let reportPrefix    = "crash_report_"

    // MARK: - Public API

    /// Installs all crash handlers. Safe to call multiple times (idempotent).
    static func install() {
        createCrashDirectory()
        pruneOldReports()
        installExceptionHandler()
        installSignalHandlers()
        AppLogger.info(.lifecycle, "CrashGuard installed — monitoring SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE")
    }

    // MARK: - Crash Report Directory

    static var crashReportDirectory: URL? {
        guard let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return support.appendingPathComponent("NetGaugeMac", isDirectory: true)
    }

    private static func createCrashDirectory() {
        guard let dir = crashReportDirectory else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    // MARK: - Pruning

    /// Keeps only the most recent `maxCrashReports` crash report files.
    static func pruneOldReports() {
        guard let dir = crashReportDirectory else { return }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        let reports = files
            .filter { $0.hasPrefix(reportPrefix) && $0.hasSuffix(".json") }
            .sorted()
        if reports.count > maxCrashReports {
            let toDelete = reports.prefix(reports.count - maxCrashReports)
            for name in toDelete {
                try? fm.removeItem(at: dir.appendingPathComponent(name))
            }
        }
    }

    // MARK: - Existing Crash Reports

    /// Returns all crash reports sorted newest-first, as decoded dictionaries.
    static func existingCrashReports() -> [[String: Any]] {
        guard let dir = crashReportDirectory else { return [] }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: dir.path) else { return [] }
        return files
            .filter { $0.hasPrefix(reportPrefix) && $0.hasSuffix(".json") }
            .sorted()
            .reversed()
            .compactMap { name -> [String: Any]? in
                let url = dir.appendingPathComponent(name)
                guard let data = try? Data(contentsOf: url),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return nil }
                return json
            }
    }

    // MARK: - Obj-C Exception Handler

    private static func installExceptionHandler() {
        NSSetUncaughtExceptionHandler { exception in
            let name    = exception.name.rawValue
            let reason  = exception.reason ?? "no reason"
            let symbols = exception.callStackSymbols.prefix(20).joined(separator: "\n")
            let msg     = "Uncaught exception: \(name) — \(reason)\n\(symbols)"

            // Write via AppLogger (fault level) — also persists crash_context.json
            AppLogger.fault(.app, msg)

            // Write structured JSON crash report
            CrashGuard.writeExceptionReport(name: name, reason: reason, symbols: Array(exception.callStackSymbols.prefix(20)))
        }
    }

    private static func writeExceptionReport(name: String, reason: String, symbols: [String]) {
        guard let dir = crashReportDirectory else { return }
        let ts = Int(Date().timeIntervalSince1970)
        let url = dir.appendingPathComponent("\(reportPrefix)\(ts)_exception.json")

        let payload: [String: Any] = [
            "type":          "exception",
            "exceptionName": name,
            "reason":        reason,
            "callStack":     symbols,
            "timestamp":     ISO8601DateFormatter().string(from: Date()),
            "appVersion":    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "osVersion":     ProcessInfo.processInfo.operatingSystemVersionString,
            "pid":           ProcessInfo.processInfo.processIdentifier
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - POSIX Signal Handlers

    private static func installSignalHandlers() {
        // Populate nonisolated(unsafe) globals with signal-safe static strings.
        // These are written once before any signal can fire and then only read inside
        // the handler, so there is no concurrent mutation — nonisolated(unsafe) is correct.
        if let dirPath = crashReportDirectory?.path {
            CrashGuardGlobals.crashDirPath = dirPath
        }
        CrashGuardGlobals.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"

        for sig in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE] {
            signal(sig) { signum in
                // === ASYNC-SIGNAL-SAFE ZONE ===
                // We use only write(2) and open(2) syscalls. No malloc, no ObjC, no Swift runtime.
                CrashGuardGlobals.writeSignalCrashReport(signal: signum)
                // Re-raise so the OS crash reporter fires and generates a .crash file
                signal(signum, SIG_DFL)
                raise(signum)
            }
        }
    }
}

// MARK: - Signal-Safe Globals

/// Global state used inside signal handlers.
/// Fields are plain Swift Strings written once at startup (before signals fire)
/// and only read inside the signal handler — protected by write-once semantics.
/// `nonisolated(unsafe)` disables Swift concurrency checks because signal handlers
/// run outside any actor and access these before malloc is available.
enum CrashGuardGlobals {
    // nonisolated(unsafe): Written once at install() time, read-only after that.
    // Safe because the write happens before any signal can be delivered.
    nonisolated(unsafe) static var crashDirPath: String = ""
    nonisolated(unsafe) static var appVersion: String = ""

    /// Writes a minimal crash report using only async-signal-safe syscalls.
    /// Builds a compact JSON string without Foundation/malloc, then writes it
    /// atomically using open(2) + write(2) + close(2).
    static func writeSignalCrashReport(signal signum: Int32) {
        // Resolve signal name without any heap allocation
        let sigName: String
        switch signum {
        case SIGABRT: sigName = "SIGABRT"
        case SIGSEGV: sigName = "SIGSEGV"
        case SIGBUS:  sigName = "SIGBUS"
        case SIGILL:  sigName = "SIGILL"
        case SIGFPE:  sigName = "SIGFPE"
        default:      sigName = "SIGUNKNOWN"
        }

        let ts  = Int(time(nil))
        let pid = Int(getpid())

        // Build path using only string concatenation (no format functions)
        let path = "\(crashDirPath)/crash_report_\(ts)_signal.json"

        // Build minimal JSON without Foundation
        let json = """
        {"type":"signal","signal":"\(sigName)","signalNumber":\(signum),"pid":\(pid),"timestamp":\(ts),"appVersion":"\(appVersion)"}
        """

        // Write using only open(2)/write(2)/close(2) — async-signal-safe
        path.withCString { pathPtr in
            let fd = open(pathPtr, O_WRONLY | O_CREAT | O_TRUNC, 0o644 as mode_t)
            if fd >= 0 {
                json.withCString { jsonPtr in
                    let len = strlen(jsonPtr)
                    _ = Darwin.write(fd, jsonPtr, len)
                }
                Darwin.close(fd)
            }
        }
    }
}
