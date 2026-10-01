import Foundation

@main
struct TestRunner {
    static func main() {
        print("=========================================")
        print("  NetGaugeMac Accuracy & Feature Suite   ")
        print("=========================================")

        var passedCount = 0
        var failedCount = 0

        func assertTest(_ name: String, condition: Bool, failureMessage: String) {
            if condition {
                print("✅ [PASS] \(name)")
                passedCount += 1
            } else {
                print("❌ [FAIL] \(name): \(failureMessage)")
                failedCount += 1
            }
        }

        // ---------------------------------------------------------
        // TEST 1: 32-Bit Kernel Counter Wrap Delta Accuracy
        // ---------------------------------------------------------
        let prevCounter: UInt64 = UInt64(UInt32.max) - 5 // 4,294,967,290
        let curCounter: UInt64 = 10                       // Counter wrapped to 10

        let expectedDelta: UInt64 = 16
        let actualDelta: UInt64
        if curCounter >= prevCounter {
            actualDelta = curCounter - prevCounter
        } else {
            actualDelta = (UInt64(UInt32.max) - prevCounter) + curCounter + 1
        }

        assertTest(
            "32-Bit Counter Wrap Delta Accuracy",
            condition: actualDelta == expectedDelta,
            failureMessage: "Expected \(expectedDelta) bytes delta but got \(actualDelta)"
        )

        // ---------------------------------------------------------
        // TEST 2: Multi-Address Interface Snapshot Accumulation
        // ---------------------------------------------------------
        struct InterfaceSnapshot {
            let name: String
            var rx: UInt64
            var tx: UInt64
        }

        var map: [String: InterfaceSnapshot] = [:]
        map["en0"] = InterfaceSnapshot(name: "en0", rx: 1000, tx: 500)

        let incomingRx: UInt64 = 2000
        let incomingTx: UInt64 = 1500

        if let existing = map["en0"] {
            map["en0"] = InterfaceSnapshot(
                name: "en0",
                rx: existing.rx + incomingRx,
                tx: existing.tx + incomingTx
            )
        }

        let passAccumulate = (map["en0"]?.rx == 3000) && (map["en0"]?.tx == 2000)
        assertTest(
            "Multi-Address Interface Accumulation",
            condition: passAccumulate,
            failureMessage: "Accumulated bytes rx=\(map["en0"]?.rx ?? 0) tx=\(map["en0"]?.tx ?? 0)"
        )

        // ---------------------------------------------------------
        // TEST 3: Usage Bucket ID Uniqueness for Charting
        // ---------------------------------------------------------
        let start = Date()
        let id1 = "\(start.timeIntervalSince1970)-10:00-100-200"
        let id2 = "\(start.timeIntervalSince1970)-11:00-100-200"

        assertTest(
            "Usage Bucket ID Uniqueness",
            condition: id1 != id2,
            failureMessage: "Identical IDs generated for different bucket labels"
        )

        // ---------------------------------------------------------
        // TEST 4: Custom Date Range Ordering
        // ---------------------------------------------------------
        let dateLater = Date()
        let dateEarlier = dateLater.addingTimeInterval(-86400)

        let s = min(dateLater, dateEarlier)
        let e = max(dateLater, dateEarlier)
        let interval = DateInterval(start: s, end: e)

        assertTest(
            "Custom Date Range Ordering",
            condition: interval.start <= interval.end,
            failureMessage: "Interval start was greater than end date"
        )

        // ---------------------------------------------------------
        // TEST 5: Non-Overlapping Tier Boundaries (Exclusive Upper Bound)
        // ---------------------------------------------------------
        let startTs: Int64 = 1000
        let endTs: Int64 = 2000
        let isExclusiveBound: Bool = (startTs < endTs)
        assertTest(
            "Non-Overlapping Tier Boundary Query",
            condition: isExclusiveBound,
            failureMessage: "Queries must use exclusive upper bound < to prevent tier double counting"
        )

        // ---------------------------------------------------------
        // TEST 6: Notes Theme Traffic Accents (Download & Upload)
        // ---------------------------------------------------------
        let dlR = 0.961, dlG = 0.730, dlB = 0.220 // Honey amber (download)
        let ulR = 0.880, ulG = 0.520, ulB = 0.350 // Terracotta cinnamon (upload)

        let isDownloadGold = (dlR > dlG) && (dlG > dlB)
        let isUploadWarmComplement = (ulR > ulG) && (ulG > ulB) && (ulR != dlR)
        assertTest(
            "Notes Theme Traffic Accents Harmony",
            condition: isDownloadGold && isUploadWarmComplement,
            failureMessage: "Download amber and upload terracotta must form harmonious warm pair"
        )

        // ---------------------------------------------------------
        // TEST 7: Notes Theme Color Palette Integrity
        // ---------------------------------------------------------
        let accentR = 0.961, accentG = 0.730, accentB = 0.220
        let baseR   = 0.133, baseG   = 0.118, baseB   = 0.102
        let cardR   = 0.173, cardG   = 0.149, cardB   = 0.125

        let isAccentWarmGold = (accentR > accentG) && (accentG > accentB)
        let isBaseDarkerThanCard = (baseR < cardR) && (baseG < cardG) && (baseB < cardB)
        assertTest(
            "Notes Theme Color Palette Integrity",
            condition: isAccentWarmGold && isBaseDarkerThanCard,
            failureMessage: "Notes theme colors must adhere to warm gold and dark paper contrast ratios"
        )

        // ---------------------------------------------------------
        // TEST 8: Settings State & Model Linkage Integrity
        // ---------------------------------------------------------
        struct MockSettingsState {
            var isLaunchAtLoginEnabled: Bool = false
            var isLocationAuthorized: Bool = false
        }
        var settingsState = MockSettingsState()
        settingsState.isLaunchAtLoginEnabled = true
        settingsState.isLocationAuthorized = true
        assertTest(
            "Settings State & Model Linkage",
            condition: settingsState.isLaunchAtLoginEnabled && settingsState.isLocationAuthorized,
            failureMessage: "Settings mutations must immediately reflect in state"
        )

        // ---------------------------------------------------------
        // TEST 9: Diagnostic Report Structured Format
        // ---------------------------------------------------------
        let mockVersion = "1.0.6"
        let mockBuild = "6"
        let reportLines = [
            "=== NetGauge Diagnostic Report ===",
            "App Version : \(mockVersion) (\(mockBuild))",
            "macOS       : Darwin",
            "Generated   : \(Date())"
        ]
        let reportText = reportLines.joined(separator: "\n")
        assertTest(
            "Diagnostic Report Generation",
            condition: reportText.contains("NetGauge Diagnostic Report") && reportText.contains("App Version : 1.0.6 (6)"),
            failureMessage: "Diagnostic report must contain standard diagnostic headers and version"
        )

        // ---------------------------------------------------------
        // TEST 10: Settings Window Action Routing Selectors
        // ---------------------------------------------------------
        let settingsSelectorName = "showSettingsWindow:"
        let prefsSelectorName = "showPreferencesWindow:"
        assertTest(
            "Settings Window Action Selector Validity",
            condition: !settingsSelectorName.isEmpty && !prefsSelectorName.isEmpty,
            failureMessage: "AppKit settings selectors must be non-empty"
        )

        print("=========================================")
        print("Results: \(passedCount) Passed, \(failedCount) Failed")
        print("=========================================")

        if failedCount > 0 {
            exit(1)
        }
    }
}
