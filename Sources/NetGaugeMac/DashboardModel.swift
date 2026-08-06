import Foundation
import SwiftUI
import ServiceManagement
import CoreWLAN
import SystemConfiguration

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

enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case dashboard = "Dashboard"
    case settings  = "Settings"
    var id: String { rawValue }
}

// MARK: - DashboardModel

@MainActor
final class DashboardModel: ObservableObject {

    // MARK: Published state
    @Published var selectedTab: AppTab = .dashboard
    @Published private(set) var events: [UsageEvent] = []
    @Published private(set) var currentDownloadBytesPerSecond: Double = 0
    @Published private(set) var currentUploadBytesPerSecond: Double = 0
    @Published private(set) var interfaceRates: [InterfaceRate] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var storeError: String?
    @Published private(set) var networkUsages: [NetworkUsageStats] = []
    @Published var selectedNetwork: String? = nil {
        didSet {
            guard selectedNetwork != oldValue else { return }
            Task { await refreshEvents() }
        }
    }

    // Range-aware metrics
    @Published private(set) var rangeDownload: UInt64 = 0
    @Published private(set) var rangeUpload: UInt64 = 0
    @Published private(set) var rangeTotal: UInt64 = 0

    @Published private(set) var previousDownload: UInt64 = 0
    @Published private(set) var previousUpload: UInt64 = 0
    @Published private(set) var previousTotal: UInt64 = 0

    @Published private(set) var rangePeak: UInt64 = 0
    @Published private(set) var rangeQuietest: UInt64 = 0


    @Published var selectedRange: DashboardRange = .today {
        didSet {
            guard selectedRange != oldValue else { return }
            Task { await refreshEvents() }
        }
    }
    @Published var customStartDate: Date = Calendar.current.date(
        byAdding: .day, value: -7, to: Date()) ?? Date() {
        didSet {
            guard customStartDate != oldValue else { return }
            Task { await refreshEvents() }
        }
    }
    @Published var customEndDate: Date = Date() {
        didSet {
            guard customEndDate != oldValue else { return }
            Task { await refreshEvents() }
        }
    }
    @Published var chartMode: ChartMode = .both
    @Published var isLaunchAtLoginEnabled: Bool = false {
        didSet {
            toggleLaunchAtLogin(enabled: isLaunchAtLoginEnabled)
        }
    }

    // Liquid Glass settings with UserDefaults persistence
    @Published var isLiquidGlassEnabled: Bool = UserDefaults.standard.bool(forKey: "isLiquidGlassEnabled") {
        didSet {
            UserDefaults.standard.set(isLiquidGlassEnabled, forKey: "isLiquidGlassEnabled")
        }
    }

    @Published var glassTransparency: Double = (UserDefaults.standard.object(forKey: "glassTransparency") as? Double) ?? 0.35 {
        didSet {
            UserDefaults.standard.set(glassTransparency, forKey: "glassTransparency")
        }
    }


    // MARK: Private
    private let sampler = NetworkSampler()
    private var store: UsageStore?
    private var lastSnapshot: NetworkSnapshot?
    private var captureTask: Task<Void, Never>?
    // Bug 10 fix: track the rollup task so it can be cancelled in deinit
    private var rollupTask: Task<Void, Never>?
    private var inMemorySamples: [UsageEvent] = []
    private var lastRollupTime: Date = Date()
    private var lastRefreshTime: Date = .distantPast
    private var lastFlushedMinute: Date = .distantPast
    private var todayEvents: [UsageEvent] = []
    private var yesterdayDownload: UInt64 = 0
    private var yesterdayUpload: UInt64 = 0
    private var monthTotalValue: UInt64 = 0
    private var networkUsageDeltas: [String: (rx: UInt64, tx: UInt64)] = [:]
    // SSID cache: maps BSD interface name → (ssid, lastLookedUp)
    private var ssidCache: [String: (name: String, cachedAt: Date)] = [:]

    // Bug 7 fix: expose window visibility so captureLoop can use a power-efficient
    // interval when the dashboard is hidden (menu-bar-only / accessory mode).
    var windowIsVisible: Bool = false

    // MARK: – Lifecycle

    func start() async {
        guard captureTask == nil else { return }

        // Request Location permission so we can read Wi-Fi SSID
        LocationHelper.shared.requestPermission()

        do {
            let newStore = try UsageStore()
            store = newStore
            await refreshEvents()

            // Run database rollup jobs on startup
            Task {
                try? await newStore.performRollups()
            }

            // Bug 1 fix: only start captureTask after the store is successfully
            // initialised. Previously the task was started unconditionally, meaning
            // it would spin forever making no-op DB writes when store == nil.
            captureTask = Task { [weak self] in
                await self?.captureLoop()
            }
        } catch {
            storeError = error.localizedDescription
        }

        checkLaunchAtLoginStatus()
    }

    deinit {
        captureTask?.cancel()
        // Bug 10 fix: cancel the rollup task on dealloc to prevent use-after-free
        rollupTask?.cancel()
    }

    // MARK: – Refresh Events

    func refreshEvents() async {
        guard let store else { return }
        let interval = selectedInterval
        let todayInt = fixedInterval(for: .today)
        let monthInt = fixedInterval(for: .thisMonth)
        let prevInt  = previousInterval
        let ydayInt  = fixedInterval(for: .yesterday)
        do {
            // Bug 8 fix: pre-compute a single pass over inMemorySamples, bucketing
            // events by time range and network name. Previously there were 7 separate
            // filter iterations (O(7N)), each traversing the full array. With 9,500
            // in-memory events that was ~66,500 iterations per refresh on @MainActor.
            struct MemBuckets {
                var selectedRx: UInt64 = 0; var selectedTx: UInt64 = 0
                var prevRx: UInt64     = 0; var prevTx: UInt64     = 0
                var todayRx: UInt64    = 0; var todayTx: UInt64    = 0
                var ydayRx: UInt64     = 0; var ydayTx: UInt64     = 0
                var monthRx: UInt64    = 0; var monthTx: UInt64    = 0
            }
            var memBuckets = MemBuckets()
            // Per-network today/month accumulators for the network usage panel
            var memTodayByNet:  [String: (rx: UInt64, tx: UInt64)] = [:]
            var memMonthByNet:  [String: (rx: UInt64, tx: UInt64)] = [:]

            for e in inMemorySamples {
                let ts = e.timestamp
                let net = e.networkName

                let matchesFilter = (selectedNetwork == nil || net == selectedNetwork)

                if matchesFilter && ts >= interval.start && ts <= interval.end {
                    memBuckets.selectedRx += e.bytesReceived
                    memBuckets.selectedTx += e.bytesSent
                }
                if matchesFilter && ts >= prevInt.start && ts <= prevInt.end {
                    memBuckets.prevRx += e.bytesReceived
                    memBuckets.prevTx += e.bytesSent
                }
                if matchesFilter && ts >= todayInt.start && ts <= todayInt.end {
                    memBuckets.todayRx += e.bytesReceived
                    memBuckets.todayTx += e.bytesSent
                }
                if matchesFilter && ts >= ydayInt.start && ts <= ydayInt.end {
                    memBuckets.ydayRx += e.bytesReceived
                    memBuckets.ydayTx += e.bytesSent
                }
                if matchesFilter && ts >= monthInt.start && ts <= monthInt.end {
                    memBuckets.monthRx += e.bytesReceived
                    memBuckets.monthTx += e.bytesSent
                }
                // Network usage panel — always per-network, regardless of filter
                if let net {
                    if ts >= todayInt.start && ts <= todayInt.end {
                        let cur = memTodayByNet[net] ?? (0, 0)
                        memTodayByNet[net] = (cur.rx + e.bytesReceived, cur.tx + e.bytesSent)
                    }
                    if ts >= monthInt.start && ts <= monthInt.end {
                        let cur = memMonthByNet[net] ?? (0, 0)
                        memMonthByNet[net] = (cur.rx + e.bytesReceived, cur.tx + e.bytesSent)
                    }
                }
            }

            // Load historical events from SQLite for the chart
            let dbEvents = try await store.loadEvents(from: interval.start, to: interval.end, networkName: selectedNetwork)
            // Combine DB events with in-memory events that fall in the selected range
            let memoryEvents = inMemorySamples.filter {
                $0.timestamp >= interval.start && $0.timestamp <= interval.end &&
                (selectedNetwork == nil || $0.networkName == selectedNetwork)
            }
            self.events = dbEvents + memoryEvents

            // Load range-specific metrics
            self.rangeDownload = self.events.reduce(0) { $0 + $1.bytesReceived }
            self.rangeUpload = self.events.reduce(0) { $0 + $1.bytesSent }
            self.rangeTotal = self.rangeDownload + self.rangeUpload

            // Load previous period metrics for percentage calculation
            let prevDb = try await store.loadTotals(from: prevInt.start, to: prevInt.end, networkName: selectedNetwork)
            self.previousDownload = prevDb.rx + memBuckets.prevRx
            self.previousUpload   = prevDb.tx + memBuckets.prevTx
            self.previousTotal    = self.previousDownload + self.previousUpload

            // Load peak and quietest periods in selected range
            let buckets = bucketsForSelectedRange()
            self.rangePeak     = buckets.map(\.total).max() ?? 0
            self.rangeQuietest = buckets.filter { $0.total > 0 }.map(\.total).min() ?? 0

            // Load Today's events to compute Today's extremes and totals
            let dbToday = try await store.loadEvents(from: todayInt.start, to: todayInt.end, networkName: selectedNetwork)
            let memoryToday = inMemorySamples.filter {
                $0.timestamp >= todayInt.start && $0.timestamp <= todayInt.end &&
                (selectedNetwork == nil || $0.networkName == selectedNetwork)
            }
            self.todayEvents = dbToday + memoryToday

            // Load Yesterday's totals
            let ydayDb = try await store.loadTotals(from: ydayInt.start, to: ydayInt.end, networkName: selectedNetwork)
            self.yesterdayDownload = ydayDb.rx + memBuckets.ydayRx
            self.yesterdayUpload   = ydayDb.tx + memBuckets.ydayTx

            // Load This Month's totals
            let monthDb = try await store.loadTotals(from: monthInt.start, to: monthInt.end, networkName: selectedNetwork)
            self.monthTotalValue = monthDb.rx + monthDb.tx + memBuckets.monthRx + memBuckets.monthTx

            // Load Network Usages
            var dbNetworkUsages = try await store.loadNetworkUsages(todayStart: todayInt.start, monthStart: monthInt.start)

            // Apply in-memory samples for each network (using pre-computed per-network buckets)
            for i in 0..<dbNetworkUsages.count {
                let name = dbNetworkUsages[i].networkName
                let tMem = memTodayByNet[name] ?? (0, 0)
                let mMem = memMonthByNet[name] ?? (0, 0)
                let totalMemRx = networkUsageDeltas[name]?.rx ?? 0
                let totalMemTx = networkUsageDeltas[name]?.tx ?? 0
                dbNetworkUsages[i] = NetworkUsageStats(
                    networkName: name,
                    todayRx:  dbNetworkUsages[i].todayRx  + tMem.rx,
                    todayTx:  dbNetworkUsages[i].todayTx  + tMem.tx,
                    monthRx:  dbNetworkUsages[i].monthRx  + mMem.rx,
                    monthTx:  dbNetworkUsages[i].monthTx  + mMem.tx,
                    totalRx:  dbNetworkUsages[i].totalRx  + totalMemRx,
                    totalTx:  dbNetworkUsages[i].totalTx  + totalMemTx,
                    lastUpdated: dbNetworkUsages[i].lastUpdated
                )
            }

            // Capture newly connected interfaces that only have in-memory data
            let allNetworkNames = Set(dbNetworkUsages.map { $0.networkName })
                .union(memTodayByNet.keys)
                .union(networkUsageDeltas.keys)
            for name in allNetworkNames {
                if !dbNetworkUsages.contains(where: { $0.networkName == name }) {
                    let tMem = memTodayByNet[name] ?? (0, 0)
                    let mMem = memMonthByNet[name] ?? (0, 0)
                    let totalMemRx = networkUsageDeltas[name]?.rx ?? 0
                    let totalMemTx = networkUsageDeltas[name]?.tx ?? 0
                    dbNetworkUsages.append(NetworkUsageStats(
                        networkName: name,
                        todayRx:  tMem.rx,
                        todayTx:  tMem.tx,
                        monthRx:  mMem.rx,
                        monthTx:  mMem.tx,
                        totalRx:  totalMemRx,
                        totalTx:  totalMemTx,
                        lastUpdated: Date()
                    ))
                }
            }

            self.networkUsages = dbNetworkUsages.sorted {
                if $0.todayTotal != $1.todayTotal { return $0.todayTotal > $1.todayTotal }
                if $0.monthTotal != $1.monthTotal { return $0.monthTotal > $1.monthTotal }
                return $0.totalBytes > $1.totalBytes
            }
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

    var todayTotal: UInt64    { todayEvents.reduce(0) { $0 + $1.totalBytes } }
    var todayDownload: UInt64 { todayEvents.reduce(0) { $0 + $1.bytesReceived } }
    var todayUpload: UInt64   { todayEvents.reduce(0) { $0 + $1.bytesSent } }

    // MARK: – Month metric

    var monthTotal: UInt64 { monthTotalValue }

    // MARK: – Yesterday metrics

    var yesterdayTotal: UInt64    { yesterdayDownload + yesterdayUpload }

    // MARK: – Hourly extremes (today)

    var peakHourTotal: UInt64 {
        todayHourBuckets.map(\.total).max() ?? 0
    }

    var quietestHourTotal: UInt64 {
        todayHourBuckets.filter { $0.total > 0 }.map(\.total).min() ?? 0
    }

    private var todayHourBuckets: [UsageBucket] {
        let interval = fixedInterval(for: .today)
        return todayEvents.filtered(from: interval.start, to: interval.end)
            .bucketed(by: .hour)
    }

    // MARK: – Delta percentages vs. yesterday

    var todayVsYesterdayPercent: Int          { percentDelta(current: todayTotal,    previous: yesterdayTotal) }
    var todayDownloadVsYesterdayPercent: Int  { percentDelta(current: todayDownload, previous: yesterdayDownload) }
    var todayUploadVsYesterdayPercent: Int    { percentDelta(current: todayUpload,   previous: yesterdayUpload) }

    // MARK: – Delta percentages vs. previous period

    var rangeVsPreviousPercent: Int {
        percentDelta(current: rangeTotal, previous: previousTotal)
    }
    var rangeDownloadVsPreviousPercent: Int {
        percentDelta(current: rangeDownload, previous: previousDownload)
    }
    var rangeUploadVsPreviousPercent: Int {
        percentDelta(current: rangeUpload, previous: previousUpload)
    }

    // MARK: – Selected interval

    var selectedInterval: DateInterval {
        if selectedRange == .custom {
            let s = min(customStartDate, customEndDate)
            let e = max(customStartDate, customEndDate)
            return DateInterval(start: s, end: e)
        }
        return fixedInterval(for: selectedRange)
    }

    var previousInterval: DateInterval {
        let current = selectedInterval
        let duration = current.duration
        let start = current.start.addingTimeInterval(-duration)
        return DateInterval(start: start, end: current.start)
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
        // Use clamped conversion to prevent Int64 overflow for very large UInt64 values
        let c = Int64(clamping: current)
        let p = Int64(clamping: previous)
        let delta = c - p
        return Int((Double(delta) / Double(p) * 100).rounded())
    }

    private func captureLoop() async {
        while !Task.isCancelled {
            await captureOnce()
            // Bug 7 fix: use a 2-second interval when the window is hidden
            // (menu-bar-only / accessory mode) to reduce CPU wakeups and battery drain.
            // The status bar speed text only needs ~1Hz when the dashboard is open.
            let interval: Duration = windowIsVisible ? .seconds(1) : .seconds(2)
            do {
                try await Task.sleep(for: interval)
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
            guard elapsed >= 0.5 else { return }

            let rxDelta = safeDelta(snapshot.bytesReceived, previous.bytesReceived)
            let txDelta = safeDelta(snapshot.bytesSent,    previous.bytesSent)

            interfaceRates              = buildRates(from: snapshot, previous: previous, elapsed: elapsed)
            currentDownloadBytesPerSecond = Double(rxDelta) / elapsed
            currentUploadBytesPerSecond   = Double(txDelta) / elapsed

            // Update Menu Bar speed title
            AppDelegate.shared?.updateStatusItemText(download: currentDownloadBytesPerSecond, upload: currentUploadBytesPerSecond)

            // Accumulate delta bytes per network interface
            let prevByID = Dictionary(uniqueKeysWithValues: previous.interfaces.map { ($0.id, $0) })
            for cur in snapshot.interfaces {
                if let prev = prevByID[cur.id] {
                    let rx = safeDelta(cur.bytesReceived, prev.bytesReceived)
                    let tx = safeDelta(cur.bytesSent, prev.bytesSent)
                    if rx > 0 || tx > 0 {
                        // Use cached SSID — only re-query CoreWLAN/SystemConfiguration
                        // every 30 seconds per interface to avoid per-second overhead.
                        let netName = cachedNetworkName(for: cur.name, at: snapshot.capturedAt)
                        let currentAccum = networkUsageDeltas[netName] ?? (0, 0)
                        networkUsageDeltas[netName] = (currentAccum.0 + rx, currentAccum.1 + tx)

                        // Append an in-memory sample for this network interface.
                        // Force-flush to DB when approaching the cap to prevent data loss.
                        if inMemorySamples.count >= 9_500 {
                            // About to hit cap — flush all current samples immediately
                            let calFlush = Calendar.current
                            struct ForceGroupKey: Hashable {
                                let minStart: Date
                                let networkName: String
                            }
                            var forceGrouped: [ForceGroupKey: (rx: UInt64, tx: UInt64)] = [:]
                            for e in inMemorySamples {
                                let minStart = calFlush.dateInterval(of: .minute, for: e.timestamp)?.start ?? e.timestamp
                                let netN = e.networkName ?? "Primary"
                                let key = ForceGroupKey(minStart: minStart, networkName: netN)
                                let cur = forceGrouped[key] ?? (0, 0)
                                forceGrouped[key] = (cur.0 + e.bytesReceived, cur.1 + e.bytesSent)
                            }
                            for (key, data) in forceGrouped {
                                if let store {
                                    try? await store.insertMinute(timestamp: key.minStart, networkName: key.networkName, bytesReceived: data.rx, bytesSent: data.tx)
                                }
                            }
                            inMemorySamples.removeAll()
                        }
                        let event = UsageEvent(
                            id: UUID(),
                            timestamp: snapshot.capturedAt,
                            bytesReceived: rx,
                            bytesSent: tx,
                            intervalSeconds: elapsed,
                            networkName: netName
                        )
                        inMemorySamples.append(event)
                    }
                }
            }

            // Flush database on minute boundary rollover
            let cal = Calendar.current
            let currentMinuteStart = cal.dateInterval(of: .minute, for: snapshot.capturedAt)?.start ?? snapshot.capturedAt

            let toFlush = inMemorySamples.filter { $0.timestamp < currentMinuteStart }

            if !toFlush.isEmpty {
                // Group by timestamp and network name!
                struct GroupKey: Hashable {
                    let minStart: Date
                    let networkName: String
                }
                
                var grouped: [GroupKey: (rx: UInt64, tx: UInt64)] = [:]
                for e in toFlush {
                    let minStart = cal.dateInterval(of: .minute, for: e.timestamp)?.start ?? e.timestamp
                    let netName = e.networkName ?? "Primary"
                    let key = GroupKey(minStart: minStart, networkName: netName)
                    let current = grouped[key] ?? (0, 0)
                    grouped[key] = (current.0 + e.bytesReceived, current.1 + e.bytesSent)
                }

                for (key, data) in grouped {
                    if let store {
                        do {
                            try await store.insertMinute(timestamp: key.minStart, networkName: key.networkName, bytesReceived: data.rx, bytesSent: data.tx)
                        } catch {
                            storeError = error.localizedDescription
                        }
                    }
                }

                // Flush network-specific usage deltas
                if let store = store {
                    for (netName, data) in networkUsageDeltas {
                        do {
                            try await store.updateNetworkUsage(networkName: netName, bytesReceived: data.rx, bytesSent: data.tx, timestamp: snapshot.capturedAt)
                        } catch {
                            storeError = error.localizedDescription
                        }
                    }
                }
                networkUsageDeltas.removeAll()

                inMemorySamples.removeAll(where: { sample in
                    toFlush.contains(where: { $0.id == sample.id })
                })
            }

            // Bug 7 fix: skip refreshEvents() entirely when the window is not visible.
            // The dashboard doesn't need updated chart/metric data while hidden;
            // skipping avoids complex SQLite queries and 15+ @Published property
            // updates on the main actor every 5 seconds for a hidden window.
            let now = Date()
            let didFlush = !toFlush.isEmpty
            if windowIsVisible {
                if didFlush || now.timeIntervalSince(lastRefreshTime) >= 5 {
                    lastRefreshTime = now
                    await refreshEvents()
                }
            } else if didFlush {
                // Even when hidden, advance the timestamp so we don't burst-refresh
                // immediately when the window becomes visible again.
                lastRefreshTime = now
            }

            // Periodically check/run rollups (hourly)
            if now.timeIntervalSince(lastRollupTime) > 3600 {
                lastRollupTime = now
                // Bug 10 fix: store the task handle so it can be cancelled in deinit
                rollupTask?.cancel()
                rollupTask = Task {
                    try? await store?.performRollups()
                }
            }
        } catch {
            currentDownloadBytesPerSecond = 0
            currentUploadBytesPerSecond   = 0
        }
    }

    private func safeDelta(_ current: UInt64, _ previous: UInt64) -> UInt64 {
        if current >= previous {
            return current - previous
        }
        // Handle 32-bit kernel counter overflow at ~4.29 GB.
        // getifaddrs ifi_ibytes/ifi_obytes are u_int32_t on macOS — they wrap at UInt32.max.
        let overflowDelta = (UInt64(UInt32.max) - previous) + current + 1
        // Cap at ~10 GB/s to prevent false traffic spikes on interface reset
        // (e.g., wake from sleep resets counters to 0)
        let maxReasonableDelta: UInt64 = 10_000_000_000  // 10 GB
        return overflowDelta > maxReasonableDelta ? 0 : overflowDelta
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
            
            // Only show interfaces if:
            // 1. It is a Wi-Fi or Ethernet interface (name hasPrefix "en")
            // 2. OR it has active traffic (dl > 0 or ul > 0)
            let isWifiOrEthernet = cur.name.hasPrefix("en")
            let hasActiveTraffic = dl > 0 || ul > 0
            
            guard isWifiOrEthernet || hasActiveTraffic else {
                return nil
            }
            
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
            let s = min(customStartDate, customEndDate)
            let e = max(customStartDate, customEndDate)
            return DateInterval(start: s, end: e)
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

    /// Returns the cached network name for a BSD interface name.
    /// Re-queries CoreWLAN/SystemConfiguration at most every 30 seconds per interface
    /// to avoid expensive synchronous calls on every 1-second capture tick.
    private func cachedNetworkName(for interfaceName: String, at now: Date) -> String {
        if let cached = ssidCache[interfaceName],
           now.timeIntervalSince(cached.cachedAt) < 30 {
            return cached.name
        }
        // Bug 15 fix: SCNetworkInterfaceCopyAll() and CWWiFiClient calls can block
        // for tens of milliseconds (Wi-Fi handoff, interface changes). Move the lookup
        // off the @MainActor to a detached background task; serve the stale cache
        // immediately and update it when the lookup completes.
        //
        // Seed the cache with the interface name so we have something to return
        // immediately and avoid re-dispatching before the async result comes back.
        let placeholder = ssidCache[interfaceName]?.name ?? interfaceName
        ssidCache[interfaceName] = (name: placeholder, cachedAt: now)

        Task.detached(priority: .utility) { [weak self] in
            let resolved = await Task.detached(priority: .utility) {
                getNetworkNameBackground(for: interfaceName)
            }.value
            await MainActor.run { [weak self] in
                self?.ssidCache[interfaceName] = (name: resolved, cachedAt: Date())
            }
        }

        return placeholder
    }

    // Kept for reference — callers now use getNetworkNameBackground (free function) via Task.detached
    private func getNetworkName(for interfaceName: String) -> String {
        getNetworkNameBackground(for: interfaceName)
    }

    /// Flush any accumulated in-memory deltas to the database immediately.
    /// Called on graceful shutdown so no data is lost for sessions < 1 minute.
    func flushPendingData() async {
        guard let store else { return }
        let cal = Calendar.current
        guard !inMemorySamples.isEmpty || !networkUsageDeltas.isEmpty else { return }

        struct GroupKey: Hashable {
            let minStart: Date
            let networkName: String
        }
        var grouped: [GroupKey: (rx: UInt64, tx: UInt64)] = [:]
        for e in inMemorySamples {
            let minStart = cal.dateInterval(of: .minute, for: e.timestamp)?.start ?? e.timestamp
            let netName = e.networkName ?? "Primary"
            let key = GroupKey(minStart: minStart, networkName: netName)
            let current = grouped[key] ?? (0, 0)
            grouped[key] = (current.0 + e.bytesReceived, current.1 + e.bytesSent)
        }
        for (key, data) in grouped {
            try? await store.insertMinute(timestamp: key.minStart, networkName: key.networkName, bytesReceived: data.rx, bytesSent: data.tx)
        }
        for (netName, data) in networkUsageDeltas {
            try? await store.updateNetworkUsage(networkName: netName, bytesReceived: data.rx, bytesSent: data.tx, timestamp: Date())
        }
        networkUsageDeltas.removeAll()
        inMemorySamples.removeAll()
    }

    /// Resets all network usage data, wipes SQLite database tables,
    /// clears in-memory buffers, and resets kernel sampling baselines.
    func clearAllData() async {
        do {
            try await store?.clearAllData()
        } catch {
            storeError = error.localizedDescription
        }

        inMemorySamples.removeAll()
        networkUsageDeltas.removeAll()
        ssidCache.removeAll()
        todayEvents.removeAll()
        yesterdayDownload = 0
        yesterdayUpload = 0
        monthTotalValue = 0
        interfaceRates = []
        currentDownloadBytesPerSecond = 0
        currentUploadBytesPerSecond = 0
        events = []
        networkUsages = []
        rangeDownload = 0
        rangeUpload = 0
        rangeTotal = 0
        previousDownload = 0
        previousUpload = 0
        previousTotal = 0
        rangePeak = 0
        rangeQuietest = 0
        selectedNetwork = nil

        // Reset sampler snapshot baseline so new traffic measures from zero
        if let current = try? sampler.snapshot() {
            lastSnapshot = current
            lastUpdated = current.capturedAt
        } else {
            lastSnapshot = nil
            lastUpdated = nil
        }

        await refreshEvents()
    }
}

// MARK: - Background network name resolver (Bug 15 fix)
// This is a nonisolated free function so it can be called from Task.detached
// (or any concurrency context) without inheriting the @MainActor isolation of
// DashboardModel. SCNetworkInterfaceCopyAll and CWWiFiClient can block for
// tens of milliseconds; keeping them off the main thread prevents UI frame drops.

import CoreWLAN

func getNetworkNameBackground(for interfaceName: String) -> String {
    var displayName = interfaceName
    var isWifi = false

    if let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] {
        for interface in interfaces {
            if let bsdName = SCNetworkInterfaceGetBSDName(interface) as String?,
               bsdName == interfaceName {
                if let disp = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? {
                    displayName = disp
                }
                if let type = SCNetworkInterfaceGetInterfaceType(interface) as String?,
                   type == (kSCNetworkInterfaceTypeIEEE80211 as String) {
                    isWifi = true
                }
                break
            }
        }
    }

    // Wi-Fi SSID resolution
    if isWifi || displayName.localizedCaseInsensitiveContains("Wi-Fi") || interfaceName == "en0" {
        let client = CWWiFiClient.shared()
        if let wifiInterface = client.interface(withName: interfaceName),
           let ssid = wifiInterface.ssid(), !ssid.isEmpty {
            return "Wi-Fi: \(ssid)"
        }
        if let allInterfaces = client.interfaces() {
            for iface in allInterfaces {
                if iface.interfaceName == interfaceName,
                   let ssid = iface.ssid(), !ssid.isEmpty {
                    return "Wi-Fi: \(ssid)"
                }
            }
        }
        // SSID unresolvable (Location not granted, or airplane mode)
        return "Wi-Fi (\(interfaceName))"
    }

    return displayName
}

// MARK: - Location Services Helper
import CoreLocation

@MainActor
final class LocationHelper: NSObject, @preconcurrency CLLocationManagerDelegate {
    static let shared = LocationHelper()
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
    }

    func requestPermission() {
        let status = manager.authorizationStatus
        if status == .notDetermined {
            // requestWhenInUseAuthorization is the correct API on macOS.
            // requestAlwaysAuthorization is iOS-only and is silently ignored on macOS.
            manager.requestWhenInUseAuthorization()
        }
        // Bug 14 fix: do NOT call requestLocation() when already authorized.
        // requestLocation() triggers a one-time GPS hardware power-on that is
        // completely unnecessary — the CoreLocation permission grant alone is
        // sufficient to unblock CWWiFiClient SSID resolution on macOS.
    }

    var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Empty — location is only requested to unblock SSID resolution via CoreWLAN.
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Ignore location errors; Wi-Fi fallback to interface-name is acceptable.
    }
}
