import SwiftUI
import Charts

/// Shared bill presentation for the menu-bar popover and Settings usage page.
struct BillPopoverView: View {
    var topInset: CGFloat = 0
    /// Embedded in Settings the page sits on the window background instead
    /// of painting the panel's own near-black.
    var embedded = false
    @AppStorage("CapacityDockBillAppearance") private var appearance = "dark"
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var period: TokenConsumptionPeriod = .today
    @State private var showProviders = false
    @State private var snapshot: TokenConsumptionSnapshot?
    @State private var isLoading = true
    @State private var loadID = UUID()
    @State private var currency = DisplayCurrency.usd
    @State private var selectedDay: Date?
    @State private var activityData: TokenConsumptionSnapshot?

    private var scheme: ColorScheme { appearance == "dark" ? .dark : appearance == "light" ? .light : systemScheme }
    private var palette: CapacityDockInterfacePalette.Tokens { CapacityDockInterfacePalette.tokens(scheme, onWindow: embedded) }
    private var accent: Color { palette.accent }
    @State private var chartMode = "trend"

    var body: some View {
        VStack(spacing: 0) {
            // One scrolling page: the summary and chart scroll away and the
            // Models / Providers switch pins to the top, so the list gets the
            // whole panel height instead of a fixed strip at the bottom.
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    overview
                        .padding(.horizontal, 16).padding(.top, 16 + topInset).padding(.bottom, 12)
                        .overlay(alignment: .bottomLeading) {
                            if let selectedDay, chartMode != "composition",
                               let detailSnapshot = activityData {
                                dayTooltip(selectedDay, snapshot: detailSnapshot)
                                    .padding(.horizontal, 16).offset(y: 100).allowsHitTesting(false)
                            }
                        }
                        .zIndex(1)
                    Section {
                        detailList.padding(.horizontal, 16).padding(.bottom, 16)
                    } header: {
                        listHeader
                    }
                }
            }
            .scrollIndicators(.automatic)

            footer
                .padding(.horizontal, 16).padding(.vertical, 10)
                .overlay(alignment: .top) { Rectangle().fill(palette.separator).frame(height: 0.5) }
        }
        .background(embedded ? Color.clear : palette.background)
        .foregroundStyle(.primary)
        .tint(accent)
        .environment(\.colorScheme, scheme)
        .preferredColorScheme(appearance == "system" ? nil : scheme)
        .task { currency = DisplayCurrencyState.shared.snapshot }
        .task(id: period) { await load() }
        .task(id: chartMode != "composition") {
            if chartMode != "composition" {
                let history = await MenubarBillStore.shared.historicalActivity()
                if !Task.isCancelled { activityData = history }
            }
        }
        .onChange(of: chartMode) { _, _ in selectedDay = nil }
        .onChange(of: period) { _, _ in
            selectedDay = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .capacityDockCurrencyDidChange)) { _ in
            currency = DisplayCurrencyState.shared.snapshot
        }
        .onReceive(NotificationCenter.default.publisher(for: .capacityDockMenubarBillDidChange)) { _ in
            if period == .today, !isLoading { snapshot = MenubarBillStore.shared.snapshot }
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            APIBalanceSummary()
            BillSegmentedControl(selection: $period,
                items: TokenConsumptionPeriod.allCases.map { BillSegment(id: $0, title: LocalizedStringKey($0.title)) },
                palette: palette, fillsWidth: true)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Period")
            if let snapshot {
                summary(snapshot)
                chartCard(snapshot)
            } else {
                VStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(MenubarBillStore.shared.scanProgress[period] ?? NSLocalizedString("Reading local logs…", comment: ""))
                        .font(.system(size: 12, weight: .medium))
                    Text("Historical logs are cached after the first read.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 250)
                .background(palette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    /// Pinned while scrolling; painted with the page background so rows pass
    /// cleanly underneath it.
    private var listHeader: some View {
        HStack(spacing: 8) {
            BillSegmentedControl(selection: $showProviders, items: [
                BillSegment(id: false, title: "Models"),
                BillSegment(id: true, title: "Providers")
            ], palette: palette, compact: true)
            Spacer()
            Text("Cost").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                .padding(.trailing, 34)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(embedded ? Color(nsColor: .windowBackgroundColor) : palette.background)
    }

    @ViewBuilder
    private var detailList: some View {
        if let snapshot {
            let rows = detailRows(snapshot)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Rectangle().fill(palette.separator).frame(height: 0.5).padding(.leading, 56)
                    }
                    BillDetailRow(item: row, currency: currency, palette: palette)
                }
                if snapshot.allLogsMissing {
                    emptyState("No token log", detail: "Use an AI coding tool on this Mac, then reload local logs.")
                } else if !showProviders && snapshot.modelRows(matching: nil).isEmpty {
                    emptyState("No usage in this period", detail: "Switch the period or view provider status.")
                }
            }
            .padding(6)
            .background(palette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func detailRows(_ snapshot: TokenConsumptionSnapshot) -> [BillDetailItem] {
        if showProviders {
            return snapshot.ledgerRows.map { row in
                BillDetailItem(id: "provider:" + row.id, name: row.displayName, providerID: row.providerID,
                               totals: row.totals, calls: row.loggedEventCount,
                               amount: row.pricedEventCount > 0 ? row.estimatedUSD : nil,
                               unpriced: row.unpricedEventCount, status: row.availability)
            }
        }
        return BillPopoverPresentation.models(snapshot, providerID: nil).map { item in
            BillDetailItem(id: "model:" + item.id, name: item.model.shortName, providerID: item.providerID,
                           totals: item.model.totals,
                           calls: item.model.pricedEventCount + item.model.unpricedEventCount,
                           amount: item.model.pricedEventCount > 0 ? item.model.estimatedUSD : nil,
                           unpriced: item.model.unpricedEventCount, status: .logged)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            BillAppGlyph(active: isLoading, accent: accent, reduceMotion: reduceMotion)
                .frame(width: 30, height: 30).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Usage overview").font(.system(size: 15, weight: .semibold)).accessibilityAddTraits(.isHeader)
                Text("Local logs · API-equivalent estimate").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            BillIconButton(palette: palette) {
                Task { await load(force: true) }
            } label: {
                if isLoading { ProgressView().controlSize(.mini) }
                else { Image(systemName: "arrow.clockwise") }
            }
            .disabled(isLoading)
            .help("Reload local logs").accessibilityLabel("Reload local logs")
            Menu {
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(palette.control, in: Circle())
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("Appearance")
        }
    }

    private func summary(_ snapshot: TokenConsumptionSnapshot) -> some View {
        let totals = snapshot.totals(matching: nil)
        let amount = totals.pricedEventCount > 0 ? totals.estimatedUSD : nil
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(TokenConsumptionPresentation.windowLabel(snapshot))
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    Text(amount.map { currency.grouped($0) } ?? "—")
                        .font(.system(size: 32, weight: .semibold, design: .rounded)).monospacedDigit()
                        .contentTransition(reduceMotion ? .identity : .numericText(value: currency.convert(amount ?? 0)))
                        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85), value: amount)
                        .id("\(period.rawValue)-\(snapshot.window.start)-all-\(currency.code)-\(currency.rate)")
                        .lineLimit(1).minimumScaleFactor(0.65).fixedSize(horizontal: false, vertical: true).layoutPriority(1)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(TokenConsumptionPresentation.callsText(totals.loggedEventCount))
                        .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                    if totals.unpricedEventCount > 0 {
                        Label("Some calls unpriced", systemImage: "info.circle")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                            .help("Unpriced calls are included in token counts but excluded from the estimate.")
                    }
                }
            }
            HStack(spacing: 0) {
                metric("Tokens", value: BillPopoverPresentation.compact(totals.tokenCount))
                metricDivider
                metric("Input", value: BillPopoverPresentation.compact(totals.input))
                metricDivider
                metric("Output", value: BillPopoverPresentation.compact(totals.output))
                metricDivider
                metric("Cache", value: BillPopoverPresentation.compact(totals.cacheRead + totals.cacheWrite))
            }
        }
        .padding(14)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var metricDivider: some View {
        Rectangle().fill(palette.separator).frame(width: 0.5, height: 26).padding(.horizontal, 10)
    }

    private func metric(_ title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chartCard(_ snapshot: TokenConsumptionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                BillSegmentedControl(selection: $chartMode, items: [
                    BillSegment(id: "composition", title: "Composition"),
                    BillSegment(id: "trend", title: "Trend"),
                    BillSegment(id: "activity", title: "Activity")
                ], palette: palette, compact: true)
                Spacer()
                Text(chartMode == "activity" ? NSLocalizedString("Last 81 days", comment: "") : chartMode == "trend" ? NSLocalizedString("Last 30 days", comment: "") : period.title)
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            }
            Group {
                if chartMode != "composition" {
                    if let activityData {
                        if chartMode == "activity" { activity(activityData) }
                        else { chart(BillPopoverPresentation.trendHistory(activityData)) }
                    } else {
                        VStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(MenubarBillStore.shared.activityProgress).font(.system(size: 10)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity)
                    }
                } else { chart(snapshot) }
            }
            .frame(height: 106, alignment: .top)
        }
        .padding(12)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder private func chart(_ snapshot: TokenConsumptionSnapshot) -> some View {
        if chartMode == "trend" {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Daily tokens").font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Text(dayReadout(snapshot)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).monospacedDigit()
                }
                Chart(BillPopoverPresentation.days(snapshot)) { day in
                    if let tokens = day.tokens {
                        let isToday = day.date == Calendar.current.startOfDay(for: snapshot.window.now)
                        let isSelected = selectedDay.map { Calendar.current.isDate($0, inSameDayAs: day.date) } ?? false
                        BarMark(x: .value("Date", day.date, unit: .day), y: .value("Tokens", tokens))
                            .foregroundStyle(accent.opacity(isToday || isSelected ? 1 : 0.55))
                            .cornerRadius(2.5)
                            .accessibilityLabel(day.label)
                            .accessibilityValue(TokenConsumptionFormatting.tokens(tokens))
                    }
                }
                .chartXScale(domain: snapshot.window.start...snapshot.window.end)
                .chartXSelection(value: $selectedDay)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Color.clear.contentShape(Rectangle()).onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                if let frame = proxy.plotFrame {
                                    selectedDay = proxy.value(atX: location.x - geometry[frame].origin.x)
                                }
                            case .ended: selectedDay = nil
                            }
                        }
                    }
                }
                .chartXAxis { AxisMarks(values: .stride(by: .day, count: 5)) { _ in
                    AxisValueLabel(format: .dateTime.month(.defaultDigits).day(), centered: true)
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                } }
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(palette.separator)
                    AxisValueLabel { if let number = value.as(Int.self) { Text(BillPopoverPresentation.compact(number)).font(.system(size: 9)).foregroundStyle(.secondary) } }
                } }
            }
        } else {
            let totals = snapshot.totals(matching: nil)
            let parts = BillPopoverPresentation.composition(totals)
            let total = max(parts.reduce(0) { $0 + $1.value }, 1)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Token composition").font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Text("Including cached tokens").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                // One stacked capsule reads as a share of the whole, like the
                // storage bar in System Settings.
                GeometryReader { geometry in
                    HStack(spacing: 2) {
                        ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                            if part.value > 0 {
                                Rectangle()
                                    .fill(accent.opacity([1.0, 0.62, 0.30][index]))
                                    .frame(width: max(3, (geometry.size.width - 4) * CGFloat(part.value) / CGFloat(total)))
                            }
                        }
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 10)
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Circle().fill(accent.opacity([1.0, 0.62, 0.30][index])).frame(width: 7, height: 7)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(part.title).font(.system(size: 10)).foregroundStyle(.secondary)
                                Text(BillPopoverPresentation.compact(part.value))
                                    .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                                Text("\(Int((Double(part.value) / Double(total) * 100).rounded()))%")
                                    .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func activity(_ snapshot: TokenConsumptionSnapshot) -> some View {
        let days = BillPopoverPresentation.days(snapshot)
        let peak = max(days.compactMap(\.tokens).max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Daily activity").font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("Gaps mean no records").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 6), spacing: 3), count: 27), alignment: .leading, spacing: 3) {
                ForEach(days) { day in
                    activityCell(day, peak: peak)
                }
            }.frame(maxWidth: 375).frame(maxWidth: .infinity)
            HStack(spacing: 4) {
                Text(days.first?.label ?? "")
                Spacer()
                Text("Less")
                ForEach(0..<4) { level in
                    RoundedRectangle(cornerRadius: 2).fill(accent.opacity(0.18 + Double(level) * 0.27)).frame(width: 8, height: 8)
                }
                Text("More")
                Spacer()
                Text(days.last?.label ?? "")
            }.font(.system(size: 9)).monospacedDigit().foregroundStyle(.secondary)
            // Three squares cannot fill the chart height the other tabs use,
            // so the space carries a summary instead of sitting empty.
            let stats = BillPopoverPresentation.activityStats(days)
            HStack(spacing: 0) {
                activityStat("Active days", value: "\(stats.activeDays)/\(stats.totalDays)")
                activityStat("Longest streak", value: String(format: NSLocalizedString("%d days", comment: ""), stats.longestStreak))
                activityStat("Peak day", value: stats.peak > 0 ? BillPopoverPresentation.compact(stats.peak) : "—")
            }
        }
    }

    private func activityStat(_ title: LocalizedStringKey, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func activityCell(_ day: BillPopoverPresentation.Day, peak: Int) -> some View {
        // Rare UI GitHubActivity: square cells, 3px gaps, four discrete color levels.
        let level = day.tokens.map { $0 <= 0 ? 0 : min(4, max(1, Int(ceil(Double($0) / Double(peak) * 4)))) } ?? 0
        let intensity = [0.08, 0.30, 0.52, 0.76, 1.0][level]
        let color = day.tokens == nil ? Color.secondary.opacity(0.08) : accent.opacity(intensity)
        let value = day.tokens.map { TokenConsumptionFormatting.tokens($0) } ?? NSLocalizedString("No records", comment: "")
        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(color)
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(day.tokens == nil ? 0.25 : 0), style: StrokeStyle(lineWidth: 1, dash: [2]))
            }
            .aspectRatio(1, contentMode: .fit)
            .onHover { hovered in selectedDay = hovered ? day.date : nil }
            .accessibilityLabel(day.label)
            .accessibilityValue(value)
    }

    private func dayTooltip(_ date: Date, snapshot: TokenConsumptionSnapshot) -> some View {
        let key = TokenConsumptionClock.dayKey(date)
        let day = snapshot.daily.first { $0.day == key }
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(key).fontWeight(.semibold).monospacedDigit()
                Spacer()
                Text(day.map { BillPopoverPresentation.compact($0.tokenCount) + " tokens" }
                     ?? NSLocalizedString("No records", comment: ""))
                    .foregroundStyle(accent)
            }
            if let day {
                ForEach(day.models.prefix(8)) { model in
                    HStack(spacing: 6) {
                        Text(model.model).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 4)
                        Text(model.estimatedUSD.map { currency.grouped($0) } ?? "—")
                        Text(BillPopoverPresentation.compact(model.tokens)).foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .trailing)
                    }.font(.system(size: 10)).monospacedDigit()
                }
                if day.models.count > 8 {
                    Text(String(format: NSLocalizedString("%d more models", comment: ""), day.models.count - 8))
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
        }
        .font(.system(size: 11))
        .padding(12)
        .background(palette.elevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(palette.separator))
        .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
    }

    private func dayReadout(_ snapshot: TokenConsumptionSnapshot) -> String {
        guard let selectedDay else { return NSLocalizedString("Gaps mean no records", comment: "") }
        let key = TokenConsumptionClock.dayKey(selectedDay)
        let value = snapshot.daily.first { $0.day == key }
        return String(key.suffix(5)) + " · " + (value.map { TokenConsumptionFormatting.tokens($0.tokenCount) } ?? NSLocalizedString("No records", comment: ""))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Menu {
                    ForEach(SupportedCurrency.allCases) { item in
                        Button { DisplayCurrencyState.shared.select(item.rawValue) } label: {
                            if item.rawValue == currency.code { Label("\(item.displayName) (\(item.rawValue))", systemImage: "checkmark") }
                            else { Text("\(item.displayName) (\(item.rawValue))") }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(currency.code).font(.system(size: 11, weight: .semibold))
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold))
                    }
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(palette.control, in: Capsule())
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().accessibilityLabel("Currency")
                if DisplayCurrencyState.shared.isUpdating { ProgressView().controlSize(.mini) }
                Spacer()
                Label("Estimate ≠ subscription bill", systemImage: "info.circle")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .help("API-equivalent estimate, not a subscription charge.")
            }
            if let error = DisplayCurrencyState.shared.errorMessage {
                Text(error).font(.system(size: 10)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func emptyState(_ title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis").font(.system(size: 24)).foregroundStyle(.secondary)
            Text(title).font(.system(size: 12, weight: .semibold))
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 28)
    }

    private func load(force: Bool = false) async {
        let request = UUID()
        loadID = request
        let chosen = period
        if snapshot?.period != chosen { snapshot = nil }
        if !force, chosen == .today, let cached = MenubarBillStore.shared.snapshot, cached.window.contains(Date()) { snapshot = cached }
        isLoading = true
        defer { if loadID == request { isLoading = false } }
        let result = await MenubarBillStore.shared.snapshot(for: chosen, force: force)
        guard !Task.isCancelled, loadID == request, period == chosen else { return }
        snapshot = result
        if force, chartMode != "composition" {
            let history = await MenubarBillStore.shared.historicalActivity(force: true)
            if !Task.isCancelled { activityData = history }
        }
    }
}

private struct BillDetailItem: Identifiable {
    let id: String
    let name: String
    let providerID: String
    let totals: TokenUsageTotals
    let calls: Int
    let amount: Double?
    let unpriced: Int
    let status: TokenLogAvailability
}

private struct BillDetailRow: View {
    let item: BillDetailItem
    let currency: DisplayCurrency
    let palette: CapacityDockInterfacePalette.Tokens
    @State private var expanded = false
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 10) {
                    BillProviderTile(providerID: item.providerID, palette: palette)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1).truncationMode(.middle).help(item.name)
                        Text(subtitle).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1).monospacedDigit()
                    }
                    Spacer(minLength: 5)
                    Text(item.amount.map { currency.grouped($0) } ?? "—")
                        .font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .padding(.horizontal, 8).padding(.vertical, 8).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityValue(expanded ? "Expanded" : "Collapsed")
            if expanded {
                VStack(alignment: .leading, spacing: 5) {
                    if item.status == .logged {
                        detail("Input", item.totals.input)
                        detail("Output", item.totals.displayOutput)
                        detail("Cache", item.totals.cacheRead)
                        detail("Cache write", item.totals.cacheWrite)
                        detail("Reasoning", item.totals.reasoning)
                        if item.unpriced > 0 { Text("Some calls unpriced").foregroundStyle(.secondary) }
                    } else {
                        Text(item.status == .unreadable ? "Could not read this provider’s local log. Check folder permissions, then press Reload local logs." : "The quota ring can show percent remaining, but this Mac has no token log for this provider.")
                            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .font(.system(size: 10.5))
                .padding(.leading, 50).padding(.trailing, 12).padding(.bottom, 10)
                .transition(.opacity)
            }
        }
        .background(palette.control.opacity(expanded ? 1 : hovered ? 0.7 : 0), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.86), value: expanded)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
    }

    private var subtitle: String {
        switch item.status {
        case .logged:
            if item.calls == 0 { return NSLocalizedString("No usage in this period", comment: "") }
            return "\(BillPopoverPresentation.compact(item.totals.tokenCount)) tokens · \(TokenConsumptionPresentation.callsText(item.calls))"
        case .unreadable: return NSLocalizedString("Unread", comment: "")
        case .cursorHashOnly, .noLocalTokenLog: return NSLocalizedString("No token log", comment: "")
        }
    }

    private func detail(_ title: LocalizedStringKey, _ value: Int) -> some View {
        HStack { Text(title).foregroundStyle(.secondary); Spacer(); Text(TokenConsumptionFormatting.tokens(value)).monospacedDigit() }
    }
}

/// Provider logo on a small rounded tile, like app icons in System Settings lists.
private struct BillProviderTile: View {
    let providerID: String
    let palette: CapacityDockInterfacePalette.Tokens

    var body: some View {
        let name = CapacityDockProvider(rawValue: providerID)?.iconName ?? (providerID == "cursor-agent" ? "cursor" : providerID)
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(palette.control)
            if let image = ProviderIconCache.image(named: name) {
                Image(nsImage: image).resizable().scaledToFit().frame(width: 16, height: 16)
            } else {
                Image(systemName: "cpu").font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 30, height: 30)
        .accessibilityHidden(true)
    }
}

/// Pure display projections: never reprices or invents missing daily records.
enum BillPopoverPresentation {
    struct Model: Identifiable {
        let providerID: String
        let model: TokenConsumptionModelRow
        var id: String { providerID + ":" + model.model }
    }
    struct Day: Identifiable {
        let date: Date
        let tokens: Int?
        let label: String
        var id: Date { date }
    }
    struct Part { let title: LocalizedStringKey; let value: Int }
    struct ActivityStats: Equatable {
        var activeDays: Int
        var totalDays: Int
        var longestStreak: Int
        var peak: Int
    }

    /// Active = any tokens that day; a day with no records or zero tokens
    /// breaks the streak.
    static func activityStats(_ days: [Day]) -> ActivityStats {
        var streak = 0
        var longest = 0
        for day in days {
            if (day.tokens ?? 0) > 0 {
                streak += 1
                longest = max(longest, streak)
            } else {
                streak = 0
            }
        }
        return ActivityStats(
            activeDays: days.filter { ($0.tokens ?? 0) > 0 }.count,
            totalDays: days.count,
            longestStreak: longest,
            peak: days.compactMap(\.tokens).max() ?? 0
        )
    }

    static func compact(_ value: Int) -> String {
        value.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
    }

    static func models(_ snapshot: TokenConsumptionSnapshot, providerID: String?) -> [Model] {
        snapshot.rows.filter { $0.availability == .logged && (providerID == nil || providerID == $0.providerID) }
            .flatMap { row in row.models.map { Model(providerID: row.providerID, model: $0) } }
            .sorted {
                if $0.model.estimatedUSD != $1.model.estimatedUSD { return ($0.model.estimatedUSD ?? -1) > ($1.model.estimatedUSD ?? -1) }
                return $0.id < $1.id
            }
    }

    static func composition(_ totals: TokenConsumptionPeriodTotals) -> [Part] {
        // Aggregated output already includes reasoning; adding it again overstates usage.
        [Part(title: "Input", value: totals.input), Part(title: "Output", value: totals.output),
         Part(title: "Cache", value: totals.cacheRead + totals.cacheWrite)]
    }

    static func trendHistory(_ snapshot: TokenConsumptionSnapshot, calendar: Calendar = .current) -> TokenConsumptionSnapshot {
        var result = snapshot
        let today = calendar.startOfDay(for: snapshot.window.now)
        let start = calendar.date(byAdding: .day, value: -29, to: today) ?? today
        result.window = TokenConsumptionWindow(start: start, end: snapshot.window.end, now: snapshot.window.now)
        let firstDay = TokenConsumptionClock.dayKey(start, timeZone: calendar.timeZone)
        result.daily = snapshot.daily.filter { $0.day >= firstDay }
        return result
    }

    static func days(_ snapshot: TokenConsumptionSnapshot, calendar: Calendar = .current) -> [Day] {
        let recorded = Dictionary(snapshot.daily.map { ($0.day, $0.tokenCount) }, uniquingKeysWith: +)
        var date = calendar.startOfDay(for: snapshot.window.start)
        var result: [Day] = []
        while date <= snapshot.window.now {
            let key = TokenConsumptionClock.dayKey(date, timeZone: calendar.timeZone)
            result.append(Day(date: date, tokens: recorded[key], label: key))
            guard let next = calendar.date(byAdding: .day, value: 1, to: date), next > date else { break }
            date = next
        }
        return result
    }
}

/// App glyph for the panel header; its highlight drifts only while a scan runs.
private struct BillAppGlyph: View {
    let active: Bool
    let accent: Color
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15, paused: !active || reduceMotion)) { context in
            let phase = active && !reduceMotion ? context.date.timeIntervalSinceReferenceDate * 1.6 : 0
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(accent.gradient)
                .overlay {
                    Circle().fill(.white.opacity(active ? 0.45 : 0)).frame(width: 14, height: 14)
                        .blur(radius: 5)
                        .offset(x: sin(phase) * 6, y: cos(phase * 0.8) * 5)
                }
                .overlay {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

private struct BillIconButton<Label: View>: View {
    let palette: CapacityDockInterfacePalette.Tokens
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            label()
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(palette.control.opacity(hovered ? 1.6 : 1), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

/// Shared interaction for period and chart selection; no timers or idle animation.
private struct BillSegment<Selection: Hashable>: Identifiable {
    let id: Selection
    let title: LocalizedStringKey
}

/// Native-style segmented control: a neutral raised thumb slides over a
/// recessed track; colour is reserved for data.
private struct BillSegmentedControl<Selection: Hashable>: View {
    @Binding var selection: Selection
    let items: [BillSegment<Selection>]
    let palette: CapacityDockInterfacePalette.Tokens
    var fillsWidth = false
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered: Selection?
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                let selected = selection == item.id
                Button { selection = item.id } label: {
                    Text(item.title)
                        .font(.system(size: compact ? 11 : 12, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                        .padding(.horizontal, compact ? 10 : 12)
                        .frame(maxWidth: fillsWidth ? .infinity : nil)
                        .frame(height: compact ? 22 : 26)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: compact ? 6 : 7, style: .continuous)
                                    .fill(palette.thumb)
                                    .shadow(color: .black.opacity(0.18), radius: 1.5, y: 0.5)
                                    .matchedGeometryEffect(id: "selection", in: indicator)
                            } else if hovered == item.id {
                                RoundedRectangle(cornerRadius: compact ? 6 : 7, style: .continuous)
                                    .fill(palette.control)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
                .onHover { hovered = $0 ? item.id : nil }
            }
        }
        .padding(2)
        .background(palette.track, in: RoundedRectangle(cornerRadius: compact ? 8 : 9, style: .continuous))
        .fixedSize(horizontal: !fillsWidth, vertical: true)
        .animation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.85), value: selection)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
    }
}

/// Interface colours for the menu-bar panel and Settings. Dark sits on the
/// same near-black as the edge dock; light uses the system grouped greys.
/// Colour is the macOS accent so the app follows the user's system choice.
enum CapacityDockInterfacePalette {
    struct Tokens {
        let background: Color
        let card: Color
        let elevated: Color
        let control: Color
        let track: Color
        let thumb: Color
        let separator: Color
        let accent: Color
    }

    /// `onWindow` is for pages inside the Settings window, whose background
    /// is lighter than the panel's near-black; cards there lift by overlay.
    static func tokens(_ scheme: ColorScheme, onWindow: Bool = false) -> Tokens {
        if scheme == .dark {
            return Tokens(
                background: Color(white: 0.035),
                card: onWindow ? Color.white.opacity(0.055) : Color(white: 0.105),
                elevated: Color(white: onWindow ? 0.22 : 0.15),
                control: Color.white.opacity(0.07),
                track: Color.white.opacity(0.06),
                thumb: Color(white: 0.30),
                separator: Color.white.opacity(0.09),
                accent: accent(scheme)
            )
        }
        return Tokens(
            background: Color(red: 0.949, green: 0.949, blue: 0.969),
            card: .white,
            elevated: .white,
            control: Color.black.opacity(0.05),
            track: Color.black.opacity(0.06),
            thumb: .white,
            separator: Color.black.opacity(0.09),
            accent: accent(scheme)
        )
    }

    static func accent(_ scheme: ColorScheme) -> Color {
        Color(nsColor: .controlAccentColor)
    }
    static func surface(_ scheme: ColorScheme) -> Color {
        tokens(scheme).background
    }
}
