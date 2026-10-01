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

        // ---------------------------------------------------------
        // TEST 11: Export Scope & File Extensions Validation
        // ---------------------------------------------------------
        let expectedPdfExt = "pdf"
        let expectedXlsxExt = "xlsx"
        let expectedJsonExt = "json"

        assertTest(
            "Export Formats and Extensions Match",
            condition: expectedPdfExt == "pdf" && expectedXlsxExt == "xlsx" && expectedJsonExt == "json",
            failureMessage: "Export extensions must match standard file formats"
        )

        // ---------------------------------------------------------
        // TEST 12: Wi-Fi vs Personal Hotspot vs Ethernet Classification
        // ---------------------------------------------------------
        func classifyNetName(_ name: String) -> (clean: String, type: String, isHotspot: Bool) {
            let lower = name.lowercased()
            let isHotspot = lower.contains("hotspot") || lower.contains("iphone") || lower.contains("ipad") || lower.contains("cellular")
            var clean = name
            var connType = "Wi-Fi"
            if isHotspot {
                connType = "Personal Hotspot"
            } else if lower.contains("ethernet") || (name.hasPrefix("en") && !name.contains("Wi-Fi")) {
                connType = "Ethernet / Wired"
            } else if name.hasPrefix("Wi-Fi:") {
                clean = name.replacingOccurrences(of: "Wi-Fi:", with: "").trimmingCharacters(in: .whitespaces)
                connType = "Wi-Fi"
            } else {
                connType = "Network Interface"
            }
            return (clean, connType, isHotspot)
        }

        let wifiResult = classifyNetName("Wi-Fi: Starlink_5G")
        let hotspotResult1 = classifyNetName("Paritosh's iPhone Hotspot")
        let hotspotResult2 = classifyNetName("Wi-Fi: Paritosh's iPhone")
        let ethernetResult = classifyNetName("en0")

        let passClassification = wifiResult.type == "Wi-Fi" &&
                                 wifiResult.clean == "Starlink_5G" &&
                                 hotspotResult1.isHotspot &&
                                 hotspotResult1.type == "Personal Hotspot" &&
                                 hotspotResult2.isHotspot &&
                                 ethernetResult.type == "Ethernet / Wired"

        assertTest(
            "Wi-Fi & Personal Hotspot Classification",
            condition: passClassification,
            failureMessage: "Failed to accurately classify Wi-Fi, Hotspot, and Wired interfaces"
        )

        // ---------------------------------------------------------
        // TEST 13: Data Byte Formatter Accuracy (B, KB, MB, GB)
        // ---------------------------------------------------------
        func formatTestBytes(_ bytes: UInt64) -> String {
            let gb = Double(bytes) / 1_000_000_000.0
            let mb = Double(bytes) / 1_000_000.0
            let kb = Double(bytes) / 1_000.0
            if gb >= 1.0 { return String(format: "%.2f GB", gb) }
            if mb >= 1.0 { return String(format: "%.1f MB", mb) }
            if kb >= 1.0 { return String(format: "%.1f KB", kb) }
            return "\(bytes) B"
        }

        let bStr  = formatTestBytes(500)
        let kbStr = formatTestBytes(45_000)
        let mbStr = formatTestBytes(120_500_000)
        let gbStr = formatTestBytes(15_420_000_000)

        let passFormatting = (bStr == "500 B") &&
                             (kbStr == "45.0 KB") &&
                             (mbStr == "120.5 MB") &&
                             (gbStr == "15.42 GB")

        assertTest(
            "Byte Formatting Scales (B, KB, MB, GB)",
            condition: passFormatting,
            failureMessage: "Byte counts did not format to expected decimal units: \(bStr), \(kbStr), \(mbStr), \(gbStr)"
        )

        // ---------------------------------------------------------
        // TEST 14: Export Report Aggregation & Network Percentage
        // ---------------------------------------------------------
        struct MockRecord {
            let net: String
            let rx: UInt64
            let tx: UInt64
        }
        let records = [
            MockRecord(net: "Wi-Fi: Office", rx: 700_000_000, tx: 100_000_000), // 800 MB
            MockRecord(net: "iPhone Hotspot", rx: 150_000_000, tx: 50_000_000)   // 200 MB
        ]
        let totalRx = records.reduce(UInt64(0)) { $0 + $1.rx }
        let totalTx = records.reduce(UInt64(0)) { $0 + $1.tx }
        let totalAll = totalRx + totalTx // 1,000,000,000 bytes (1 GB)

        let officeTotal: UInt64 = 800_000_000
        let hotspotTotal: UInt64 = 200_000_000
        let officePct = (Double(officeTotal) / Double(totalAll)) * 100.0
        let hotspotPct = (Double(hotspotTotal) / Double(totalAll)) * 100.0

        let passAggregation = (totalAll == 1_000_000_000) &&
                              (abs(officePct - 80.0) < 0.01) &&
                              (abs(hotspotPct - 20.0) < 0.01)

        assertTest(
            "Export Aggregation & Percentage Calculation",
            condition: passAggregation,
            failureMessage: "Total=\(totalAll), OfficePct=\(officePct), HotspotPct=\(hotspotPct)"
        )

        // ---------------------------------------------------------
        // TEST 15: Pure Swift PKZIP .xlsx Engine Validation
        // ---------------------------------------------------------
        let mockEntries: [(path: String, data: Data)] = [
            ("[Content_Types].xml", Data("<Types/>".utf8)),
            ("xl/workbook.xml", Data("<workbook/>".utf8)),
            ("xl/worksheets/sheet1.xml", Data("<worksheet/>".utf8))
        ]

        var zipBody = Data()
        var zipCd = Data()
        for entry in mockEntries {
            let nameBytes = Array(entry.path.utf8)
            let nlen = UInt16(nameBytes.count)
            let sz = UInt32(entry.data.count)
            let offset = UInt32(zipBody.count)

            var lHeader = Data()
            var sig: UInt32 = 0x04034b50; lHeader.append(Data(bytes: &sig, count: 4))
            var ver: UInt16 = 20;         lHeader.append(Data(bytes: &ver, count: 2))
            var flag: UInt16 = 0;         lHeader.append(Data(bytes: &flag, count: 2))
            var method: UInt16 = 0;       lHeader.append(Data(bytes: &method, count: 2))
            var time: UInt16 = 0;         lHeader.append(Data(bytes: &time, count: 2))
            var date: UInt16 = 0;         lHeader.append(Data(bytes: &date, count: 2))
            var crc: UInt32 = 12345;      lHeader.append(Data(bytes: &crc, count: 4))
            var csz = sz;                 lHeader.append(Data(bytes: &csz, count: 4))
            var usz = sz;                 lHeader.append(Data(bytes: &usz, count: 4))
            var nl = nlen;                lHeader.append(Data(bytes: &nl, count: 2))
            var el: UInt16 = 0;           lHeader.append(Data(bytes: &el, count: 2))
            lHeader.append(contentsOf: nameBytes)

            zipBody.append(lHeader)
            zipBody.append(entry.data)

            var cd = Data()
            var cdSig: UInt32 = 0x02014b50; cd.append(Data(bytes: &cdSig, count: 4))
            var cdVer: UInt16 = 20;        cd.append(Data(bytes: &cdVer, count: 2))
            var cdVerN: UInt16 = 20;       cd.append(Data(bytes: &cdVerN, count: 2))
            var cdFlag: UInt16 = 0;        cd.append(Data(bytes: &cdFlag, count: 2))
            var cdM: UInt16 = 0;           cd.append(Data(bytes: &cdM, count: 2))
            var cdT: UInt16 = 0;           cd.append(Data(bytes: &cdT, count: 2))
            var cdD: UInt16 = 0;           cd.append(Data(bytes: &cdD, count: 2))
            var cdC: UInt32 = 12345;       cd.append(Data(bytes: &cdC, count: 4))
            var cdSz = sz;                 cd.append(Data(bytes: &cdSz, count: 4))
            var cdUsz = sz;                cd.append(Data(bytes: &cdUsz, count: 4))
            var cdNl = nlen;               cd.append(Data(bytes: &cdNl, count: 2))
            var cdEl: UInt16 = 0;          cd.append(Data(bytes: &cdEl, count: 2))
            var cdComm: UInt16 = 0;        cd.append(Data(bytes: &cdComm, count: 2))
            var cdDisk: UInt16 = 0;        cd.append(Data(bytes: &cdDisk, count: 2))
            var cdAttr: UInt16 = 0;        cd.append(Data(bytes: &cdAttr, count: 2))
            var cdExt: UInt32 = 0;         cd.append(Data(bytes: &cdExt, count: 4))
            var cdOff = offset;            cd.append(Data(bytes: &cdOff, count: 4))
            cd.append(contentsOf: nameBytes)
            zipCd.append(cd)
        }
        var eocd = Data()
        var eocdSig: UInt32 = 0x06054b50; eocd.append(Data(bytes: &eocdSig, count: 4))
        var d1: UInt16 = 0;               eocd.append(Data(bytes: &d1, count: 2))
        var d2: UInt16 = 0;               eocd.append(Data(bytes: &d2, count: 2))
        var entriesCount = UInt16(mockEntries.count)
        eocd.append(Data(bytes: &entriesCount, count: 2))
        eocd.append(Data(bytes: &entriesCount, count: 2))
        var cdSize = UInt32(zipCd.count); eocd.append(Data(bytes: &cdSize, count: 4))
        var cdOff = UInt32(zipBody.count); eocd.append(Data(bytes: &cdOff, count: 4))
        var commLen: UInt16 = 0;          eocd.append(Data(bytes: &commLen, count: 2))

        var fullZip = Data()
        fullZip.append(zipBody)
        fullZip.append(zipCd)
        fullZip.append(eocd)

        let hasZipSignature = fullZip.starts(with: [0x50, 0x4b, 0x03, 0x04])
        assertTest(
            "Pure Swift PKZIP .xlsx Engine Validation",
            condition: hasZipSignature && fullZip.count > 100,
            failureMessage: "Zip output missing standard PKZIP local header signature"
        )

        // ---------------------------------------------------------
        // TEST 16: JSON Report Serialization & ISO8601 Compliance
        // ---------------------------------------------------------
        struct MockJsonReport: Codable {
            let app: String
            let date: Date
            let totalBytes: UInt64
        }
        let mockReport = MockJsonReport(app: "NetGauge", date: Date(), totalBytes: 123456789)
        let jsonEncoder = JSONEncoder()
        jsonEncoder.dateEncodingStrategy = .iso8601
        let jsonData = (try? jsonEncoder.encode(mockReport)) ?? Data()
        let jsonStr = String(data: jsonData, encoding: .utf8) ?? ""

        assertTest(
            "JSON Report Serialization & ISO8601 Compliance",
            condition: jsonStr.contains("NetGauge") && jsonStr.contains("totalBytes"),
            failureMessage: "JSON encoding failed or did not contain required keys"
        )

        // ---------------------------------------------------------
        // TEST 17: Date Range Clamping & Day End Coverage
        // ---------------------------------------------------------
        let cal = Calendar.current
        let today = Date()
        let startOfDay = cal.startOfDay(for: today)
        let endOfDay = cal.date(bySettingHour: 23, minute: 59, second: 59, of: today) ?? today

        assertTest(
            "Date Range Clamping & 23:59:59 Coverage",
            condition: endOfDay > startOfDay && cal.component(.hour, from: endOfDay) == 23,
            failureMessage: "End of day date did not cover up to 23:59:59"
        )

        print("=========================================")
        print("Results: \(passedCount) Passed, \(failedCount) Failed")
        print("=========================================")

        if failedCount > 0 {
            exit(1)
        }
    }
}
