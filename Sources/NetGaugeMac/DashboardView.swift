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

    var body: some View {
        ZStack(alignment: .top) {
            ngBg.ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Scrollable content ─────────────────────────────────────
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        headlineAndMetrics
                        liveRateStrip
                        chartSection
                        HStack(alignment: .top, spacing: 20) {
                            performancePanel
                            interfacePanel
                        }
                        captureFooter
                    }
                    .padding(28)
                }
                .id(model.selectedRange)   // reset scroll position on range change
            }
        }
        .onAppear { livePulse = true }
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
                    value: heroValue(model.todayTotal),
                    unit:  heroUnit(model.todayTotal),
                    label: "Total today",
                    deltaValue: model.todayVsYesterdayPercent,
                    deltaLabel: "vs yesterday"
                )

                ngSep.frame(width: 1, height: 70).padding(.top, 6)

                HeroMetric(
                    value: heroValue(model.peakHourTotal),
                    unit:  heroUnit(model.peakHourTotal),
                    label: "Peak hour",
                    deltaValue: nil,
                    deltaLabel: "highest hour today",
                    badge: "▲ Peak",
                    badgeColor: ngAccent
                )

                ngSep.frame(width: 1, height: 70).padding(.top, 6)

                HeroMetric(
                    value: model.quietestHourTotal > 0 ? heroValue(model.quietestHourTotal) : "—",
                    unit:  model.quietestHourTotal > 0 ? heroUnit(model.quietestHourTotal)  : "",
                    label: "Quietest hour",
                    deltaValue: nil,
                    deltaLabel: "lowest hour today",
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
                     title: "Today Total",
                     value: model.todayTotal.byteString,
                     color: ngText1)

            ngSep.frame(width: 1).padding(.vertical, 14)

            RateTile(icon: "calendar",
                     title: "This Month",
                     value: model.monthTotal.byteString,
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

                // Mode pills: Both / Download / Upload
                ChartModePicker(selected: $model.chartMode)

                // Legend
                HStack(spacing: 14) {
                    LegendItem(label: "Download", color: ngDownload)
                    LegendItem(label: "Upload",   color: ngUpload)
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
                                // Use Swift concurrency instead of GCD to stay on @MainActor.
                                Task {
                                    try? await Task.sleep(for: .seconds(1.8))
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
                    Text(Date().formatted(date: .abbreviated, time: .omitted))
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
                    label:    "Download today",
                    sublabel: "Today's received data",
                    value:    model.todayDownload.byteString,
                    delta:    model.todayDownloadVsYesterdayPercent,
                    color:    ngDownload
                )
                MiniStatCard(
                    label:    "Upload today",
                    sublabel: "Today's sent data",
                    value:    model.todayUpload.byteString,
                    delta:    model.todayUploadVsYesterdayPercent,
                    color:    ngUpload
                )
                MiniStatCard(
                    label:    "Month total",
                    sublabel: "This calendar month",
                    value:    model.monthTotal.byteString,
                    delta:    0,
                    color:    ngAccent
                )
                MiniStatCard(
                    label:    "Yesterday",
                    sublabel: "Prior day total",
                    value:    model.yesterdayTotal.byteString,
                    delta:    0,
                    color:    ngText2
                )
                MiniStatCard(
                    label:    "Peak hour",
                    sublabel: "Busiest hour today",
                    value:    model.peakHourTotal > 0 ? model.peakHourTotal.byteString : "—",
                    delta:    0,
                    color:    ngAccent
                )
                MiniStatCard(
                    label:    "Quietest hour",
                    sublabel: "Lowest-traffic hour",
                    value:    model.quietestHourTotal > 0 ? model.quietestHourTotal.byteString : "—",
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
                    Text("Updated \(updated.formatted(date: .omitted, time: .standard))")
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

// MARK: - NavBar

private struct NavBar: View {
    private let navItems = ["Dashboard", "Analytics", "Interfaces", "About"]
    @State private var selected = "Dashboard"

    var body: some View {
        HStack(spacing: 0) {
            // Logo — uses the generated app icon PNG bundled with the app.
            HStack(spacing: 10) {
                // Swift Package Manager doesn't use asset catalogs; load by filename.
                Group {
                    if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
                       let nsImg = NSImage(contentsOf: url) {
                        Image(nsImage: nsImg)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                            .frame(width: 34, height: 34)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    } else {
                        // Fallback if PNG isn't bundled yet.
                        ZStack {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(ngDownload)
                                .frame(width: 34, height: 34)
                            Image(systemName: "wifi")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                    .accessibilityLabel("NetGauge app icon")
                Text("NetGauge")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(ngText1)
            }
            .padding(.leading, 28)

            Spacer()

            // Navigation tabs
            HStack(spacing: 1) {
                ForEach(navItems, id: \.self) { item in
                    let isSel = item == selected
                    Button(action: { selected = item }) {
                        Text(item)
                            .font(.system(size: 13, weight: isSel ? .semibold : .regular))
                            .foregroundStyle(isSel ? .white : ngText2)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(isSel ? ngText1 : .clear)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(ngBg)
            .clipShape(Capsule())

            Spacer()

            // Right controls — each icon button gets an accessibility label
            // so VoiceOver users understand its purpose (Apple HIG requirement).
            HStack(spacing: 10) {
                Button(action: {}) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(ngText2)
                        .frame(width: 34, height: 34)
                        .background(ngBg)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Search")

                Button(action: {}) {
                    Image(systemName: "bell")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(ngText2)
                        .frame(width: 34, height: 34)
                        .background(ngBg)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Notifications")

                // Avatar badge
                ZStack {
                    Circle()
                        .fill(ngDownload.opacity(0.18))
                        .frame(width: 34, height: 34)
                    Text("NG")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(ngDownload)
                }
                .accessibilityLabel("NetGauge user profile")
            }
            .padding(.trailing, 28)
        }
        .frame(height: 58)
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
                Text(value)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(ngText1)
                    .monospacedDigit()
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ngText2)
                        .padding(.bottom, 2)
                }
            }

            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(ngText2)

            // Delta or badge
            if let dv = deltaValue, dv != 0 {
                HStack(spacing: 4) {
                    Image(systemName: dv > 0 ? "arrow.up" : "arrow.down")
                        .font(.system(size: 10, weight: .bold))
                    Text(dv > 0 ? "+\(dv)%" : "\(dv)%")
                        .font(.system(size: 12, weight: .semibold))
                    Text(deltaLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(ngText2)
                }
                .foregroundStyle(dv > 0 ? ngGreen : ngRed)
            } else if let b = badge {
                Text(b)
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
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ngText2)
                Text(value)
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
            Text(bucket.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(ngAccent)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 5) {
                TooltipRow(label: "Download", value: bucket.received.byteString, color: ngDownload, prefix: "▲")
                TooltipRow(label: "Upload",   value: bucket.sent.byteString,     color: ngUpload,   prefix: "▼")
            }

            ngSep.frame(height: 1)

            HStack {
                Text("Total")
                    .font(.caption2)
                    .foregroundStyle(ngText2)
                Spacer()
                Text(bucket.total.byteString)
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
                Text(prefix)
                    .foregroundStyle(color)
                Text(label)
                    .foregroundStyle(ngText2)
            }
            Spacer()
            Text(value)
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
                    Text(label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(ngText2)
                        .lineLimit(1)
                    Text(sublabel)
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

            Text(value)
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
                        Text(delta > 0 ? "+\(delta)%" : "\(delta)%")
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
                Text(rate.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ngText1)
                    .lineLimit(1)
                Text(rate.name)
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
}

private extension UInt64 {
    /// Full byte count (e.g. "2.45 GB")
    var byteString: String {
        guard self > 0 else { return "0 B" }
        return ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .binary)
    }

    /// Compact byte count for chart axis labels (e.g. "2.4 GB")
    var shortByteString: String {
        guard self > 0 else { return "0 KB" }
        let fmt = ByteCountFormatter()
        fmt.countStyle   = .binary
        fmt.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        fmt.isAdaptive   = true
        return fmt.string(fromByteCount: Int64(self))
    }
}

extension Double {
    /// Rate formatted as bytes/second (e.g. "1.2 MB/s")
    var speedString: String {
        guard self > 0 else { return "0 B/s" }
        return "\(ByteCountFormatter.string(fromByteCount: Int64(max(self, 0)), countStyle: .binary))/s"
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
