import AppKit
import Charts
import SwiftUI

// MARK: - Design Tokens
// All colours, radii and shadow values in one place for easy theming.

private let ngBg         = Color(red: 0.918, green: 0.929, blue: 0.945)   // soft blue-gray page
private let ngCard       = Color.white
private let ngDownload   = Color(red: 0.047, green: 0.647, blue: 0.761)   // teal  – received
private let ngUpload     = Color(red: 0.482, green: 0.380, blue: 1.000)   // violet – sent
private let ngAccent     = Color(red: 0.957, green: 0.635, blue: 0.157)   // amber  – highlight
private let ngGreen      = Color(red: 0.173, green: 0.733, blue: 0.400)
private let ngRed        = Color(red: 0.910, green: 0.255, blue: 0.255)
private let ngText1      = Color(red: 0.086, green: 0.098, blue: 0.122)
private let ngText2      = Color(red: 0.420, green: 0.455, blue: 0.522)
private let ngSep        = Color(red: 0.878, green: 0.894, blue: 0.914)
private let ngRadius     = 16.0

// MARK: - Card View Modifier

private struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(ngCard)
            .clipShape(RoundedRectangle(cornerRadius: ngRadius, style: .continuous))
            .shadow(color: .black.opacity(0.055), radius: 16, x: 0, y: 4)
            .overlay {
                RoundedRectangle(cornerRadius: ngRadius, style: .continuous)
                    .strokeBorder(ngSep, lineWidth: 0.5)
            }
    }
}

private extension View {
    func ngCard() -> some View { modifier(CardStyle()) }
}

// MARK: - DashboardView

struct DashboardView: View {
    @EnvironmentObject private var model: DashboardModel

    @State private var selectedBucket: UsageBucket?
    @State private var selectedChartX: CGFloat?
    @State private var livePulse       = false
    @State private var tooltipDismissTask: Task<Void, Never>?

    // Settings & Alert states
    @State private var showClearConfirmation = false
    @State private var showSuccessToast = false

    var body: some View {
        ZStack(alignment: .top) {
            ngBg.ignoresSafeArea()

            VStack(spacing: 0) {
                topNavigationBar

                ngSep.frame(height: 1)

                if model.selectedTab == .dashboard {
                    dashboardContent
                } else {
                    settingsContent
                }
            }

            // Success Toast Notification Banner
            if showSuccessToast {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(ngGreen)
                    Text("All network speed data cleared. App reset to fresh install state.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ngText1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.white)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                .overlay {
                    Capsule().strokeBorder(ngGreen.opacity(0.4), lineWidth: 1)
                }
                .padding(.top, 60)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: showSuccessToast)
        .animation(.easeInOut(duration: 0.2), value: model.selectedTab)
        .alert("Clear All Network Data?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All Data", role: .destructive) {
                Task {
                    await model.clearAllData()
                    withAnimation {
                        showSuccessToast = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                        withAnimation {
                            showSuccessToast = false
                        }
                    }
                }
            }
        } message: {
            Text("This will permanently delete all recorded network speed and usage history and reset NetGauge to its fresh install state. This action cannot be undone.")
        }
        .onAppear { livePulse = true }
    }

    // MARK: – Top Navigation Bar

    private var topNavigationBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 10) {
                if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
                   let nsImg = NSImage(contentsOf: url) {
                    Image(nsImage: nsImg)
                        .resizable()
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                        .font(.system(size: 18))
                        .foregroundStyle(ngDownload)
                }
                Text("NetGauge")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(ngText1)
            }

            Spacer()

            AppTabPicker(selected: $model.selectedTab)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .windowDragIfAvailable()
    }

    // MARK: – Dashboard Content

    private var dashboardContent: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 24) {
                headlineAndMetrics
                liveRateStrip
                chartSection
                HStack(alignment: .top, spacing: 20) {
                    performancePanel
                    VStack(spacing: 20) {
                        interfacePanel
                        networkUsagePanel
                    }
                }
                captureFooter
            }
            .padding(28)
        }
        .id(model.selectedRange)
    }

    // MARK: – Headline + Hero Metrics

    private var headlineAndMetrics: some View {
        HStack(alignment: .top, spacing: 0) {

            // Left — title + range picker
            // This region doubles as the window drag handle (required with .hiddenTitleBar).
            VStack(alignment: .leading, spacing: 10) {
                // Pulsing live badge
                HStack(spacing: 7) {
                    ZStack {
                        Circle()
                            .stroke(ngGreen.opacity(0.35), lineWidth: 6)
                            .frame(width: 16, height: 16)
                            .scaleEffect(livePulse ? 1.8 : 1.0)
                            .opacity(livePulse ? 0 : 0.7)
                            .animation(
                                .easeOut(duration: 1.3).repeatForever(autoreverses: false),
                                value: livePulse
                            )
                        Circle()
                            .fill(ngGreen)
                            .frame(width: 8, height: 8)
                    }
                    Text("LIVE MONITORING")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ngText2)
                        .tracking(1.5)
                }

                Text("Live Traffic")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(ngText1)

                // Time-period pills
                RangePicker(selected: $model.selectedRange)

                // Custom date pickers (only when Custom is active)
                if model.selectedRange == .custom {
                    HStack(spacing: 10) {
                        DatePicker("From",
                                   selection: $model.customStartDate,
                                   displayedComponents: [.date, .hourAndMinute])
                        DatePicker("To",
                                   selection: $model.customEndDate,
                                   displayedComponents: [.date, .hourAndMinute])
                    }
                    .labelsHidden()
                    .font(.caption)
                    .tint(ngDownload)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.22), value: model.selectedRange)
            // Allow window dragging from the headline area (HIG requirement for hiddenTitleBar).
            // WindowDragGesture requires macOS 15+; on macOS 14 the window is draggable
            // from untinted background areas automatically.
            .windowDragIfAvailable()


            Spacer()

            // Right — three hero stat cards (mirrors reference image layout)
            HStack(alignment: .top, spacing: 40) {
                HeroMetric(
                    value: heroValue(model.rangeTotal),
                    unit:  heroUnit(model.rangeTotal),
                    label: model.selectedRange.heroTotalLabel,
                    deltaValue: model.rangeVsPreviousPercent,
                    deltaLabel: model.selectedRange.heroTotalDeltaLabel
                )

                ngSep.frame(width: 1, height: 70).padding(.top, 6)

                HeroMetric(
                    value: model.rangePeak > 0 ? heroValue(model.rangePeak) : "—",
                    unit:  model.rangePeak > 0 ? heroUnit(model.rangePeak) : "",
                    label: model.selectedRange.heroPeakLabel,
                    deltaValue: nil,
                    deltaLabel: model.selectedRange.heroPeakDeltaLabel,
                    badge: "▲ Peak",
                    badgeColor: ngAccent
                )

                ngSep.frame(width: 1, height: 70).padding(.top, 6)

                HeroMetric(
                    value: model.rangeQuietest > 0 ? heroValue(model.rangeQuietest) : "—",
                    unit:  model.rangeQuietest > 0 ? heroUnit(model.rangeQuietest)  : "",
                    label: model.selectedRange.heroQuietestLabel,
                    deltaValue: nil,
                    deltaLabel: model.selectedRange.heroQuietestDeltaLabel,
                    badge: "▼ Low",
                    badgeColor: ngDownload
                )
            }
            .padding(.top, 6)
        }
    }

    // MARK: – Live Rate Strip

    private var liveRateStrip: some View {
        HStack(spacing: 0) {
            RateTile(icon: "arrow.down.circle.fill",
                     title: "Download",
                     value: model.currentDownloadBytesPerSecond.speedString,
                     color: ngDownload)

            ngSep.frame(width: 1).padding(.vertical, 14)

            RateTile(icon: "arrow.up.circle.fill",
                     title: "Upload",
                     value: model.currentUploadBytesPerSecond.speedString,
                     color: ngUpload)

            ngSep.frame(width: 1).padding(.vertical, 14)

            RateTile(icon: "clock.fill",
                     title: model.selectedRange.rateStripSelectedTitle,
                     value: model.rangeTotal.byteString,
                     color: ngText1)

            ngSep.frame(width: 1).padding(.vertical, 14)

            let isTodayOrYday = model.selectedRange == .today || model.selectedRange == .yesterday
            RateTile(icon: isTodayOrYday ? "calendar" : "clock",
                     title: model.selectedRange.rateStripAlternativeTitle,
                     value: isTodayOrYday ? model.monthTotal.byteString : model.todayTotal.byteString,
                     color: ngAccent)
        }
        .padding(.vertical, 4)
        .ngCard()
    }

    // MARK: – Chart Section

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Chart header row
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Usage Distribution")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(ngText1)
                    Text("Bytes transferred over the selected period")
                        .font(.caption)
                        .foregroundStyle(ngText2)
                }

                Spacer()

                // Network Dropdown Picker
                Menu {
                    Button(action: { model.selectedNetwork = nil }) {
                        HStack {
                            Text("All Networks")
                            if model.selectedNetwork == nil {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    ForEach(model.networkUsages) { stats in
                        Button(action: { model.selectedNetwork = stats.networkName }) {
                            HStack {
                                Text(stats.networkName)
                                if model.selectedNetwork == stats.networkName {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: model.selectedNetwork == nil ? "network" : "wifi.router")
                            .font(.system(size: 11, weight: .semibold))
                        Text(model.selectedNetwork ?? "All Networks")
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(ngText1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(ngBg)
                    .clipShape(Capsule())
                }
                .menuStyle(.button)

                // Mode pills: Both / Download / Upload
                ChartModePicker(selected: $model.chartMode)

                // Legend
                HStack(spacing: 14) {
                    if model.chartMode != .upload {
                        LegendItem(label: "Download", color: ngDownload)
                    }
                    if model.chartMode != .download {
                        LegendItem(label: "Upload",   color: ngUpload)
                    }
                }
                .padding(.leading, 6)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            ngSep.frame(height: 1)

            // Chart body or empty state
            let buckets = model.bucketsForSelectedRange()

            if buckets.isEmpty {
                emptyChartState
            } else {
                ZStack(alignment: .topLeading) {
                    usageChart(buckets: buckets)

                    // Hover / tap tooltip
                    if let bucket = selectedBucket, let xPos = selectedChartX {
                        ChartTooltipCard(bucket: bucket)
                            .offset(x: xPos - 92, y: 16)
                            .transition(.scale(scale: 0.92).combined(with: .opacity))
                    }
                }
                .animation(.snappy(duration: 0.15), value: selectedBucket?.id)
            }
        }
        .padding(.bottom, 20)
        .ngCard()
    }

    private var emptyChartState: some View {
        ContentUnavailableView(
            "Waiting for network activity",
            systemImage: "chart.xyaxis.line",
            description: Text(
                "Leave NetGauge running. Data appears after traffic crosses an active interface."
            )
        )
        .frame(maxWidth: .infinity, minHeight: 300)
        .foregroundStyle(ngText2)
    }

    @ViewBuilder
    private func usageChart(buckets: [UsageBucket]) -> some View {
        Chart {
            // ── Download series ───────────────────────────────────────────
            if model.chartMode != .upload {
                ForEach(buckets) { bucket in
                    AreaMark(
                        x: .value("Time",     bucket.label),
                        y: .value("Download", Double(bucket.received)),
                        series: .value("Series", "Download")
                    )
                    .foregroundStyle(ngDownload.opacity(0.20))
                    .interpolationMethod(.monotone)

                    LineMark(
                        x: .value("Time",     bucket.label),
                        y: .value("Download", Double(bucket.received)),
                        series: .value("Series", "Download")
                    )
                    .foregroundStyle(ngDownload)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                }
            }

            // ── Upload series ─────────────────────────────────────────────
            if model.chartMode != .download {
                ForEach(buckets) { bucket in
                    AreaMark(
                        x: .value("Time",   bucket.label),
                        y: .value("Upload", Double(bucket.sent)),
                        series: .value("Series", "Upload")
                    )
                    .foregroundStyle(ngUpload.opacity(0.18))
                    .interpolationMethod(.monotone)

                    LineMark(
                        x: .value("Time",   bucket.label),
                        y: .value("Upload", Double(bucket.sent)),
                        series: .value("Series", "Upload")
                    )
                    .foregroundStyle(ngUpload)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                }
            }

            // ── Selected bucket highlight ─────────────────────────────────
            if let sel = selectedBucket {
                RuleMark(x: .value("Selected", sel.label))
                    .foregroundStyle(ngText2.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(ngSep)
                AxisValueLabel {
                    if let bytes = value.as(Double.self) {
                        Text(UInt64(max(bytes, 0)).shortByteString)
                            .font(.caption2)
                            .foregroundStyle(ngText2)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel(anchor: .topTrailing) {
                    if let label = value.as(String.self) {
                        Text(label)
                            .font(.system(size: 9))
                            .foregroundStyle(ngText2)
                            .rotationEffect(.degrees(45))
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { val in
                                guard let plotFrame = proxy.plotFrame else { return }
                                let frame = geo[plotFrame]
                                let xPos  = val.location.x - frame.origin.x
                                guard xPos >= 0, xPos <= frame.width else { return }
                                selectedBucket = nearestBucket(in: buckets, at: xPos, width: frame.width)
                                selectedChartX = min(
                                    max(val.location.x, frame.minX + 92),
                                    frame.maxX - 92
                                )
                            }
                            .onEnded { _ in
                                tooltipDismissTask?.cancel()
                                tooltipDismissTask = Task {
                                    try? await Task.sleep(for: .seconds(1.8))
                                    guard !Task.isCancelled else { return }
                                    selectedBucket = nil
                                    selectedChartX = nil
                                }
                            }
                    )
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .frame(minHeight: 300)
    }

    // MARK: – Performance Panel

    private var performancePanel: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Panel header
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Network Performance")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ngText1)
                    Text("Usage summary by direction")
                        .font(.caption)
                        .foregroundStyle(ngText2)
                }
                Spacer()
                // Date range badge (matches reference)
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.caption2)
                    Text(model.selectedRange == .custom
                        ? "\(model.customStartDate.formatted(date: .abbreviated, time: .omitted)) – \(model.customEndDate.formatted(date: .abbreviated, time: .omitted))"
                        : model.selectedRange.rawValue)
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(ngText2)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(ngBg)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            ngSep.frame(height: 1)

            // 3-column grid of mini stat cards
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                spacing: 12
            ) {
                MiniStatCard(
                    label:    model.selectedRange.performanceDownloadLabel,
                    sublabel: "Received in period",
                    value:    model.rangeDownload.byteString,
                    delta:    model.rangeDownloadVsPreviousPercent,
                    color:    ngDownload
                )
                MiniStatCard(
                    label:    model.selectedRange.performanceUploadLabel,
                    sublabel: "Sent in period",
                    value:    model.rangeUpload.byteString,
                    delta:    model.rangeUploadVsPreviousPercent,
                    color:    ngUpload
                )
                MiniStatCard(
                    label:    model.selectedRange.performanceTotalLabel,
                    sublabel: "Transferred in period",
                    value:    model.rangeTotal.byteString,
                    delta:    model.rangeVsPreviousPercent,
                    color:    ngAccent
                )
                MiniStatCard(
                    label:    model.selectedRange.performancePreviousLabel,
                    sublabel: "Prior period total",
                    value:    model.previousTotal.byteString,
                    delta:    0,
                    color:    ngText2
                )
                MiniStatCard(
                    label:    model.selectedRange.heroPeakLabel,
                    sublabel: "Busiest hour/day",
                    value:    model.rangePeak > 0 ? model.rangePeak.byteString : "—",
                    delta:    0,
                    color:    ngAccent
                )
                MiniStatCard(
                    label:    model.selectedRange.heroQuietestLabel,
                    sublabel: "Lowest-traffic hour/day",
                    value:    model.rangeQuietest > 0 ? model.rangeQuietest.byteString : "—",
                    delta:    0,
                    color:    ngDownload
                )
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .ngCard()
    }

    // MARK: – Interface Panel

    private var interfacePanel: some View {
        VStack(alignment: .leading, spacing: 16) {

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Active Interfaces")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ngText1)
                    Text("Real-time device load")
                        .font(.caption)
                        .foregroundStyle(ngText2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ngText2)
                    .padding(7)
                    .background(ngBg)
                    .clipShape(Circle())
            }

            ngSep.frame(height: 1)

            if model.interfaceRates.isEmpty {
                // Empty state
                VStack(spacing: 10) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.title2)
                        .foregroundStyle(ngDownload)
                    Text("No active interfaces")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ngText1)
                    Text("Start browsing or downloading to see active interfaces here.")
                        .font(.caption)
                        .foregroundStyle(ngText2)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)

            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.interfaceRates.prefix(6).enumerated()), id: \.element.id) { idx, rate in
                        InterfaceRateRow(rate: rate)
                        if idx < min(5, model.interfaceRates.count - 1) {
                            ngSep.frame(height: 1)
                        }
                    }
                }

                // Storage location note
                VStack(alignment: .leading, spacing: 3) {
                    Text("Local store")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(ngText2)
                    Text("~/Library/Application Support/NetGaugeMac/netgauge.db")
                        .font(.caption2.monospaced())
                        .foregroundStyle(ngText2.opacity(0.65))
                        .textSelection(.enabled)
                }
                .padding(.top, 12)
            }
        }
        .padding(20)
        .frame(width: 300)
        .ngCard()
    }

    // MARK: – Network Usage Panel

    private var networkUsagePanel: some View {
        VStack(alignment: .leading, spacing: 16) {

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Usage by Network")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ngText1)
                    Text("SSID & connection totals")
                        .font(.caption)
                        .foregroundStyle(ngText2)
                }
                Spacer()
                Image(systemName: "wifi.router")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ngText2)
                    .padding(7)
                    .background(ngBg)
                    .clipShape(Circle())
            }

            ngSep.frame(height: 1)

            if model.networkUsages.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "wifi.slash")
                        .font(.title2)
                        .foregroundStyle(ngAccent)
                    Text("No network data")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ngText1)
                    Text("Connect to a network to start tracking usage.")
                        .font(.caption)
                        .foregroundStyle(ngText2)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.networkUsages.prefix(5).enumerated()), id: \.element.id) { idx, entry in
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                if model.selectedNetwork == entry.networkName {
                                    model.selectedNetwork = nil
                                } else {
                                    model.selectedNetwork = entry.networkName
                                }
                            }
                        }) {
                            NetworkUsageRow(entry: entry, isSelected: model.selectedNetwork == entry.networkName)
                        }
                        .buttonStyle(.plain)
                        if idx < min(4, model.networkUsages.count - 1) {
                            ngSep.frame(height: 1)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 300)
        .ngCard()
    }

    // MARK: – Status Footer

    private var captureFooter: some View {
        HStack {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(ngGreen.opacity(0.32), lineWidth: 5)
                        .frame(width: 16, height: 16)
                        .scaleEffect(livePulse ? 1.9 : 1.0)
                        .opacity(livePulse ? 0 : 0.6)
                        .animation(
                            .easeOut(duration: 1.3).repeatForever(autoreverses: false),
                            value: livePulse
                        )
                    Circle()
                        .fill(ngGreen)
                        .frame(width: 7, height: 7)
                }

                Text("Sampling 1/sec · SQLite Retention Safe")
                    .foregroundStyle(ngText2)

                if let updated = model.lastUpdated {
                    Text("·").foregroundStyle(ngText2)
                    // Use verbatim to prevent SwiftUI treating the formatted date
                    // as a LocalizedStringKey format string on macOS 26+
                    Text(verbatim: "Updated \(updated.formatted(date: .omitted, time: .standard))")
                        .foregroundStyle(ngText2.opacity(0.65))
                }
            }
            .font(.footnote)

            Spacer()

            Toggle("Launch at Login", isOn: $model.isLaunchAtLoginEnabled)
                .font(.footnote)
                .toggleStyle(.checkbox)
                .foregroundStyle(ngText2)
        }
        .padding(.bottom, 4)
    }

    // MARK: – Settings View Tab

    private var settingsContent: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 24) {
                // Header Title
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(ngDownload)
                        Text("Settings & Preferences")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(ngText1)
                    }
                    Text("Configure monitoring preferences, permissions, and data storage.")
                        .font(.subheadline)
                        .foregroundStyle(ngText2)
                }

                // Card 1: General Preferences
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("General Preferences")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(ngText1)
                            Text("App startup behavior and status bar controls")
                                .font(.caption)
                                .foregroundStyle(ngText2)
                        }
                        Spacer()
                    }

                    ngSep.frame(height: 1)

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Launch at Login")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(ngText1)
                            Text("Automatically start NetGauge in the Menu Bar when you log in.")
                                .font(.caption)
                                .foregroundStyle(ngText2)
                        }
                        Spacer()
                        Toggle("", isOn: $model.isLaunchAtLoginEnabled)
                            .toggleStyle(.switch)
                            .tint(ngDownload)
                    }
                }
                .padding(20)
                .ngCard()

                // Card 2: Wi-Fi & Location Permissions
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Wi-Fi SSID Resolution")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(ngText1)
                            Text("Location permission required by macOS CoreWLAN to read Wi-Fi network names")
                                .font(.caption)
                                .foregroundStyle(ngText2)
                        }
                        Spacer()
                    }

                    ngSep.frame(height: 1)

                    HStack(spacing: 12) {
                        let isGranted = LocationHelper.shared.authorizationStatus == .authorized
                        Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(isGranted ? ngGreen : ngAccent)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(isGranted ? "Location Permission Granted" : "Location Permission Required for SSIDs")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(ngText1)
                            Text(isGranted
                                 ? "NetGauge can resolve exact Wi-Fi network names (SSIDs)."
                                 : "Without location access, Wi-Fi traffic is categorized by interface (e.g. Wi-Fi (en0)).")
                                .font(.caption)
                                .foregroundStyle(ngText2)
                        }

                        Spacer()

                        if !isGranted {
                            Button("Request Permission") {
                                LocationHelper.shared.requestPermission()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(ngDownload)
                        }
                    }
                }
                .padding(20)
                .ngCard()

                // Card 3: Storage & Database
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Local Storage & Database")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(ngText1)
                            Text("SQLite database location and retention strategy")
                                .font(.caption)
                                .foregroundStyle(ngText2)
                        }
                        Spacer()
                    }

                    ngSep.frame(height: 1)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Database file location:")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(ngText2)

                        Text(verbatim: "~/Library/Application Support/NetGaugeMac/netgauge.db")
                            .font(.caption.monospaced())
                            .foregroundStyle(ngText1)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(ngBg)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .textSelection(.enabled)
                    }

                    Text("Tiered Data Retention: 1-minute samples (7 days) · 1-hour rollups (30 days) · 1-day rollups (permanent).")
                        .font(.caption2)
                        .foregroundStyle(ngText2)
                }
                .padding(20)
                .ngCard()

                // Card 4: Danger Zone (Reset / Clear All Data)
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.shield.fill")
                                    .foregroundStyle(ngRed)
                                Text("Reset & Clear All Data")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(ngText1)
                            }
                            Text("Permanently delete all recorded bandwidth usage, SSID metrics, and history.")
                                .font(.caption)
                                .foregroundStyle(ngText2)
                        }
                        Spacer()
                    }

                    ngSep.frame(height: 1)

                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Wipe All Network Speed & Usage Data")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(ngText1)
                            Text("This action will erase all stored network history and reset NetGauge to its initial fresh install state.")
                                .font(.caption)
                                .foregroundStyle(ngText2)
                        }

                        Spacer()

                        Button(action: {
                            showClearConfirmation = true
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "trash.fill")
                                Text("Clear All Data...")
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(ngRed)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .shadow(color: ngRed.opacity(0.3), radius: 6, y: 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
                .background(ngRed.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: ngRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: ngRadius, style: .continuous)
                        .strokeBorder(ngRed.opacity(0.25), lineWidth: 1)
                }
            }
            .padding(28)
        }
    }

    // MARK: – Helpers

    private func nearestBucket(in buckets: [UsageBucket], at x: CGFloat, width: CGFloat) -> UsageBucket? {
        guard !buckets.isEmpty, width > 0 else { return nil }
        let progress = min(max(x / width, 0), 0.999)
        let index    = min(Int(progress * CGFloat(buckets.count)), buckets.count - 1)
        return buckets[index]
    }

    /// Returns the numeric part of a byte count formatted for hero cards (e.g. "45.3")
    private func heroValue(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        let mb = Double(bytes) / 1_048_576
        let kb = Double(bytes) / 1_024
        if gb >= 1 { return String(format: "%.1f", gb) }
        if mb >= 1 { return String(format: "%.1f", mb) }
        if kb >= 1 { return String(format: "%.0f", kb) }
        return "\(bytes)"
    }

    /// Returns the unit string for a hero card (e.g. "GB")
    private func heroUnit(_ bytes: UInt64) -> String {
        if bytes >= 1_073_741_824 { return "GB" }
        if bytes >= 1_048_576    { return "MB" }
        if bytes >= 1_024        { return "KB" }
        return "B"
    }
}

// MARK: - App Tab Picker

private struct AppTabPicker: View {
    @Binding var selected: AppTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.allCases, id: \.id) { tab in
                let isSel = selected == tab
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selected = tab
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: tab == .dashboard ? "gauge.with.dots.needle.bottom.50percent" : "gearshape.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text(tab.rawValue)
                            .font(.system(size: 12, weight: isSel ? .semibold : .regular))
                    }
                    .foregroundStyle(isSel ? ngText1 : ngText2)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(isSel ? Color.white : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: isSel ? .black.opacity(0.06) : .clear, radius: 4, y: 2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(ngBg)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

// MARK: - Range Picker

private struct RangePicker: View {
    @Binding var selected: DashboardRange

    var body: some View {
        HStack(spacing: 2) {
            ForEach(DashboardRange.allCases, id: \.id) { range in
                let isSel = selected == range
                Button(action: { selected = range }) {
                    Text(range.shortLabel)
                        .font(.system(size: 12, weight: isSel ? .semibold : .regular))
                        .foregroundStyle(isSel ? ngText1 : ngText2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(isSel ? Color.white : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .shadow(color: isSel ? .black.opacity(0.07) : .clear, radius: 4, y: 2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(ngBg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Chart Mode Picker

private struct ChartModePicker: View {
    @Binding var selected: ChartMode

    var body: some View {
        HStack(spacing: 1) {
            ForEach(ChartMode.allCases) { mode in
                let isSel = selected == mode
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.18)) { selected = mode }
                }) {
                    Text(mode.rawValue)
                        .font(.system(size: 12, weight: isSel ? .semibold : .regular))
                        .foregroundStyle(isSel ? .white : ngText2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(isSel ? ngText1 : .clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(ngBg)
        .clipShape(Capsule())
    }
}

// MARK: - Hero Metric Card

private struct HeroMetric: View {
    let value:      String
    let unit:       String
    let label:      String
    let deltaValue: Int?
    let deltaLabel: String
    var badge:      String? = nil
    var badgeColor: Color   = .clear

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Big number + unit (like 45.3 kWh in reference)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: value)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(ngText1)
                    .monospacedDigit()
                if !unit.isEmpty {
                    Text(verbatim: unit)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ngText2)
                        .padding(.bottom, 2)
                }
            }

            Text(verbatim: label)
                .font(.system(size: 13))
                .foregroundStyle(ngText2)

            // Delta or badge
            if let dv = deltaValue, dv != 0 {
                HStack(spacing: 4) {
                    Image(systemName: dv > 0 ? "arrow.up" : "arrow.down")
                        .font(.system(size: 10, weight: .bold))
                    Text(verbatim: dv > 0 ? "+\(dv)%" : "\(dv)%")
                        .font(.system(size: 12, weight: .semibold))
                    Text(verbatim: deltaLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(ngText2)
                }
                .foregroundStyle(dv > 0 ? ngGreen : ngRed)
            } else if let b = badge {
                Text(verbatim: b)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(badgeColor)
            }
        }
    }
}

// MARK: - Live Rate Tile

private struct RateTile: View {
    let icon:  String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ngText2)
                Text(verbatim: value)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(ngText1)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

// MARK: - Legend Item

private struct LegendItem: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 18, height: 3)
            Text(label)
                .font(.caption)
                .foregroundStyle(ngText2)
        }
    }
}

// MARK: - Chart Tooltip Card

private struct ChartTooltipCard: View {
    let bucket: UsageBucket

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Bucket label as amber pill (matches reference style)
            Text(verbatim: bucket.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(ngAccent)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 5) {
                TooltipRow(label: "Download", value: bucket.received.byteString, color: ngDownload, prefix: "▼")
                TooltipRow(label: "Upload",   value: bucket.sent.byteString,     color: ngUpload,   prefix: "▲")
            }

            ngSep.frame(height: 1)

            HStack {
                Text("Total")
                    .font(.caption2)
                    .foregroundStyle(ngText2)
                Spacer()
                Text(verbatim: bucket.total.byteString)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ngText1)
                    .monospacedDigit()
            }
        }
        .padding(12)
        .frame(width: 184, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(ngSep, lineWidth: 0.5)
        }
    }
}

private struct TooltipRow: View {
    let label:  String
    let value:  String
    let color:  Color
    let prefix: String

    var body: some View {
        HStack {
            HStack(spacing: 5) {
                Text(verbatim: prefix)
                    .foregroundStyle(color)
                Text(verbatim: label)
                    .foregroundStyle(ngText2)
            }
            Spacer()
            Text(verbatim: value)
                .foregroundStyle(ngText1)
                .monospacedDigit()
        }
        .font(.caption2)
    }
}

// MARK: - Mini Stat Card (Performance Panel)

private struct MiniStatCard: View {
    let label:    String
    let sublabel: String
    let value:    String
    let delta:    Int
    let color:    Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(ngText2)
                        .lineLimit(1)
                    Text(verbatim: sublabel)
                        .font(.caption2)
                        .foregroundStyle(ngText2.opacity(0.65))
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ngText2)
                    .padding(5)
                    .background(Color.white)
                    .clipShape(Circle())
            }

            Text(verbatim: value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(ngText1)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // Delta row + sparkline bars
            HStack(alignment: .bottom) {
                if delta != 0 {
                    HStack(spacing: 3) {
                        Image(systemName: delta > 0 ? "arrow.up" : "arrow.down")
                            .font(.system(size: 9, weight: .bold))
                        Text(verbatim: delta > 0 ? "+\(delta)%" : "\(delta)%")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(delta > 0 ? ngGreen : ngRed)
                }
                Spacer()
                SparklineBars(color: color)
            }
        }
        .padding(14)
        .background(ngBg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(ngSep.opacity(0.6), lineWidth: 0.5)
        }
    }
}

// MARK: - Decorative Sparkline Bars

private struct SparklineBars: View {
    let color: Color
    // Simulated distribution shape; purely decorative
    private let heights: [CGFloat] = [3, 5, 7, 4, 9, 6, 8, 11, 7, 10, 13, 9]

    var body: some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(heights.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < heights.count - 4 ? color.opacity(0.35) : color)
                    .frame(width: 3, height: heights[i])
            }
        }
    }
}

// MARK: - Interface Rate Row

private struct InterfaceRateRow: View {
    let rate: InterfaceRate

    private var icon: String {
        if rate.name.hasPrefix("en")     { return "wifi" }
        if rate.name.hasPrefix("utun")   { return "lock.shield" }
        if rate.name.hasPrefix("bridge") { return "point.3.connected.trianglepath.dotted" }
        if rate.name.hasPrefix("awdl")   { return "dot.radiowaves.left.and.right" }
        if rate.name.hasPrefix("llw")    { return "wifi.circle" }
        return "network"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(ngDownload)
                .frame(width: 32, height: 32)
                .background(ngDownload.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: rate.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ngText1)
                    .lineLimit(1)
                Text(verbatim: rate.name)
                    .font(.caption2.monospaced())
                    .foregroundStyle(ngText2)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Label(rate.downloadBytesPerSecond.speedString, systemImage: "arrow.down")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ngDownload)
                Label(rate.uploadBytesPerSecond.speedString, systemImage: "arrow.up")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ngUpload)
            }
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Network Usage Row

private struct NetworkUsageRow: View {
    let entry: NetworkUsageStats
    let isSelected: Bool

    private var icon: String {
        let name = entry.networkName.lowercased()
        if name.contains("wi-fi") || name.contains("wifi") {
            return "wifi"
        } else if name.contains("iphone") || name.contains("hotspot") {
            return "personalhotspot"
        } else if name.contains("ethernet") || name.contains("lan") {
            return "network"
        } else if name.contains("vpn") || name.contains("tunnel") {
            return "lock.shield"
        }
        return "antenna.radiowaves.left.and.right"
    }

    private var iconColor: Color {
        let name = entry.networkName.lowercased()
        if name.contains("wi-fi") || name.contains("wifi") {
            return ngDownload
        } else if name.contains("iphone") || name.contains("hotspot") {
            return ngAccent
        } else if name.contains("ethernet") || name.contains("lan") {
            return ngUpload
        }
        return ngText2
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(isSelected ? .white : iconColor)
                .frame(width: 32, height: 32)
                .background(isSelected ? iconColor : iconColor.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: entry.networkName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? ngAccent : ngText1)
                    .lineLimit(1)
                
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("TODAY")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(ngText2)
                        Text(verbatim: entry.todayTotal.byteString)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(isSelected ? ngText1 : ngDownload)
                    }
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text("MONTH")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(ngText2)
                        Text(verbatim: entry.monthTotal.byteString)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(isSelected ? ngText1 : ngUpload)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: entry.totalBytes.byteString)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(ngText1)
                Text("Total")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(ngText2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(isSelected ? ngBg.opacity(0.7) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Private Extensions

private extension DashboardRange {
    var shortLabel: String {
        switch self {
        case .today:      "1D"
        case .yesterday:  "Yday"
        case .thisMonth:  "1M"
        case .last30Days: "30D"
        case .custom:     "Custom"
        }
    }

    var heroTotalLabel: String {
        switch self {
        case .today:      "Total today"
        case .yesterday:  "Total yesterday"
        case .thisMonth:  "Total this month"
        case .last30Days: "Total last 30 days"
        case .custom:     "Total in range"
        }
    }
    
    var heroTotalDeltaLabel: String {
        switch self {
        case .today:      "vs yesterday"
        case .yesterday:  "vs day before"
        case .thisMonth:  "vs previous month"
        case .last30Days: "vs previous 30 days"
        case .custom:     "vs previous period"
        }
    }
    
    var heroPeakLabel: String {
        switch self {
        case .today, .yesterday: "Peak hour"
        default:                 "Peak period"
        }
    }
    
    var heroPeakDeltaLabel: String {
        switch self {
        case .today, .yesterday: "highest hour"
        default:                 "highest period"
        }
    }
    
    var heroQuietestLabel: String {
        switch self {
        case .today, .yesterday: "Quietest hour"
        default:                 "Quietest period"
        }
    }
    
    var heroQuietestDeltaLabel: String {
        switch self {
        case .today, .yesterday: "lowest hour"
        default:                 "lowest period"
        }
    }

    var rateStripSelectedTitle: String {
        switch self {
        case .today:      "Today Total"
        case .yesterday:  "Yesterday Total"
        case .thisMonth:  "Month Total"
        case .last30Days: "30 Days Total"
        case .custom:     "Selected Total"
        }
    }
    
    var rateStripAlternativeTitle: String {
        switch self {
        case .today, .yesterday: "This Month"
        default:                 "Today Total"
        }
    }

    var performanceDownloadLabel: String {
        switch self {
        case .today:      "Download today"
        case .yesterday:  "Download yesterday"
        default:          "Download selected"
        }
    }
    
    var performanceUploadLabel: String {
        switch self {
        case .today:      "Upload today"
        case .yesterday:  "Upload yesterday"
        default:          "Upload selected"
        }
    }
    
    var performanceTotalLabel: String {
        switch self {
        case .today:      "Total today"
        case .yesterday:  "Total yesterday"
        default:          "Selected Total"
        }
    }
    
    var performancePreviousLabel: String {
        switch self {
        case .today:      "Yesterday"
        case .yesterday:  "Day before"
        case .thisMonth:  "Prev. Month"
        case .last30Days: "Prev. 30 Days"
        case .custom:     "Prev. Period"
        }
    }
}

private extension UInt64 {
    /// Full byte count (e.g. "2.45 GB")
    var byteString: String {
        guard self > 0 else { return "0 B" }
        // Clamp to Int64.max (~9.2 EB) to prevent overflow in ByteCountFormatter
        let safe = self > UInt64(Int64.max) ? Int64.max : Int64(self)
        return ByteCountFormatter.string(fromByteCount: safe, countStyle: .binary)
    }

    /// Compact byte count for chart axis labels (e.g. "2.4 GB")
    var shortByteString: String {
        guard self > 0 else { return "0 B" }
        let safe = self > UInt64(Int64.max) ? Int64.max : Int64(self)
        let fmt = ByteCountFormatter()
        fmt.countStyle   = .binary
        fmt.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        fmt.isAdaptive   = true
        return fmt.string(fromByteCount: safe)
    }
}

extension Double {
    /// Rate formatted as bytes/second (e.g. "1.2 MB/s")
    var speedString: String {
        // Guard against NaN, Infinity, and values that would overflow Int64
        guard self > 0, self.isFinite else { return "0 B/s" }
        let clamped = min(self, Double(Int64.max))
        return ByteCountFormatter.string(fromByteCount: Int64(clamped), countStyle: .binary) + "/s"
    }
}

// MARK: - Window Drag Helper

private extension View {
    /// Attaches a WindowDragGesture on macOS 15+.
    /// On macOS 14, the window can still be dragged from untinted regions;
    /// this is a progressive enhancement only.
    @ViewBuilder
    func windowDragIfAvailable() -> some View {
        if #available(macOS 15.0, *) {
            self.gesture(WindowDragGesture())
        } else {
            self
        }
    }
}
