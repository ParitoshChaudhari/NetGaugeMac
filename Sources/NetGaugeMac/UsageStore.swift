import Foundation
import SQLite3

// MARK: - Models

struct UsageEvent: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let bytesReceived: UInt64
    let bytesSent: UInt64
    let intervalSeconds: TimeInterval

    var totalBytes: UInt64 { bytesReceived + bytesSent }
}

struct UsageBucket: Identifiable, Equatable, Sendable {
    var id: String { "\(start.timeIntervalSinceReferenceDate)-\(received)-\(sent)" }
    let start: Date
    let label: String
    let received: UInt64
    let sent: UInt64
    var total: UInt64 { received + sent }
}

// MARK: - SQLite Wrapper

final class SQLiteDatabase {
    private var db: OpaquePointer?

    init(path: String) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
        if sqlite3_open_v2(path, &db, flags, nil) != SQLITE_OK {
            let errMsg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            throw DatabaseError.openFailed(errMsg)
        }

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

        let db = try SQLiteDatabase(path: dbURL.path)
        self.database = db

        // Create retention tables
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS network_minutes (
                ts INTEGER PRIMARY KEY,
                bytes_rx INTEGER NOT NULL,
                bytes_tx INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS network_hours (
                ts INTEGER PRIMARY KEY,
                bytes_rx INTEGER NOT NULL,
                bytes_tx INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS network_days (
                ts INTEGER PRIMARY KEY,
                bytes_rx INTEGER NOT NULL,
                bytes_tx INTEGER NOT NULL
            );
        """)

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
                        INSERT INTO network_minutes (ts, bytes_rx, bytes_tx)
                        VALUES (?, ?, ?)
                        ON CONFLICT(ts) DO UPDATE SET
                            bytes_rx = bytes_rx + excluded.bytes_rx,
                            bytes_tx = bytes_tx + excluded.bytes_tx;
                        """
                        for (ts, data) in minutes {
                            let stmt = try db.prepare(sql: insertSql)
                            try stmt.bind(index: 1, value: ts)
                            try stmt.bind(index: 2, value: Int64(data.rx))
                            try stmt.bind(index: 3, value: Int64(data.tx))
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

    func insertMinute(timestamp: Date, bytesReceived: UInt64, bytesSent: UInt64) throws {
        let cal = Calendar.current
        let minuteStart = cal.dateInterval(of: .minute, for: timestamp)?.start ?? timestamp
        let ts = Int64(minuteStart.timeIntervalSince1970)

        let sql = """
        INSERT INTO network_minutes (ts, bytes_rx, bytes_tx)
        VALUES (?, ?, ?)
        ON CONFLICT(ts) DO UPDATE SET
            bytes_rx = bytes_rx + excluded.bytes_rx,
            bytes_tx = bytes_tx + excluded.bytes_tx;
        """

        let stmt = try database.prepare(sql: sql)
        try stmt.bind(index: 1, value: ts)
        try stmt.bind(index: 2, value: Int64(bytesReceived))
        try stmt.bind(index: 3, value: Int64(bytesSent))

        if stmt.step() != SQLITE_DONE {
            throw DatabaseError.executionFailed("Failed to insert minute row")
        }
    }

    // MARK: – Read

    func loadEvents(from startDate: Date, to endDate: Date) throws -> [UsageEvent] {
        let cal = Calendar.current

        // Expand query boundaries to align with the table resolutions to prevent data loss
        let minStart = cal.dateInterval(of: .minute, for: startDate)?.start ?? startDate
        let minEnd   = cal.dateInterval(of: .minute, for: endDate)?.end ?? endDate

        let hourStart = cal.dateInterval(of: .hour, for: startDate)?.start ?? startDate
        let hourEnd   = cal.dateInterval(of: .hour, for: endDate)?.end ?? endDate

        let dayStart = cal.startOfDay(for: startDate)
        let dayEnd   = cal.dateInterval(of: .day, for: endDate)?.end ?? endDate

        let startMinTs = Int64(minStart.timeIntervalSince1970)
        let endMinTs   = Int64(minEnd.timeIntervalSince1970)

        let startHourTs = Int64(hourStart.timeIntervalSince1970)
        let endHourTs   = Int64(hourEnd.timeIntervalSince1970)

        let startDayTs = Int64(dayStart.timeIntervalSince1970)
        let endDayTs   = Int64(dayEnd.timeIntervalSince1970)

        // Union minutes, hours, and days tables for the requested window
        let sql = """
        SELECT ts, bytes_rx, bytes_tx, 60 AS interval FROM network_minutes WHERE ts >= ? AND ts <= ?
        UNION ALL
        SELECT ts, bytes_rx, bytes_tx, 3600 AS interval FROM network_hours WHERE ts >= ? AND ts <= ?
        UNION ALL
        SELECT ts, bytes_rx, bytes_tx, 86400 AS interval FROM network_days WHERE ts >= ? AND ts <= ?
        ORDER BY ts ASC;
        """

        let stmt = try database.prepare(sql: sql)
        try stmt.bind(index: 1, value: startMinTs)
        try stmt.bind(index: 2, value: endMinTs)
        try stmt.bind(index: 3, value: startHourTs)
        try stmt.bind(index: 4, value: endHourTs)
        try stmt.bind(index: 5, value: startDayTs)
        try stmt.bind(index: 6, value: endDayTs)

        var events: [UsageEvent] = []
        while stmt.step() == SQLITE_ROW {
            let ts = stmt.columnInt64(index: 0)
            let rx = stmt.columnInt64(index: 1)
            let tx = stmt.columnInt64(index: 2)
            let interval = stmt.columnInt64(index: 3)

            events.append(UsageEvent(
                id: UUID(),
                timestamp: Date(timeIntervalSince1970: TimeInterval(ts)),
                bytesReceived: UInt64(rx),
                bytesSent: UInt64(tx),
                intervalSeconds: TimeInterval(interval)
            ))
        }
        return events
    }

    // MARK: – Rollup Retention Jobs

    func performRollups() throws {
        let now = Date()
        try rollupMinutesToHours(olderThan: now.addingTimeInterval(-7 * 24 * 60 * 60))
        try rollupHoursToDays(olderThan: now.addingTimeInterval(-90 * 24 * 60 * 60))
    }

    private func rollupMinutesToHours(olderThan limitDate: Date) throws {
        let limitTs = Int64(limitDate.timeIntervalSince1970)

        // 1. Fetch minute rows older than 7 days
        let fetchSql = "SELECT ts, bytes_rx, bytes_tx FROM network_minutes WHERE ts < ?;"
        let stmt = try database.prepare(sql: fetchSql)
        try stmt.bind(index: 1, value: limitTs)

        var rawRows: [(ts: Int64, rx: Int64, tx: Int64)] = []
        while stmt.step() == SQLITE_ROW {
            rawRows.append((
                ts: stmt.columnInt64(index: 0),
                rx: stmt.columnInt64(index: 1),
                tx: stmt.columnInt64(index: 2)
            ))
        }

        guard !rawRows.isEmpty else { return }

        // 2. Group by hour boundary in local time
        let cal = Calendar.current
        var hourlyGroups: [Int64: (rx: Int64, tx: Int64)] = [:]
        for row in rawRows {
            let date = Date(timeIntervalSince1970: TimeInterval(row.ts))
            let hourStart = cal.dateInterval(of: .hour, for: date)?.start ?? date
            let hourTs = Int64(hourStart.timeIntervalSince1970)

            let current = hourlyGroups[hourTs] ?? (0, 0)
            hourlyGroups[hourTs] = (current.0 + row.rx, current.1 + row.tx)
        }

        // 3. Insert and delete in a single transaction
        try database.execute(sql: "BEGIN TRANSACTION;")
        do {
            let insertSql = """
            INSERT INTO network_hours (ts, bytes_rx, bytes_tx)
            VALUES (?, ?, ?)
            ON CONFLICT(ts) DO UPDATE SET
                bytes_rx = bytes_rx + excluded.bytes_rx,
                bytes_tx = bytes_tx + excluded.bytes_tx;
            """
            for (hourTs, data) in hourlyGroups {
                let insertStmt = try database.prepare(sql: insertSql)
                try insertStmt.bind(index: 1, value: hourTs)
                try insertStmt.bind(index: 2, value: data.rx)
                try insertStmt.bind(index: 3, value: data.tx)
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

        // 1. Fetch hour rows older than 90 days
        let fetchSql = "SELECT ts, bytes_rx, bytes_tx FROM network_hours WHERE ts < ?;"
        let stmt = try database.prepare(sql: fetchSql)
        try stmt.bind(index: 1, value: limitTs)

        var rawRows: [(ts: Int64, rx: Int64, tx: Int64)] = []
        while stmt.step() == SQLITE_ROW {
            rawRows.append((
                ts: stmt.columnInt64(index: 0),
                rx: stmt.columnInt64(index: 1),
                tx: stmt.columnInt64(index: 2)
            ))
        }

        guard !rawRows.isEmpty else { return }

        // 2. Group by day boundary in local time
        let cal = Calendar.current
        var dailyGroups: [Int64: (rx: Int64, tx: Int64)] = [:]
        for row in rawRows {
            let date = Date(timeIntervalSince1970: TimeInterval(row.ts))
            let dayStart = cal.startOfDay(for: date)
            let dayTs = Int64(dayStart.timeIntervalSince1970)

            let current = dailyGroups[dayTs] ?? (0, 0)
            dailyGroups[dayTs] = (current.0 + row.rx, current.1 + row.tx)
        }

        // 3. Insert and delete in a single transaction
        try database.execute(sql: "BEGIN TRANSACTION;")
        do {
            let insertSql = """
            INSERT INTO network_days (ts, bytes_rx, bytes_tx)
            VALUES (?, ?, ?)
            ON CONFLICT(ts) DO UPDATE SET
                bytes_rx = bytes_rx + excluded.bytes_rx,
                bytes_tx = bytes_tx + excluded.bytes_tx;
            """
            for (dayTs, data) in dailyGroups {
                let insertStmt = try database.prepare(sql: insertSql)
                try insertStmt.bind(index: 1, value: dayTs)
                try insertStmt.bind(index: 2, value: data.rx)
                try insertStmt.bind(index: 3, value: data.tx)
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
