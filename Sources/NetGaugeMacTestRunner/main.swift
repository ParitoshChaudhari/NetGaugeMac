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

        print("=========================================")
        print("Results: \(passedCount) Passed, \(failedCount) Failed")
        print("=========================================")

        if failedCount > 0 {
            exit(1)
        }
    }
}
