import SwiftUI
import Charts

/// Shared bill presentation for the menu-bar popover and Settings usage page.
struct BillPopoverView: View {
    var topInset: CGFloat = 0
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
    private var accent: Color { CapacityDockInterfacePalette.accent(scheme) }
    private var surface: Color { CapacityDockInterfacePalette.surface(scheme) }
    @State private var chartMode = "trend"
    @Namespace private var detailSelection

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                header
                APIBalanceSummary()
                BillSegmentedControl(selection: $period,
                    items: TokenConsumptionPeriod.allCases.map { BillSegment(id: $0, title: LocalizedStringKey($0.title)) },
                    itemWidth: 62, accent: accent)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Period")
                if let snapshot {
                    summary(snapshot)
                    chartModePicker
                    if chartMode != "composition" {
                        if let activityData {
                            if chartMode == "activity" { activity(activityData) }
                            else { chart(BillPopoverPresentation.trendHistory(activityData)) }
                        }
                        else {
                            VStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text(MenubarBillStore.shared.activityProgress).font(.system(size: 10)).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity).frame(height: 105)
                        }
                    } else { chart(snapshot) }
                } else {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text(MenubarBillStore.shared.scanProgress[period] ?? NSLocalizedString("Reading local logs…", comment: ""))
                            .font(.system(size: 12))
                        Text("Historical logs are cached after the first read.")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, minHeight: 214)
                }
            }.padding(16).padding(.top, topInset)
            .overlay(alignment: .bottomLeading) {
                if let selectedDay, chartMode != "composition",
                   let detailSnapshot = activityData {
                    dayTooltip(selectedDay, snapshot: detailSnapshot)
                        .padding(.horizontal, 16).offset(y: 100).allowsHitTesting(false)
                }
            }.zIndex(1)
            Divider()
            HStack(spacing: 18) {
                tab("Models", providers: false)
                tab("Providers", providers: true)
                Spacer()
                Text("Cost").foregroundStyle(.secondary).font(.system(size: 10))
            }.padding(.horizontal, 18).padding(.top, 8)
                .animation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.85), value: showProviders)
            ScrollView {
                if let snapshot {
                    LazyVStack(spacing: 0) {
                        if showProviders {
                            ForEach(snapshot.ledgerRows) { row in
                                BillDetailRow(name: row.displayName, providerID: row.providerID,
                                              totals: row.totals, calls: row.loggedEventCount,
                                              amount: row.pricedEventCount > 0 ? row.estimatedUSD : nil,
                                              unpriced: row.unpricedEventCount, status: row.availability,
                                              currency: currency, accent: accent)
                            }
                        } else {
                            ForEach(BillPopoverPresentation.models(snapshot, providerID: nil)) { item in
                                BillDetailRow(name: item.model.shortName, providerID: item.providerID,
                                              totals: item.model.totals,
                                              calls: item.model.pricedEventCount + item.model.unpricedEventCount,
                                              amount: item.model.pricedEventCount > 0 ? item.model.estimatedUSD : nil,
                                              unpriced: item.model.unpricedEventCount, status: .logged,
                                              currency: currency, accent: accent)
                            }
                        }
                        if snapshot.allLogsMissing {
                            emptyState("No token log", detail: "Use an AI coding tool on this Mac, then reload local logs.")
                        } else if !showProviders && snapshot.modelRows(matching: nil).isEmpty {
                            emptyState("No usage in this period", detail: "Switch the period or view provider status.")
                        }
                    }.padding(.horizontal, 12).padding(.bottom, 8)
                }
            }
            Divider()
            footer.padding(.horizontal, 16).padding(.vertical, 10)
        }
        .background(surface)
        .foregroundStyle(scheme == .dark ? Color(red: 0.91, green: 0.92, blue: 0.96) : Color(red: 0.16, green: 0.20, blue: 0.25))
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

    private var chartModePicker: some View {
        ZStack {
            BillSegmentedControl(selection: $chartMode, items: [
                BillSegment(id: "composition", title: "Composition"),
                BillSegment(id: "trend", title: "Trend"),
                BillSegment(id: "activity", title: "Activity")
            ], itemWidth: 60, accent: accent)
            HStack {
                Spacer()
                Text(chartMode == "activity" ? NSLocalizedString("Last 81 days", comment: "") : chartMode == "trend" ? NSLocalizedString("Last 30 days", comment: "") : period.title)
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }.allowsHitTesting(false)
        }.frame(maxWidth: .infinity).frame(height: 31)
    }

    private var header: some View {
        HStack(spacing: 8) {
            BillActivityOrb(active: isLoading, accent: accent, reduceMotion: reduceMotion)
                .frame(width: 26, height: 26).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Usage overview").font(.system(size: 15, weight: .semibold)).accessibilityAddTraits(.isHeader)
                Text("Local logs · API-equivalent estimate").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { Task { await load(force: true) } } label: {
                if isLoading { ProgressView().controlSize(.mini) }
                else { Image(systemName: "arrow.clockwise") }
            }.buttonStyle(.plain).frame(width: 28, height: 28).disabled(isLoading)
                .help("Reload local logs").accessibilityLabel("Reload local logs")
            Menu {
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("Appearance")
        }
    }

    private func summary(_ snapshot: TokenConsumptionSnapshot) -> some View {
        let totals = snapshot.totals(matching: nil)
        let amount = totals.pricedEventCount > 0 ? totals.estimatedUSD : nil
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(amount.map { currency.grouped($0) } ?? "—")
                    .font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText(value: currency.convert(amount ?? 0)))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: amount)
                    .id("\(period.rawValue)-\(snapshot.window.start)-all-\(currency.code)-\(currency.rate)")
                    .lineLimit(1).minimumScaleFactor(0.65).fixedSize(horizontal: false, vertical: true).layoutPriority(1)
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(TokenConsumptionPresentation.callsText(totals.loggedEventCount)).font(.system(size: 11, weight: .medium))
                    Text(TokenConsumptionPresentation.windowLabel(snapshot)).font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 0) {
                metric("Tokens", value: BillPopoverPresentation.compact(totals.tokenCount))
                metric("Input", value: BillPopoverPresentation.compact(totals.input))
                metric("Output", value: BillPopoverPresentation.compact(totals.output))
                metric("Cache", value: BillPopoverPresentation.compact(totals.cacheRead + totals.cacheWrite))
            }.padding(10).background(accent.opacity(0.075), in: RoundedRectangle(cornerRadius: 9))
            if totals.unpricedEventCount > 0 {
                Label("Some calls unpriced", systemImage: "info.circle").font(.system(size: 10)).foregroundStyle(.secondary)
                    .help("Unpriced calls are included in token counts but excluded from the estimate.")
            }
        }
    }

    private func metric(_ title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 9)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12, weight: .semibold)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func chart(_ snapshot: TokenConsumptionSnapshot) -> some View {
        if chartMode == "trend" {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Daily tokens").font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text(dayReadout(snapshot)).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }
                Chart(BillPopoverPresentation.days(snapshot)) { day in
                    if let tokens = day.tokens {
                        BarMark(x: .value("Date", day.date, unit: .day), y: .value("Tokens", tokens))
                            .foregroundStyle(accent.opacity(day.date == Calendar.current.startOfDay(for: snapshot.window.now) ? 1 : 0.5))
                            .cornerRadius(2)
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
                .chartXAxis { AxisMarks(values: .stride(by: .day, count: 5)) { _ in AxisValueLabel(format: .dateTime.month(.defaultDigits).day(), centered: true) } }
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Color.secondary.opacity(0.12))
                    AxisValueLabel { if let number = value.as(Int.self) { Text(BillPopoverPresentation.compact(number)).font(.system(size: 8)) } }
                } }
                .frame(height: 86)
            }
        } else {
            let totals = snapshot.totals(matching: nil)
            let parts = BillPopoverPresentation.composition(totals)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Token composition").font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text("Including cached tokens").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                Chart(Array(parts.enumerated()), id: \.offset) { index, part in
                    BarMark(x: .value("Tokens", part.value), y: .value("Usage", String(index)))
                        .foregroundStyle(accent.opacity([1.0, 0.70, 0.36][index]))
                        .accessibilityLabel(Text(part.title)).accessibilityValue(TokenConsumptionFormatting.tokens(part.value))
                    .cornerRadius(3)
                        .annotation(position: .trailing, alignment: .leading) {
                            Text(BillPopoverPresentation.compact(part.value)).font(.system(size: 9)).monospacedDigit().foregroundStyle(.secondary)
                        }
                }
                .chartXScale(domain: 0...max(Double(parts.map(\.value).max() ?? 0) * 1.35, 1))
                .chartYScale(domain: ["0", "1", "2"])
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading, values: ["0", "1", "2"]) { axis in
                        AxisValueLabel { if let key = axis.as(String.self), let index = Int(key), parts.indices.contains(index) { Text(parts[index].title).font(.system(size: 9)) } }
                    }
                }.frame(height: 70)

            }
        }
    }

    private func activity(_ snapshot: TokenConsumptionSnapshot) -> some View {
        let days = BillPopoverPresentation.days(snapshot)
        let peak = max(days.compactMap(\.tokens).max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Daily activity").font(.system(size: 11, weight: .medium))
                Spacer()
                Text("Gaps mean no records").font(.system(size: 9)).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(11), spacing: 3), count: 27), alignment: .leading, spacing: 3) {
                ForEach(days) { day in
                    activityCell(day, peak: peak)
                }
            }.frame(width: 375).frame(maxWidth: .infinity)
            HStack {
                Text(days.first?.label ?? "")
                Spacer()
                Text("Less")
                ForEach(0..<4) { level in
                    RoundedRectangle(cornerRadius: 2).fill(accent.opacity(0.18 + Double(level) * 0.27)).frame(width: 8, height: 8)
                }
                Text("More")
                Spacer()
                Text(days.last?.label ?? "")
            }.font(.system(size: 9)).foregroundStyle(.secondary)
        }.frame(height: 85, alignment: .top)
    }

    private func activityCell(_ day: BillPopoverPresentation.Day, peak: Int) -> some View {
        // Rare UI GitHubActivity: 11px cells, 3px gaps, four discrete color levels.
        let level = day.tokens.map { $0 <= 0 ? 0 : min(4, max(1, Int(ceil(Double($0) / Double(peak) * 4)))) } ?? 0
        let intensity = [0.08, 0.30, 0.52, 0.76, 1.0][level]
        let color = day.tokens == nil ? Color.secondary.opacity(0.08) : accent.opacity(intensity)
        let value = day.tokens.map { TokenConsumptionFormatting.tokens($0) } ?? NSLocalizedString("No records", comment: "")
        return RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .overlay {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Color.secondary.opacity(day.tokens == nil ? 0.25 : 0), style: StrokeStyle(lineWidth: 1, dash: [2]))
            }
            .frame(width: 11, height: 11)
            .onHover { hovered in selectedDay = hovered ? day.date : nil }
            .accessibilityLabel(day.label)
            .accessibilityValue(value)
    }

    private func dayTooltip(_ date: Date, snapshot: TokenConsumptionSnapshot) -> some View {
        let key = TokenConsumptionClock.dayKey(date)
        let day = snapshot.daily.first { $0.day == key }
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(key).fontWeight(.semibold)
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
        .padding(12).background(surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(accent.opacity(0.25)))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
    }

    private func dayReadout(_ snapshot: TokenConsumptionSnapshot) -> String {
        guard let selectedDay else { return NSLocalizedString("Gaps mean no records", comment: "") }
        let key = TokenConsumptionClock.dayKey(selectedDay)
        let value = snapshot.daily.first { $0.day == key }
        return String(key.suffix(5)) + " · " + (value.map { TokenConsumptionFormatting.tokens($0.tokenCount) } ?? NSLocalizedString("No records", comment: ""))
    }

    private func tab(_ label: LocalizedStringKey, providers: Bool) -> some View {
        Button { showProviders = providers } label: {
            VStack(spacing: 7) {
                Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(showProviders == providers ? accent : .secondary)
                Color.clear.frame(height: 2).overlay {
                    if showProviders == providers {
                        Rectangle().fill(accent).matchedGeometryEffect(id: "detail-selection", in: detailSelection)
                    }
                }
            }.fixedSize(horizontal: true, vertical: false)
        }.buttonStyle(.plain).accessibilityAddTraits(showProviders == providers ? [.isSelected] : [])
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
                } label: { Label(currency.code, systemImage: "dollarsign.circle") }
                    .menuStyle(.borderlessButton).fixedSize().font(.system(size: 11)).accessibilityLabel("Currency")
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
            Image(systemName: "chart.bar.xaxis").font(.system(size: 24)).foregroundStyle(accent)
            Text(title).font(.system(size: 12, weight: .medium))
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

private struct BillDetailRow: View {
    let name: String
    let providerID: String
    let totals: TokenUsageTotals
    let calls: Int
    let amount: Double?
    let unpriced: Int
    let status: TokenLogAvailability
    let currency: DisplayCurrency
    let accent: Color
    @State private var expanded = false
    @State private var proximity = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 8) {
                    if let image = ProviderIconCache.image(named: CapacityDockProvider(rawValue: providerID)?.iconName ?? (providerID == "cursor-agent" ? "cursor" : providerID)) {
                        Image(nsImage: image).resizable().scaledToFit().frame(width: 17, height: 17).accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle).help(name)
                        Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 5)
                    Text(amount.map { currency.grouped($0) } ?? "—").font(.system(size: 12, weight: .medium)).monospacedDigit()
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 8, weight: .semibold)).foregroundStyle(.tertiary)
                }.padding(.horizontal, 6).padding(.vertical, 10).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityValue(expanded ? "Expanded" : "Collapsed")
            if expanded {
                VStack(alignment: .leading, spacing: 5) {
                    if status == .logged {
                        detail("Input", totals.input)
                        detail("Output", totals.displayOutput)
                        detail("Cache", totals.cacheRead)
                        detail("Cache write", totals.cacheWrite)
                        detail("Reasoning", totals.reasoning)
                        if unpriced > 0 { Text("Some calls unpriced").foregroundStyle(.secondary) }
                    } else {
                        Text(status == .unreadable ? "Could not read this provider’s local log. Check folder permissions, then press Reload local logs." : "The quota ring can show percent remaining, but this Mac has no token log for this provider.")
                            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }.font(.system(size: 10)).padding(.horizontal, 31).padding(.bottom, 10)
            }
        }.background(accent.opacity(expanded ? 0.08 : 0.025 * proximity), in: RoundedRectangle(cornerRadius: 7))
            .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 1).fill(accent.opacity(proximity * 0.6)).frame(width: 2, height: 24) }
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): proximity = max(0.2, 1 - abs(Double(point.y) - 26) / 90)
                case .ended: proximity = 0
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: proximity)
        Divider().padding(.horizontal, 6).opacity(0.5)
    }

    private var subtitle: String {
        switch status {
        case .logged:
            if calls == 0 { return NSLocalizedString("No usage in this period", comment: "") }
            return "\(BillPopoverPresentation.compact(totals.tokenCount)) tokens · \(TokenConsumptionPresentation.callsText(calls))"
        case .unreadable: return NSLocalizedString("Unread", comment: "")
        case .cursorHashOnly, .noLocalTokenLog: return NSLocalizedString("No token log", comment: "")
        }
    }

    private func detail(_ title: LocalizedStringKey, _ value: Int) -> some View {
        HStack { Text(title).foregroundStyle(.secondary); Spacer(); Text(TokenConsumptionFormatting.tokens(value)).monospacedDigit() }
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

/// A bounded refresh indicator: the fluid highlight stops when the scan ends.
private struct BillActivityOrb: View {
    let active: Bool
    let accent: Color
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15, paused: !active || reduceMotion)) { context in
            let phase = active && !reduceMotion ? context.date.timeIntervalSinceReferenceDate * 1.6 : 0
            Circle()
                .fill(accent.gradient)
                .overlay {
                    Circle().fill(.white.opacity(0.55)).frame(width: 13, height: 16)
                        .blur(radius: 4)
                        .offset(x: sin(phase) * 5, y: cos(phase * 0.8) * 4)
                }
                .overlay { Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5) }
                .clipShape(Circle())
        }
    }
}

/// Shared interaction for period and chart selection; no timers or idle animation.
private struct BillSegment<Selection: Hashable>: Identifiable {
    let id: Selection
    let title: LocalizedStringKey
}

private struct BillSegmentedControl<Selection: Hashable>: View {
    @Binding var selection: Selection
    let items: [BillSegment<Selection>]
    let itemWidth: CGFloat
    let accent: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered: Selection?
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                let selected = selection == item.id
                Button { selection = item.id } label: {
                    Text(item.title)
                        .font(.system(size: 11, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.75))
                        .frame(width: itemWidth, height: 25)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 6).fill(accent)
                                    .matchedGeometryEffect(id: "selection", in: indicator)
                            } else if hovered == item.id {
                                RoundedRectangle(cornerRadius: 6).fill(accent.opacity(0.10))
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
                .onHover { hovered = $0 ? item.id : nil }
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
        .animation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.85), value: selection)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
    }
}

/// Shared settings and bill palette; the edge widget keeps its established styling.
enum CapacityDockInterfacePalette {
    static func accent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.66, green: 0.59, blue: 1) : Color(red: 0.03, green: 0.45, blue: 0.43)
    }
    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.085, green: 0.095, blue: 0.13) : Color(red: 0.97, green: 0.975, blue: 0.98)
    }
    static func sidebar(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.065, green: 0.075, blue: 0.105) : Color(red: 0.94, green: 0.95, blue: 0.96)
    }
}
