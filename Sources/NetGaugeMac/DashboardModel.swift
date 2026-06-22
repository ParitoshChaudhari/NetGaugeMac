import Foundation
import SwiftUI
import ServiceManagement

// MARK: - Enums

enum ChartMode: String, CaseIterable, Identifiable, Sendable {
    case both     = "Both"
    case download = "Download"
    case upload   = "Upload"
    var id: String { rawValue }
}

enum DashboardRange: String, CaseIterable, Identifiable, Sendable {
    case today      = "Today"
    case yesterday  = "Yesterday"
    case thisMonth  = "This Month"
    case last30Days = "Last 30 Days"
    case custom     = "Custom"
    var id: String { rawValue }
}

// MARK: - DashboardModel

@MainActor
final class DashboardModel: ObservableObject {

    // MARK: Published state
    @Published private(set) var events: [UsageEvent] = []
    @Published private(set) var currentDownloadBytesPerSecond: Double = 0
    @Published private(set) var currentUploadBytesPerSecond: Double = 0
    @Published private(set) var interfaceRates: [InterfaceRate] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var storeError: String?

    @Published var selectedRange: DashboardRange = .today {
        didSet {
            Task { await refreshEvents() }
        }
    }
    @Published var customStartDate: Date = Calendar.current.date(
        byAdding: .day, value: -7, to: Date()) ?? Date() {
        didSet {
            Task { await refreshEvents() }
        }
    }
    @Published var customEndDate: Date = Date() {
        didSet {
            Task { await refreshEvents() }
        }
    }
    @Published var chartMode: ChartMode = .both
    @Published var isLaunchAtLoginEnabled: Bool = false {
        didSet {
            toggleLaunchAtLogin(enabled: isLaunchAtLoginEnabled)
        }
    }

    // MARK: Private
    private let sampler = NetworkSampler()
    private var store: UsageStore?
    private var lastSnapshot: NetworkSnapshot?
    private var captureTask: Task<Void, Never>?
    private var inMemorySamples: [UsageEvent] = []
    private var lastRollupTime: Date = Date()

    // MARK: – Lifecycle

    func start() async {
        guard captureTask == nil else { return }

        do {
            let newStore = try UsageStore()
            store = newStore
            await refreshEvents()

            // Run database rollup jobs on startup
            Task {
                try? await newStore.performRollups()
            }
        } catch {
            storeError = error.localizedDescription
        }

        checkLaunchAtLoginStatus()

        captureTask = Task { [weak self] in
            await self?.captureLoop()
        }
    }

    deinit {
        captureTask?.cancel()
    }

    // MARK: – Refresh Events

    func refreshEvents() async {
        guard let store else { return }
        let interval = selectedInterval
        do {
            // Load historical events from SQLite
            let dbEvents = try await store.loadEvents(from: interval.start, to: interval.end)

            // Filter in-memory 1-second samples that fall within the selected interval
            let memoryEvents = inMemorySamples.filter {
                $0.timestamp >= interval.start && $0.timestamp <= interval.end
            }

            // Combine and update UI state
            self.events = dbEvents + memoryEvents
        } catch {
            storeError = error.localizedDescription
        }
    }

    // MARK: – Chart data

    func bucketsForSelectedRange() -> [UsageBucket] {
        let interval = selectedInterval
        return events
            .filtered(from: interval.start, to: interval.end)
            .bucketed(by: bucketComponent(for: interval), in: interval)
    }

    // MARK: – Today metrics

    var todayTotal: UInt64    { sumEvents(in: .today, keyPath: \.totalBytes) }
    var todayDownload: UInt64 { sumEvents(in: .today, keyPath: \.bytesReceived) }
    var todayUpload: UInt64   { sumEvents(in: .today, keyPath: \.bytesSent) }

    // MARK: – Month metric

    var monthTotal: UInt64 { sumEvents(in: .thisMonth, keyPath: \.totalBytes) }

    // MARK: – Yesterday metrics

    var yesterdayTotal: UInt64    { sumEvents(in: .yesterday, keyPath: \.totalBytes) }
    var yesterdayDownload: UInt64 { sumEvents(in: .yesterday, keyPath: \.bytesReceived) }
    var yesterdayUpload: UInt64   { sumEvents(in: .yesterday, keyPath: \.bytesSent) }

    // MARK: – Hourly extremes (today)

    var peakHourTotal: UInt64 {
        todayHourBuckets.map(\.total).max() ?? 0
    }

    var quietestHourTotal: UInt64 {
        todayHourBuckets.filter { $0.total > 0 }.map(\.total).min() ?? 0
    }

    private var todayHourBuckets: [UsageBucket] {
        let interval = fixedInterval(for: .today)
        return events.filtered(from: interval.start, to: interval.end)
            .bucketed(by: .hour)
    }

    // MARK: – Delta percentages vs. yesterday

    var todayVsYesterdayPercent: Int          { percentDelta(current: todayTotal,    previous: yesterdayTotal) }
    var todayDownloadVsYesterdayPercent: Int  { percentDelta(current: todayDownload, previous: yesterdayDownload) }
    var todayUploadVsYesterdayPercent: Int    { percentDelta(current: todayUpload,   previous: yesterdayUpload) }

    // MARK: – Selected interval

    var selectedInterval: DateInterval {
        if selectedRange == .custom {
            let s = min(customStartDate, customEndDate)
            let e = max(customStartDate, customEndDate)
            return DateInterval(start: s, end: e)
        }
        return fixedInterval(for: selectedRange)
    }

    // MARK: – Private helpers

    private func sumEvents(in range: DashboardRange, keyPath: KeyPath<UsageEvent, UInt64>) -> UInt64 {
        let interval = fixedInterval(for: range)
        return events
            .filtered(from: interval.start, to: interval.end)
            .reduce(UInt64(0)) { $0 + $1[keyPath: keyPath] }
    }

    private func percentDelta(current: UInt64, previous: UInt64) -> Int {
        guard previous > 0 else { return 0 }
        let delta = Int64(current) - Int64(previous)
        return Int((Double(delta) / Double(previous) * 100).rounded())
    }

    private func captureLoop() async {
        while !Task.isCancelled {
            await captureOnce()
            do {
                try await Task.sleep(for: .seconds(1))
            } catch is CancellationError {
                return
            } catch {
                // Continue on unexpected sleep error
            }
        }
    }

    private func captureOnce() async {
        do {
            let snapshot = try sampler.snapshot()
            defer {
                lastSnapshot = snapshot
                lastUpdated  = snapshot.capturedAt
            }

            guard let previous = lastSnapshot else { return }

            let elapsed = snapshot.capturedAt.timeIntervalSince(previous.capturedAt)
            guard elapsed > 0 else { return }

            let rxDelta = safeDelta(snapshot.bytesReceived, previous.bytesReceived)
            let txDelta = safeDelta(snapshot.bytesSent,    previous.bytesSent)

            interfaceRates              = buildRates(from: snapshot, previous: previous, elapsed: elapsed)
            currentDownloadBytesPerSecond = Double(rxDelta) / elapsed
            currentUploadBytesPerSecond   = Double(txDelta) / elapsed

            // Update Menu Bar speed title
            let dl = currentDownloadBytesPerSecond
            let ul = currentUploadBytesPerSecond
            Task { @MainActor in
                AppDelegate.shared?.updateStatusItemText(download: dl, upload: ul)
            }



            let event = UsageEvent(
                id: UUID(),
                timestamp: snapshot.capturedAt,
                bytesReceived: rxDelta,
                bytesSent: txDelta,
                intervalSeconds: elapsed
            )

            inMemorySamples.append(event)

            // Flush database on minute boundary rollover
            let cal = Calendar.current
            let currentMinuteStart = cal.dateInterval(of: .minute, for: snapshot.capturedAt)?.start ?? snapshot.capturedAt

            let toFlush = inMemorySamples.filter { $0.timestamp < currentMinuteStart }
            let toKeep = inMemorySamples.filter { $0.timestamp >= currentMinuteStart }

            if !toFlush.isEmpty {
                let grouped = Dictionary(grouping: toFlush) { e in
                    cal.dateInterval(of: .minute, for: e.timestamp)?.start ?? e.timestamp
                }

                for (minStart, minuteEvents) in grouped {
                    let totalRx = minuteEvents.reduce(0) { $0 + $1.bytesReceived }
                    let totalTx = minuteEvents.reduce(0) { $0 + $1.bytesSent }

                    if let store {
                        do {
                            try await store.insertMinute(timestamp: minStart, bytesReceived: totalRx, bytesSent: totalTx)
                        } catch {
                            storeError = error.localizedDescription
                        }
                    }
                }

                inMemorySamples = toKeep
            }

            await refreshEvents()

            // Periodically check/run rollups (hourly)
            let now = Date()
            if now.timeIntervalSince(lastRollupTime) > 3600 {
                lastRollupTime = now
                Task {
                    try? await store?.performRollups()
                }
            }
        } catch {
            currentDownloadBytesPerSecond = 0
            currentUploadBytesPerSecond   = 0
        }
    }

    private func safeDelta(_ current: UInt64, _ previous: UInt64) -> UInt64 {
        current >= previous ? current - previous : 0
    }

    private func buildRates(
        from snapshot: NetworkSnapshot,
        previous: NetworkSnapshot,
        elapsed: TimeInterval
    ) -> [InterfaceRate] {
        let prevByID = Dictionary(uniqueKeysWithValues: previous.interfaces.map { ($0.id, $0) })
        return snapshot.interfaces.compactMap { cur in
            guard let prev = prevByID[cur.id] else { return nil }
            let dl = Double(safeDelta(cur.bytesReceived, prev.bytesReceived)) / elapsed
            let ul = Double(safeDelta(cur.bytesSent,    prev.bytesSent))    / elapsed
            return InterfaceRate(
                id: cur.id,
                name: cur.name,
                displayName: cur.displayName,
                downloadBytesPerSecond: dl,
                uploadBytesPerSecond: ul
            )
        }
        .sorted { ($0.downloadBytesPerSecond + $0.uploadBytesPerSecond) >
                  ($1.downloadBytesPerSecond + $1.uploadBytesPerSecond) }
    }

    private func fixedInterval(for range: DashboardRange) -> DateInterval {
        let cal = Calendar.current
        let now = Date()
        switch range {
        case .today:
            return DateInterval(start: cal.startOfDay(for: now), end: now)
        case .yesterday:
            let today = cal.startOfDay(for: now)
            let start = cal.date(byAdding: .day, value: -1, to: today) ?? today
            return DateInterval(start: start, end: today)
        case .thisMonth:
            let month = cal.dateInterval(of: .month, for: now)
            return DateInterval(start: month?.start ?? now, end: now)
        case .last30Days:
            let start = cal.date(byAdding: .day, value: -30, to: now) ?? now
            return DateInterval(start: start, end: now)
        case .custom:
            return DateInterval(start: customStartDate, end: customEndDate)
        }
    }

    private func bucketComponent(for interval: DateInterval) -> Calendar.Component {
        interval.duration <= 60 * 60 * 36 ? .hour : .day
    }

    // MARK: – ServiceManagement Login Item

    private func checkLaunchAtLoginStatus() {
        if #available(macOS 13.0, *) {
            isLaunchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        }
    }

    private func toggleLaunchAtLogin(enabled: Bool) {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            do {
                if enabled {
                    if service.status != .enabled {
                        try service.register()
                    }
                } else {
                    if service.status == .enabled {
                        try service.unregister()
                    }
                }
            } catch {
                print("Failed to toggle login item status: \(error)")
            }
        }
    }
}
