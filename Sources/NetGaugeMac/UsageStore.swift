import Foundation
import SQLite3

// MARK: - Models

struct UsageEvent: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let bytesReceived: UInt64
    let bytesSent: UInt64
    let intervalSeconds: TimeInterval
    let networkName: String?

    var totalBytes: UInt64 { bytesReceived + bytesSent }

    enum CodingKeys: String, CodingKey {
        case id, timestamp, bytesReceived, bytesSent, intervalSeconds, networkName
    }

    init(id: UUID = UUID(), timestamp: Date, bytesReceived: UInt64, bytesSent: UInt64, intervalSeconds: TimeInterval, networkName: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.bytesReceived = bytesReceived
        self.bytesSent = bytesSent
        self.intervalSeconds = intervalSeconds
        self.networkName = networkName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        self.bytesReceived = try container.decode(UInt64.self, forKey: .bytesReceived)
        self.bytesSent = try container.decode(UInt64.self, forKey: .bytesSent)
        self.intervalSeconds = try container.decode(TimeInterval.self, forKey: .intervalSeconds)
        self.networkName = try container.decodeIfPresent(String.self, forKey: .networkName)
    }
}

struct UsageBucket: Identifiable, Equatable, Sendable {
    // NOTE: id is intentionally based only on stable, identity-defining properties
    // (start time + label). Including received/sent would change the id on every
    // data refresh, causing SwiftUI's ForEach to treat each bucket as brand new
    // and re-animate the entire chart — producing visible flicker.
    var id: String { "\(start.timeIntervalSince1970)-\(label)" }
    let start: Date
    let label: String
    let received: UInt64
    let sent: UInt64
    var total: UInt64 { received + sent }
}

struct NetworkUsageStats: Identifiable, Equatable, Sendable {
    var id: String { networkName }
    let networkName: String
    let todayRx: UInt64
    let todayTx: UInt64
    let monthRx: UInt64
    let monthTx: UInt64
    let totalRx: UInt64
    let totalTx: UInt64
    let lastUpdated: Date

    var todayTotal: UInt64 { todayRx + todayTx }
    var monthTotal: UInt64 { monthRx + monthTx }
    var totalBytes: UInt64 { totalRx + totalTx }
}

// MARK: - SQLite Wrapper

final class SQLiteDatabase {
    private var db: OpaquePointer?

    init(path: String) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(path, &db, flags, nil) != SQLITE_OK {
            let errMsg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            throw DatabaseError.openFailed(errMsg)
        }

        sqlite3_busy_timeout(db, 5000)

        // Enable Write-Ahead Logging (WAL) mode for crash safety
        try execute(sql: "PRAGMA journal_mode=WAL;")
    }

    deinit {
        if db != nil {
            sqlite3_close_v2(db)
        }
    }

    func execute(sql: String) throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            let str = errMsg.map { String(cString: $0) } ?? "Unknown error"
            if let errMsg { sqlite3_free(errMsg) }
            throw DatabaseError.executionFailed(str)
        }
    }

    func prepare(sql: String) throws -> SQLiteStatement {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            let errMsg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            throw DatabaseError.prepareFailed(errMsg)
        }
        return SQLiteStatement(stmt: stmt!)
    }
}

final class SQLiteStatement {
    let stmt: OpaquePointer

    init(stmt: OpaquePointer) {
        self.stmt = stmt
    }

    deinit {
        sqlite3_finalize(stmt)
    }

    func bind(index: Int32, value: Int64) throws {
        if sqlite3_bind_int64(stmt, index, value) != SQLITE_OK {
            throw DatabaseError.bindFailed
        }
    }

    func step() -> Int32 {
        sqlite3_step(stmt)
    }

    func columnInt64(index: Int32) -> Int64 {
        sqlite3_column_int64(stmt, index)
    }

    func bind(index: Int32, value: String) throws {
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        if sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT) != SQLITE_OK {
            throw DatabaseError.bindFailed
        }
    }

    func columnText(index: Int32) -> String? {
        if let ptr = sqlite3_column_text(stmt, index) {
            return String(cString: ptr)
        }
        return nil
    }

    func reset() {
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
    }
}

enum DatabaseError: Error, LocalizedError {
    case openFailed(String)
    case executionFailed(String)
    case prepareFailed(String)
    case bindFailed

    var errorDescription: String? {
        switch self {
        case .openFailed(let msg): return "Failed to open SQLite database: \(msg)"
        case .executionFailed(let msg): return "SQL execution failed: \(msg)"
        case .prepareFailed(let msg): return "SQL prepare failed: \(msg)"
        case .bindFailed: return "Failed to bind SQLite parameters"
        }
    }
}

// MARK: - UsageStore

/// Actor-isolated SQLite persistence.
/// All operations run sequentially on the actor's executor (single writer thread guarantee).
actor UsageStore {

    private let database: SQLiteDatabase
    private let fileURL: URL

    init() throws {
        guard let supportDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else {
            throw StoreError.applicationSupportDirectoryUnavailable
        }

        let appDir = supportDir.appending(path: "NetGaugeMac", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        let dbURL = appDir.appending(path: "netgauge.db")
        self.fileURL = dbURL

        // If target container DB does not exist, check for legacy unsandboxed DB and migrate
        if !FileManager.default.fileExists(atPath: dbURL.path) {
            let homeDir = NSHomeDirectory()
            let legacyAppDir = URL(fileURLWithPath: homeDir)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Library/Application Support/NetGaugeMac")
            let legacyDbURL = legacyAppDir.appendingPathComponent("netgauge.db")
            
            if FileManager.default.fileExists(atPath: legacyDbURL.path) {
                try? FileManager.default.copyItem(at: legacyDbURL, to: dbURL)
                let legacyWal = legacyAppDir.appendingPathComponent("netgauge.db-wal")
                let targetWal = appDir.appending(path: "netgauge.db-wal")
                if FileManager.default.fileExists(atPath: legacyWal.path) {
                    try? FileManager.default.copyItem(at: legacyWal, to: targetWal)
                }
                let legacyShm = legacyAppDir.appendingPathComponent("netgauge.db-shm")
                let targetShm = appDir.appending(path: "netgauge.db-shm")
                if FileManager.default.fileExists(atPath: legacyShm.path) {
                    try? FileManager.default.copyItem(at: legacyShm, to: targetShm)
                }
            }
        }

        let db = try SQLiteDatabase(path: dbURL.path)
        self.database = db

        // Check schema migration
        var needsMigration = false
        do {
            let stmt = try db.prepare(sql: "PRAGMA table_info(network_minutes);")
            var hasNetworkName = false
            while stmt.step() == SQLITE_ROW {
                if let colName = stmt.columnText(index: 1), colName == "network_name" {
                    hasNetworkName = true
                    break
                }
            }
            if !hasNetworkName {
                // If table is empty/doesn't exist, we don't need migration, but we check if we can select from it first
                let checkStmt = try db.prepare(sql: "SELECT 1 FROM sqlite_master WHERE type='table' AND name='network_minutes';")
                if checkStmt.step() == SQLITE_ROW {
                    needsMigration = true
                }
            }
        } catch {
            needsMigration = false
        }

        if needsMigration {
            try? db.execute(sql: "ALTER TABLE network_minutes RENAME TO old_network_minutes;")
            try? db.execute(sql: "ALTER TABLE network_hours RENAME TO old_network_hours;")
            try? db.execute(sql: "ALTER TABLE network_days RENAME TO old_network_days;")
        }

        // Create retention tables
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS network_minutes (
                ts INTEGER,
                network_name TEXT NOT NULL,
                bytes_rx INTEGER NOT NULL,
                bytes_tx INTEGER NOT NULL,
                PRIMARY KEY (ts, network_name)
            );
            CREATE TABLE IF NOT EXISTS network_hours (
                ts INTEGER,
                network_name TEXT NOT NULL,
                bytes_rx INTEGER NOT NULL,
                bytes_tx INTEGER NOT NULL,
                PRIMARY KEY (ts, network_name)
            );
            CREATE TABLE IF NOT EXISTS network_days (
                ts INTEGER,
                network_name TEXT NOT NULL,
                bytes_rx INTEGER NOT NULL,
                bytes_tx INTEGER NOT NULL,
                PRIMARY KEY (ts, network_name)
            );
            CREATE TABLE IF NOT EXISTS network_usage (
                network_name TEXT PRIMARY KEY,
                bytes_rx INTEGER NOT NULL DEFAULT 0,
                bytes_tx INTEGER NOT NULL DEFAULT 0,
                last_updated INTEGER NOT NULL
            );
        """)

        if needsMigration {
            try? db.execute(sql: """
                BEGIN TRANSACTION;
                INSERT INTO network_minutes (ts, network_name, bytes_rx, bytes_tx)
                SELECT ts, 'Primary', bytes_rx, bytes_tx FROM old_network_minutes;
                
                INSERT INTO network_hours (ts, network_name, bytes_rx, bytes_tx)
                SELECT ts, 'Primary', bytes_rx, bytes_tx FROM old_network_hours;
                
                INSERT INTO network_days (ts, network_name, bytes_rx, bytes_tx)
                SELECT ts, 'Primary', bytes_rx, bytes_tx FROM old_network_days;
                COMMIT;
            """)
            
            try? db.execute(sql: "DROP TABLE IF EXISTS old_network_minutes;")
            try? db.execute(sql: "DROP TABLE IF EXISTS old_network_hours;")
            try? db.execute(sql: "DROP TABLE IF EXISTS old_network_days;")
        }

        // Auto-migrate from JSONL if exists
        let jsonlURL = appDir.appending(path: "usage-events.jsonl")
        if FileManager.default.fileExists(atPath: jsonlURL.path) {
            do {
                let data = try Data(contentsOf: jsonlURL, options: .mappedIfSafe)
                if let text = String(data: data, encoding: .utf8) {
                    let dec = JSONDecoder()
                    dec.dateDecodingStrategy = .iso8601
                    let jsonlEvents = text
                        .split(separator: "\n", omittingEmptySubsequences: true)
                        .compactMap { line -> UsageEvent? in
                            try? dec.decode(UsageEvent.self, from: Data(line.utf8))
                        }

                    if !jsonlEvents.isEmpty {
                        let cal = Calendar.current
                        var minutes: [Int64: (rx: UInt64, tx: UInt64)] = [:]
                        for event in jsonlEvents {
                            let minStart = cal.dateInterval(of: .minute, for: event.timestamp)?.start ?? event.timestamp
                            let ts = Int64(minStart.timeIntervalSince1970)
                            let current = minutes[ts] ?? (0, 0)
                            minutes[ts] = (current.0 + event.bytesReceived, current.1 + event.bytesSent)
                        }

                        try db.execute(sql: "BEGIN TRANSACTION;")
                        let insertSql = """
                        INSERT INTO network_minutes (ts, network_name, bytes_rx, bytes_tx)
                        VALUES (?, ?, ?, ?)
                        ON CONFLICT(ts, network_name) DO UPDATE SET
                            bytes_rx = bytes_rx + excluded.bytes_rx,
                            bytes_tx = bytes_tx + excluded.bytes_tx;
                        """
                        for (ts, data) in minutes {
                            let stmt = try db.prepare(sql: insertSql)
                            try stmt.bind(index: 1, value: ts)
                            try stmt.bind(index: 2, value: "Primary")
                            try stmt.bind(index: 3, value: Int64(clamping: data.rx))
                            try stmt.bind(index: 4, value: Int64(clamping: data.tx))
                            _ = stmt.step()
                        }
                        try db.execute(sql: "COMMIT;")
                    }
                }
                try FileManager.default.removeItem(at: jsonlURL)
            } catch {
                print("Failed to migrate JSONL data: \(error)")
            }
        }
    }

    // MARK: – Write

    func updateNetworkUsage(networkName: String, bytesReceived: UInt64, bytesSent: UInt64, timestamp: Date) throws {
        let sql = """
        INSERT INTO network_usage (network_name, bytes_rx, bytes_tx, last_updated)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(network_name) DO UPDATE SET
            bytes_rx = bytes_rx + excluded.bytes_rx,
            bytes_tx = bytes_tx + excluded.bytes_tx,
            last_updated = excluded.last_updated;
        """

        let stmt = try database.prepare(sql: sql)
        try stmt.bind(index: 1, value: networkName)
        try stmt.bind(index: 2, value: Int64(clamping: bytesReceived))
        try stmt.bind(index: 3, value: Int64(clamping: bytesSent))
        try stmt.bind(index: 4, value: Int64(timestamp.timeIntervalSince1970))

        if stmt.step() != SQLITE_DONE {
            throw DatabaseError.executionFailed("Failed to update network usage")
        }
    }

    func insertMinute(timestamp: Date, networkName: String, bytesReceived: UInt64, bytesSent: UInt64) throws {
        let cal = Calendar.current
        let minuteStart = cal.dateInterval(of: .minute, for: timestamp)?.start ?? timestamp
        let ts = Int64(minuteStart.timeIntervalSince1970)

        let sql = """
        INSERT INTO network_minutes (ts, network_name, bytes_rx, bytes_tx)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(ts, network_name) DO UPDATE SET
            bytes_rx = bytes_rx + excluded.bytes_rx,
            bytes_tx = bytes_tx + excluded.bytes_tx;
        """

        let stmt = try database.prepare(sql: sql)
        try stmt.bind(index: 1, value: ts)
        try stmt.bind(index: 2, value: networkName)
        try stmt.bind(index: 3, value: Int64(clamping: bytesReceived))
        try stmt.bind(index: 4, value: Int64(clamping: bytesSent))

        if stmt.step() != SQLITE_DONE {
            throw DatabaseError.executionFailed("Failed to insert minute row")
        }
    }

    // MARK: – Read

    func loadTotals(from startDate: Date, to endDate: Date, networkName: String?) throws -> (rx: UInt64, tx: UInt64) {
        let startTs = Int64(startDate.timeIntervalSince1970)
        let endTs   = Int64(endDate.timeIntervalSince1970)

        let sql: String
        if networkName != nil {
            sql = """
            SELECT SUM(bytes_rx), SUM(bytes_tx) FROM (
                SELECT bytes_rx, bytes_tx FROM network_minutes WHERE ts >= ? AND ts < ? AND network_name = ?
                UNION ALL
                SELECT bytes_rx, bytes_tx FROM network_hours WHERE ts >= ? AND ts < ? AND network_name = ?
                UNION ALL
                SELECT bytes_rx, bytes_tx FROM network_days WHERE ts >= ? AND ts < ? AND network_name = ?
            );
            """
        } else {
            sql = """
            SELECT SUM(bytes_rx), SUM(bytes_tx) FROM (
                SELECT bytes_rx, bytes_tx FROM network_minutes WHERE ts >= ? AND ts < ?
                UNION ALL
                SELECT bytes_rx, bytes_tx FROM network_hours WHERE ts >= ? AND ts < ?
                UNION ALL
                SELECT bytes_rx, bytes_tx FROM network_days WHERE ts >= ? AND ts < ?
            );
            """
        }

        let stmt = try database.prepare(sql: sql)
        if let networkName {
            try stmt.bind(index: 1, value: startTs)
            try stmt.bind(index: 2, value: endTs)
            try stmt.bind(index: 3, value: networkName)

            try stmt.bind(index: 4, value: startTs)
            try stmt.bind(index: 5, value: endTs)
            try stmt.bind(index: 6, value: networkName)

            try stmt.bind(index: 7, value: startTs)
            try stmt.bind(index: 8, value: endTs)
            try stmt.bind(index: 9, value: networkName)
        } else {
            try stmt.bind(index: 1, value: startTs)
            try stmt.bind(index: 2, value: endTs)
            try stmt.bind(index: 3, value: startTs)
            try stmt.bind(index: 4, value: endTs)
            try stmt.bind(index: 5, value: startTs)
            try stmt.bind(index: 6, value: endTs)
        }

        if stmt.step() == SQLITE_ROW {
            // Clamp to 0 before casting to UInt64: a corrupt or negative Int64 value
            // would wrap to a huge positive number and cause absurd byte counts in the UI.
            let rx = max(0, stmt.columnInt64(index: 0))
            let tx = max(0, stmt.columnInt64(index: 1))
            return (UInt64(rx), UInt64(tx))
        }
        return (0, 0)
    }

    func loadNetworkUsages(todayStart: Date, monthStart: Date) throws -> [NetworkUsageStats] {
        let sqlUsage = "SELECT network_name, bytes_rx, bytes_tx, last_updated FROM network_usage;"
        let stmtUsage = try database.prepare(sql: sqlUsage)
        var usages: [String: (totalRx: UInt64, totalTx: UInt64, lastUpdated: Date)] = [:]
        while stmtUsage.step() == SQLITE_ROW {
            if let name = stmtUsage.columnText(index: 0) {
                let rx = stmtUsage.columnInt64(index: 1)
                let tx = stmtUsage.columnInt64(index: 2)
                let ts = stmtUsage.columnInt64(index: 3)
                usages[name] = (UInt64(rx), UInt64(tx), Date(timeIntervalSince1970: TimeInterval(ts)))
            }
        }

        let todayTs = Int64(todayStart.timeIntervalSince1970)
        let sqlToday = """
        SELECT network_name, SUM(bytes_rx), SUM(bytes_tx) FROM (
            SELECT network_name, bytes_rx, bytes_tx FROM network_minutes WHERE ts >= ?
            UNION ALL
            SELECT network_name, bytes_rx, bytes_tx FROM network_hours WHERE ts >= ?
            UNION ALL
            SELECT network_name, bytes_rx, bytes_tx FROM network_days WHERE ts >= ?
        ) GROUP BY network_name;
        """
        let stmtToday = try database.prepare(sql: sqlToday)
        try stmtToday.bind(index: 1, value: todayTs)
        try stmtToday.bind(index: 2, value: todayTs)
        try stmtToday.bind(index: 3, value: todayTs)
        var todayStats: [String: (rx: UInt64, tx: UInt64)] = [:]
        while stmtToday.step() == SQLITE_ROW {
            if let name = stmtToday.columnText(index: 0) {
                let rx = max(0, stmtToday.columnInt64(index: 1))
                let tx = max(0, stmtToday.columnInt64(index: 2))
                todayStats[name] = (UInt64(rx), UInt64(tx))
            }
        }

        let monthTs = Int64(monthStart.timeIntervalSince1970)
        let sqlMonth = """
        SELECT network_name, SUM(bytes_rx), SUM(bytes_tx) FROM (
            SELECT network_name, bytes_rx, bytes_tx FROM network_minutes WHERE ts >= ?
            UNION ALL
            SELECT network_name, bytes_rx, bytes_tx FROM network_hours WHERE ts >= ?
            UNION ALL
            SELECT network_name, bytes_rx, bytes_tx FROM network_days WHERE ts >= ?
        ) GROUP BY network_name;
        """
        let stmtMonth = try database.prepare(sql: sqlMonth)
        try stmtMonth.bind(index: 1, value: monthTs)
        try stmtMonth.bind(index: 2, value: monthTs)
        try stmtMonth.bind(index: 3, value: monthTs)
        var monthStats: [String: (rx: UInt64, tx: UInt64)] = [:]
        while stmtMonth.step() == SQLITE_ROW {
            if let name = stmtMonth.columnText(index: 0) {
                let rx = max(0, stmtMonth.columnInt64(index: 1))
                let tx = max(0, stmtMonth.columnInt64(index: 2))
                monthStats[name] = (UInt64(rx), UInt64(tx))
            }
        }

        var result: [NetworkUsageStats] = []
        for name in usages.keys {
            let total = usages[name]!
            let today = todayStats[name] ?? (0, 0)
            let month = monthStats[name] ?? (0, 0)
            result.append(NetworkUsageStats(
                networkName: name,
                todayRx: today.rx,
                todayTx: today.tx,
                monthRx: month.rx,
                monthTx: month.tx,
                totalRx: total.totalRx,
                totalTx: total.totalTx,
                lastUpdated: total.lastUpdated
            ))
        }

        return result.sorted {
            if $0.todayTotal != $1.todayTotal {
                return $0.todayTotal > $1.todayTotal
            }
            if $0.monthTotal != $1.monthTotal {
                return $0.monthTotal > $1.monthTotal
            }
            return $0.totalBytes > $1.totalBytes
        }
    }

    func loadEvents(from startDate: Date, to endDate: Date, networkName: String?) throws -> [UsageEvent] {
        let startTs = Int64(startDate.timeIntervalSince1970)
        let endTs   = Int64(endDate.timeIntervalSince1970)

        let sql: String
        if networkName != nil {
            sql = """
            SELECT ts, bytes_rx, bytes_tx, interval FROM (
                SELECT ts, SUM(bytes_rx) AS bytes_rx, SUM(bytes_tx) AS bytes_tx, 60 AS interval FROM network_minutes WHERE ts >= ? AND ts < ? AND network_name = ? GROUP BY ts
                UNION ALL
                SELECT ts, SUM(bytes_rx) AS bytes_rx, SUM(bytes_tx) AS bytes_tx, 3600 AS interval FROM network_hours WHERE ts >= ? AND ts < ? AND network_name = ? GROUP BY ts
                UNION ALL
                SELECT ts, SUM(bytes_rx) AS bytes_rx, SUM(bytes_tx) AS bytes_tx, 86400 AS interval FROM network_days WHERE ts >= ? AND ts < ? AND network_name = ? GROUP BY ts
            ) ORDER BY ts ASC;
            """
        } else {
            sql = """
            SELECT ts, bytes_rx, bytes_tx, interval FROM (
                SELECT ts, SUM(bytes_rx) AS bytes_rx, SUM(bytes_tx) AS bytes_tx, 60 AS interval FROM network_minutes WHERE ts >= ? AND ts < ? GROUP BY ts
                UNION ALL
                SELECT ts, SUM(bytes_rx) AS bytes_rx, SUM(bytes_tx) AS bytes_tx, 3600 AS interval FROM network_hours WHERE ts >= ? AND ts < ? GROUP BY ts
                UNION ALL
                SELECT ts, SUM(bytes_rx) AS bytes_rx, SUM(bytes_tx) AS bytes_tx, 86400 AS interval FROM network_days WHERE ts >= ? AND ts < ? GROUP BY ts
            ) ORDER BY ts ASC;
            """
        }

        let stmt = try database.prepare(sql: sql)
        if let networkName {
            try stmt.bind(index: 1, value: startTs)
            try stmt.bind(index: 2, value: endTs)
            try stmt.bind(index: 3, value: networkName)

            try stmt.bind(index: 4, value: startTs)
            try stmt.bind(index: 5, value: endTs)
            try stmt.bind(index: 6, value: networkName)

            try stmt.bind(index: 7, value: startTs)
            try stmt.bind(index: 8, value: endTs)
            try stmt.bind(index: 9, value: networkName)
        } else {
            try stmt.bind(index: 1, value: startTs)
            try stmt.bind(index: 2, value: endTs)
            try stmt.bind(index: 3, value: startTs)
            try stmt.bind(index: 4, value: endTs)
            try stmt.bind(index: 5, value: startTs)
            try stmt.bind(index: 6, value: endTs)
        }

        var events: [UsageEvent] = []
        while stmt.step() == SQLITE_ROW {
            let ts = stmt.columnInt64(index: 0)
            // Clamp before UInt64 cast to prevent overflow from corrupt/negative DB values
            let rx = max(0, stmt.columnInt64(index: 1))
            let tx = max(0, stmt.columnInt64(index: 2))
            let interval = stmt.columnInt64(index: 3)

            events.append(UsageEvent(
                id: UUID(),
                timestamp: Date(timeIntervalSince1970: TimeInterval(ts)),
                bytesReceived: UInt64(rx),
                bytesSent: UInt64(tx),
                intervalSeconds: TimeInterval(interval),
                networkName: networkName
            ))
        }
        return events
    }

    /// Truncates all SQLite tables and vacuums the database to reset all stored metrics.
    func clearAllData() throws {
        // IMPORTANT: sqlite3_exec with a multi-statement string only runs the FIRST
        // statement and silently ignores the rest. Each statement must be executed
        // individually to ensure all tables are actually cleared.
        try database.execute(sql: "DELETE FROM network_minutes;")
        try database.execute(sql: "DELETE FROM network_hours;")
        try database.execute(sql: "DELETE FROM network_days;")
        try database.execute(sql: "DELETE FROM network_usage;")
        // VACUUM must run outside any transaction (it commits its own transaction internally)
        try database.execute(sql: "VACUUM;")
    }

    // MARK: – Rollup Retention Jobs

    func performRollups() throws {
        let now = Date()
        try rollupMinutesToHours(olderThan: now.addingTimeInterval(-7 * 24 * 60 * 60))
        try rollupHoursToDays(olderThan: now.addingTimeInterval(-90 * 24 * 60 * 60))
    }

    private func rollupMinutesToHours(olderThan limitDate: Date) throws {
        let limitTs = Int64(limitDate.timeIntervalSince1970)

        let fetchSql = "SELECT ts, network_name, bytes_rx, bytes_tx FROM network_minutes WHERE ts < ?;"
        let stmt = try database.prepare(sql: fetchSql)
        try stmt.bind(index: 1, value: limitTs)

        struct HourlyKey: Hashable {
            let ts: Int64
            let networkName: String
        }

        var rawRows: [HourlyKey: (rx: Int64, tx: Int64)] = [:]
        let cal = Calendar.current
        while stmt.step() == SQLITE_ROW {
            let ts = stmt.columnInt64(index: 0)
            if let networkName = stmt.columnText(index: 1) {
                let rx = stmt.columnInt64(index: 2)
                let tx = stmt.columnInt64(index: 3)

                let date = Date(timeIntervalSince1970: TimeInterval(ts))
                let hourStart = cal.dateInterval(of: .hour, for: date)?.start ?? date
                let hourTs = Int64(hourStart.timeIntervalSince1970)

                let key = HourlyKey(ts: hourTs, networkName: networkName)
                let current = rawRows[key] ?? (0, 0)
                rawRows[key] = (current.0 + rx, current.1 + tx)
            }
        }

        guard !rawRows.isEmpty else { return }

        try database.execute(sql: "BEGIN TRANSACTION;")
        do {
            let insertSql = """
            INSERT INTO network_hours (ts, network_name, bytes_rx, bytes_tx)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(ts, network_name) DO UPDATE SET
                bytes_rx = bytes_rx + excluded.bytes_rx,
                bytes_tx = bytes_tx + excluded.bytes_tx;
            """
            let insertStmt = try database.prepare(sql: insertSql)
            for (key, data) in rawRows {
                insertStmt.reset()
                try insertStmt.bind(index: 1, value: key.ts)
                try insertStmt.bind(index: 2, value: key.networkName)
                try insertStmt.bind(index: 3, value: data.rx)
                try insertStmt.bind(index: 4, value: data.tx)
                if insertStmt.step() != SQLITE_DONE {
                    throw DatabaseError.executionFailed("Failed to insert rolled up hour")
                }
            }

            let deleteSql = "DELETE FROM network_minutes WHERE ts < ?;"
            let deleteStmt = try database.prepare(sql: deleteSql)
            try deleteStmt.bind(index: 1, value: limitTs)
            if deleteStmt.step() != SQLITE_DONE {
                throw DatabaseError.executionFailed("Failed to delete rolled up minutes")
            }

            try database.execute(sql: "COMMIT;")
        } catch {
            try? database.execute(sql: "ROLLBACK;")
            throw error
        }
    }

    private func rollupHoursToDays(olderThan limitDate: Date) throws {
        let limitTs = Int64(limitDate.timeIntervalSince1970)

        let fetchSql = "SELECT ts, network_name, bytes_rx, bytes_tx FROM network_hours WHERE ts < ?;"
        let stmt = try database.prepare(sql: fetchSql)
        try stmt.bind(index: 1, value: limitTs)

        struct DailyKey: Hashable {
            let ts: Int64
            let networkName: String
        }

        var rawRows: [DailyKey: (rx: Int64, tx: Int64)] = [:]
        let cal = Calendar.current
        while stmt.step() == SQLITE_ROW {
            let ts = stmt.columnInt64(index: 0)
            if let networkName = stmt.columnText(index: 1) {
                let rx = stmt.columnInt64(index: 2)
                let tx = stmt.columnInt64(index: 3)

                let date = Date(timeIntervalSince1970: TimeInterval(ts))
                let dayStart = cal.startOfDay(for: date)
                let dayTs = Int64(dayStart.timeIntervalSince1970)

                let key = DailyKey(ts: dayTs, networkName: networkName)
                let current = rawRows[key] ?? (0, 0)
                rawRows[key] = (current.0 + rx, current.1 + tx)
            }
        }

        guard !rawRows.isEmpty else { return }

        try database.execute(sql: "BEGIN TRANSACTION;")
        do {
            let insertSql = """
            INSERT INTO network_days (ts, network_name, bytes_rx, bytes_tx)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(ts, network_name) DO UPDATE SET
                bytes_rx = bytes_rx + excluded.bytes_rx,
                bytes_tx = bytes_tx + excluded.bytes_tx;
            """
            let insertStmt = try database.prepare(sql: insertSql)
            for (key, data) in rawRows {
                insertStmt.reset()
                try insertStmt.bind(index: 1, value: key.ts)
                try insertStmt.bind(index: 2, value: key.networkName)
                try insertStmt.bind(index: 3, value: data.rx)
                try insertStmt.bind(index: 4, value: data.tx)
                if insertStmt.step() != SQLITE_DONE {
                    throw DatabaseError.executionFailed("Failed to insert rolled up day")
                }
            }

            let deleteSql = "DELETE FROM network_hours WHERE ts < ?;"
            let deleteStmt = try database.prepare(sql: deleteSql)
            try deleteStmt.bind(index: 1, value: limitTs)
            if deleteStmt.step() != SQLITE_DONE {
                throw DatabaseError.executionFailed("Failed to delete rolled up hours")
            }

            try database.execute(sql: "COMMIT;")
        } catch {
            try? database.execute(sql: "ROLLBACK;")
            throw error
        }
    }

    // MARK: – Errors

    enum StoreError: LocalizedError {
        case applicationSupportDirectoryUnavailable

        var errorDescription: String? {
            switch self {
            case .applicationSupportDirectoryUnavailable:
                return "Cannot locate ~/Library/Application Support. NetGauge cannot persist data."
            }
        }
    }
}

// MARK: - Array<UsageEvent> helpers

extension Array where Element == UsageEvent {

    func filtered(from startDate: Date, to endDate: Date) -> [UsageEvent] {
        filter { $0.timestamp >= startDate && $0.timestamp <= endDate }
    }

    func bucketed(
        by component: Calendar.Component,
        calendar: Calendar = .current
    ) -> [UsageBucket] {
        let grouped = Dictionary(grouping: self) { event in
            calendar.dateInterval(of: component, for: event.timestamp)?.start ?? event.timestamp
        }

        return grouped.map { start, events in
            let received = events.reduce(UInt64(0)) { $0 + $1.bytesReceived }
            let sent     = events.reduce(UInt64(0)) { $0 + $1.bytesSent }
            return UsageBucket(
                start:    start,
                label:    start.bucketLabel(for: component, calendar: calendar),
                received: received,
                sent:     sent
            )
        }
        .sorted { $0.start < $1.start }
    }

    func bucketed(
        by component: Calendar.Component,
        in interval: DateInterval,
        calendar: Calendar = .current
    ) -> [UsageBucket] {
        let grouped = Dictionary(grouping: self) { event in
            calendar.dateInterval(of: component, for: event.timestamp)?.start ?? event.timestamp
        }

        var buckets: [UsageBucket] = []
        var current = calendar.dateInterval(of: component, for: interval.start)?.start ?? interval.start
        let end = interval.end

        while current <= end {
            let next = calendar.date(byAdding: component, value: 1, to: current) ?? current

            let events = grouped[current] ?? []
            let rx = events.reduce(UInt64(0)) { $0 + $1.bytesReceived }
            let tx = events.reduce(UInt64(0)) { $0 + $1.bytesSent }

            buckets.append(UsageBucket(
                start: current,
                label: current.bucketLabel(for: component, calendar: calendar),
                received: rx,
                sent:     tx
            ))

            if next <= current { break }
            current = next
        }

        return buckets
    }
}

// MARK: - Date bucket label

extension Date {
    private static let hourFormatter:  DateFormatter = makeFormatter(dateFormat: "ha")
    private static let dayFormatter:   DateFormatter = makeFormatter(dateFormat: "d MMM")
    private static let monthFormatter: DateFormatter = makeFormatter(dateFormat: "MMM yyyy")
    private static let defaultFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }()

    private static func makeFormatter(dateFormat: String) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = dateFormat
        return f
    }

    func bucketLabel(for component: Calendar.Component, calendar: Calendar = .current) -> String {
        switch component {
        case .hour:  return Date.hourFormatter.string(from: self)
        case .day:   return Date.dayFormatter.string(from: self)
        case .month: return Date.monthFormatter.string(from: self)
        default:     return Date.defaultFormatter.string(from: self)
        }
    }
}
