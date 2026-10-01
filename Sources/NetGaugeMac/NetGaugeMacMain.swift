import AppKit
import SwiftUI

// MARK: - Custom Entry Point
//
// We need a custom @main entry point so CrashGuard.install() runs *before*
// NSApplication initialises. Signal handlers and exception handlers must be
// registered before any Obj-C / AppKit runtime activity.
//
// AppLogger also reads any crash context from a previous run here so the
// lifecycle log contains a complete picture from cold start.

@main
struct NetGaugeMacMain {
    static func main() {
        // 1. Install crash handlers — MUST be first
        CrashGuard.install()

        // 2. Check for a crash context left over from a previous run
        if let ctx = AppLogger.readLastCrashContext() {
            AppLogger.error(.lifecycle,
                "Previous session ended with a fault — category: \(ctx.category), " +
                "message: \(ctx.message), version: \(ctx.appVersion), " +
                "os: \(ctx.osVersion), at: \(ctx.timestamp)"
            )
            AppLogger.clearCrashContext()
        } else {
            AppLogger.info(.lifecycle, "Clean launch — no fault context from previous session")
        }

        // 3. Check for crash reports from previous runs
        let reports = CrashGuard.existingCrashReports()
        if !reports.isEmpty {
            AppLogger.notice(.lifecycle,
                "\(reports.count) crash report(s) on disk from previous session(s)"
            )
        }

        // 4. Hand off to the SwiftUI App lifecycle
        NetGaugeMacApp.main()
    }
}
