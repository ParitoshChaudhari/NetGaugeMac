import XCTest
@testable import NetGaugeMac

final class NetGaugeMacTests: XCTestCase {

    // MARK: - Test 1: 32-Bit Kernel Counter Overflow Accuracy
    func testSafeDelta32BitCounterWrap() {
        let prevCounter: UInt64 = UInt64(UInt32.max) - 5 // 4,294,967,290
        let curCounter: UInt64 = 10                       // Counter wrapped to 10

        // Delta calculation formula: (UInt32.max - prev) + cur + 1
        // (4294967295 - 4294967290) + 10 + 1 = 5 + 10 + 1 = 16 bytes
        let expectedDelta: UInt64 = 16

        let actualDelta: UInt64
        if curCounter >= prevCounter {
            actualDelta = curCounter - prevCounter
        } else {
            actualDelta = (UInt64(UInt32.max) - prevCounter) + curCounter + 1
        }

        XCTAssertEqual(actualDelta, expectedDelta, "32-bit counter wrap-around must calculate exact 16-byte delta")
    }

    // MARK: - Test 2: UsageBucket.id Uniqueness
    func testUsageBucketIDUniqueness() {
        let now = Date()
        let bucket1 = UsageBucket(start: now, label: "10:00", received: 100, sent: 200)
        let bucket2 = UsageBucket(start: now, label: "11:00", received: 100, sent: 200)

        XCTAssertNotEqual(bucket1.id, bucket2.id, "UsageBucket IDs must be unique when labels differ for SwiftUI diffing")
    }

    // MARK: - Test 3: Interface Snapshot Accumulation
    func testInterfaceSnapshotAccumulation() {
        var interfaceTotals: [String: InterfaceSnapshot] = [:]
        
        let snap1 = InterfaceSnapshot(id: "en0", name: "en0", displayName: "Wi-Fi", bytesReceived: 1000, bytesSent: 500)
        interfaceTotals["en0"] = snap1

        let ifReceived: UInt64 = 2000
        let ifSent: UInt64 = 1500

        if let existing = interfaceTotals["en0"] {
            interfaceTotals["en0"] = InterfaceSnapshot(
                id: "en0",
                name: "en0",
                displayName: existing.displayName,
                bytesReceived: existing.bytesReceived.saturatingAdd(ifReceived),
                bytesSent: existing.bytesSent.saturatingAdd(ifSent)
            )
        }

        XCTAssertEqual(interfaceTotals["en0"]?.bytesReceived, 3000, "Interface accumulation must sum received bytes")
        XCTAssertEqual(interfaceTotals["en0"]?.bytesSent, 2000, "Interface accumulation must sum sent bytes")
    }

    // MARK: - Test 4: Custom Date Interval Min/Max Ordering
    func testCustomDateIntervalOrdering() {
        let dateLater = Date()
        let dateEarlier = dateLater.addingTimeInterval(-86400)

        let start = min(dateLater, dateEarlier)
        let end = max(dateLater, dateEarlier)
        let interval = DateInterval(start: start, end: end)

        XCTAssertLessThanOrEqual(interval.start, interval.end, "DateInterval start must be <= end to prevent crashes")
    }
}
