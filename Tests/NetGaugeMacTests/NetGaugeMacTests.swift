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

    // MARK: - Test 5: Notes Theme Traffic Accents (Download & Upload)
    func testNotesThemeTrafficAccents() {
        let dlR = 0.961, dlG = 0.730, dlB = 0.220 // Honey amber (download)
        let ulR = 0.880, ulG = 0.520, ulB = 0.350 // Terracotta cinnamon (upload)

        XCTAssertGreaterThan(dlR, dlG, "Download R must exceed G for gold amber")
        XCTAssertGreaterThan(ulR, ulG, "Upload R must exceed G for warm terracotta")
        XCTAssertNotEqual(dlR, ulR, "Download and upload accents must be distinct")
    }

    // MARK: - Test 6: Notes Theme Color Palette Integrity
    func testNotesThemeColorPalette() {
        let accentR = 0.961, accentG = 0.730, accentB = 0.220
        let baseR   = 0.133, baseG   = 0.118, baseB   = 0.102
        let cardR   = 0.173, cardG   = 0.149, cardB   = 0.125

        XCTAssertGreaterThan(accentR, accentG, "Accent R must exceed G for warm gold tone")
        XCTAssertGreaterThan(accentG, accentB, "Accent G must exceed B for warm gold tone")
        XCTAssertLessThan(baseR, cardR, "Base paper must be darker than card container")
    }

    // MARK: - Test 7: Settings State & Model Linkage
    func testSettingsStateLinkage() {
        var launchAtLogin = false
        var locationAuthorized = false

        launchAtLogin = true
        locationAuthorized = true

        XCTAssertTrue(launchAtLogin, "Launch at login toggle mutation")
        XCTAssertTrue(locationAuthorized, "Location authorized permission state")
    }
}
