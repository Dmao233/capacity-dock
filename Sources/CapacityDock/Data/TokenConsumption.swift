import Foundation

/// Calendar window for the consumption ledger. Matches CodeBurn menubar
/// `getDateRange`: today, rolling last 7 days, calendar month.
enum TokenConsumptionPeriod: String, CaseIterable, Identifiable, Sendable {
    case today
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: NSLocalizedString("Today", comment: "")
        case .week: NSLocalizedString("Last 7 Days", comment: "")
        case .month: NSLocalizedString("This Month", comment: "")
        }
    }
}

struct TokenConsumptionWindow: Equatable, Sendable {
    let start: Date
    let end: Date
    let now: Date

    /// CodeBurn: `ts >= range.start && ts <= range.end` (end is 23:59:59.999 local).
    func contains(_ date: Date) -> Bool {
        date >= start && date <= end
    }
}

enum TokenConsumptionClock {
    /// Local midnight windows from `src/cli-date.ts` `getDateRange`.
    static func window(
        for period: TokenConsumptionPeriod,
        now: Date,
        timeZone: TimeZone = .current
    ) -> TokenConsumptionWindow {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let startOfDay = calendar.startOfDay(for: now)
        let endOfToday = endOfLocalDay(startOfDay, calendar: calendar)
        let start: Date
        switch period {
        case .today:
            start = startOfDay
        case .week:
            start = calendar.date(byAdding: .day, value: -7, to: startOfDay) ?? startOfDay
        case .month:
            let parts = calendar.dateComponents([.year, .month], from: startOfDay)
            start = calendar.date(from: parts) ?? startOfDay
        }
        return TokenConsumptionWindow(start: start, end: endOfToday, now: now)
    }

    static func endOfLocalDay(_ startOfDay: Date, calendar: Calendar) -> Date {
        let next = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay.addingTimeInterval(86_400)
        return next.addingTimeInterval(-0.001)
    }

    static func dayKey(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let year = parts.year ?? 0
        let month = parts.month ?? 0
        let day = parts.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func parseTimestamp(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: raw)
    }
}

struct TokenUsageTotals: Equatable, Sendable {
    var input: Int = 0
    var output: Int = 0
    var cacheRead: Int = 0
    var cacheWrite: Int = 0
    var reasoning: Int = 0
    var outputIncludesReasoning: Bool = false

    var tokenCount: Int {
        input + output + cacheRead + cacheWrite + (outputIncludesReasoning ? 0 : reasoning)
    }

    /// Output shown in the ledger. Codex already folds reasoning into `output`.
    var displayOutput: Int {
        output + (outputIncludesReasoning ? 0 : reasoning)
    }

    mutating func add(_ other: TokenUsageTotals) {
        input += other.input
        output += other.output
        cacheRead += other.cacheRead
        cacheWrite += other.cacheWrite
        reasoning += other.reasoning
        outputIncludesReasoning = outputIncludesReasoning || other.outputIncludesReasoning
    }
}

struct TokenConsumptionEvent: Equatable, Sendable {
    var providerID: String
    var date: Date
    var model: String?
    var totals: TokenUsageTotals
}

enum TokenLogAvailability: Equatable, Sendable {
    case logged
    case noLocalTokenLog
    case cursorHashOnly
    case unreadable
}

struct TokenConsumptionRow: Equatable, Identifiable, Sendable {
    var providerID: String
    var displayName: String
    var availability: TokenLogAvailability
    var totals: TokenUsageTotals
    var estimatedUSD: Double?
    var unpricedEventCount: Int
    var pricedEventCount: Int
    var models: [TokenConsumptionModelRow] = []

    var id: String { providerID }

    var hasMeasuredTokens: Bool {
        availability == .logged
    }

    /// Missing logs must not render as a real $0 / 0-token bill.
    var showsMeasuredZero: Bool {
        availability == .logged && totals.tokenCount == 0
    }

    var showsCurrency: Bool {
        availability == .logged && loggedEventCount > 0 && estimatedUSD != nil
    }

    var loggedEventCount: Int {
        pricedEventCount + unpricedEventCount
    }
}

struct TokenConsumptionModelRow: Equatable, Identifiable, Sendable {
    var model: String
    var totals: TokenUsageTotals
    var estimatedUSD: Double?
    var unpricedEventCount: Int
    var pricedEventCount: Int

    var id: String { model }

    var showsCurrency: Bool {
        (pricedEventCount + unpricedEventCount) > 0 && estimatedUSD != nil
    }

    var shortName: String {
        if let slash = model.lastIndex(of: "/") {
            return String(model[model.index(after: slash)...])
        }
        return model
    }
}

struct TokenConsumptionDay: Equatable, Identifiable, Sendable {
    var day: String
    var tokenCount: Int
    var calls: Int
    var estimatedUSD: Double?
    var pricedEventCount: Int

    var id: String { day }

    var showsCurrency: Bool {
        estimatedUSD != nil
    }
}

struct TokenConsumptionSnapshot: Equatable, Sendable {
    var period: TokenConsumptionPeriod
    var window: TokenConsumptionWindow
    var rows: [TokenConsumptionRow]
    var scannedAnyLog: Bool
    var daily: [TokenConsumptionDay] = []

    /// Only days that already have token events. Gaps stay empty — no $0 bars.
    var showsDailyTrend: Bool {
        daily.count >= 2
    }

    var hasAnyMeasuredRow: Bool {
        rows.contains { $0.availability == .logged && $0.totals.tokenCount > 0 }
    }

    var allLogsMissing: Bool {
        !scannedAnyLog && rows.allSatisfy {
            $0.availability == .noLocalTokenLog || $0.availability == .cursorHashOnly
        }
    }

    /// Parseable or explicitly unexplained rows. Hide "no log" fillers so this
    /// page is a ledger, not a second provider-status list.
    var ledgerRows: [TokenConsumptionRow] {
        rows.filter { row in
            switch row.availability {
            case .logged, .unreadable, .cursorHashOnly:
                return true
            case .noLocalTokenLog:
                return false
            }
        }
    }

    var periodTotals: TokenConsumptionPeriodTotals {
        totals(matching: nil)
    }

    func totals(matching providerID: String?) -> TokenConsumptionPeriodTotals {
        var totals = TokenConsumptionPeriodTotals()
        var usd = 0.0
        for row in rows where row.availability == .logged {
            if let providerID, row.providerID != providerID { continue }
            totals.input += row.totals.input
            totals.output += row.totals.displayOutput
            totals.cacheRead += row.totals.cacheRead
            totals.cacheWrite += row.totals.cacheWrite
            totals.reasoning += row.totals.reasoning
            totals.tokenCount += row.totals.tokenCount
            totals.pricedEventCount += row.pricedEventCount
            totals.unpricedEventCount += row.unpricedEventCount
            if row.totals.tokenCount > 0 {
                totals.measuredProviderCount += 1
            }
            if let amount = row.estimatedUSD {
                usd += amount
            }
        }
        totals.estimatedUSD = totals.loggedEventCount > 0 ? usd : nil
        return totals
    }

    func modelRows(matching providerID: String?) -> [TokenConsumptionModelRow] {
        rows
            .filter { row in
                row.availability == .logged && (providerID == nil || row.providerID == providerID)
            }
            .flatMap(\.models)
            .sorted { lhs, rhs in
                let left = lhs.estimatedUSD ?? -1
                let right = rhs.estimatedUSD ?? -1
                if left != right { return left > right }
                if lhs.totals.tokenCount != rhs.totals.tokenCount {
                    return lhs.totals.tokenCount > rhs.totals.tokenCount
                }
                return lhs.model < rhs.model
            }
    }

    var billedProviderRows: [TokenConsumptionRow] {
        ledgerRows.filter { $0.availability == .logged && ($0.totals.tokenCount > 0 || $0.loggedEventCount > 0) }
    }
}

struct TokenConsumptionPeriodTotals: Equatable, Sendable {
    var input: Int = 0
    var output: Int = 0
    var cacheRead: Int = 0
    var cacheWrite: Int = 0
    var reasoning: Int = 0
    var tokenCount: Int = 0
    var estimatedUSD: Double?
    var pricedEventCount: Int = 0
    var unpricedEventCount: Int = 0
    var measuredProviderCount: Int = 0

    var showsCurrency: Bool {
        loggedEventCount > 0 && estimatedUSD != nil
    }

    var loggedEventCount: Int {
        pricedEventCount + unpricedEventCount
    }
}

enum TokenConsumptionAggregator {
    static let ledgerProviderIDs = [
        "codex", "claude", "gemini", "copilot", "kimi",
        "grok", "cursor", "cursor-agent", "antigravity", "clinepass", "zai"
    ]

    static func displayName(for id: String) -> String {
        if id == "cursor-agent" { return "Cursor Agent" }
        return CapacityDockProvider(rawValue: id)?.displayName ?? id
    }

    static func snapshot(
        period: TokenConsumptionPeriod,
        window: TokenConsumptionWindow,
        events: [TokenConsumptionEvent],
        availability: [String: TokenLogAvailability],
        scannedAnyLog: Bool,
        timeZone: TimeZone = .current
    ) -> TokenConsumptionSnapshot {
        struct ModelBucket {
            var totals = TokenUsageTotals()
            var usd = 0.0
            var priced = 0
            var unpriced = 0
        }

        var totalsByProvider: [String: TokenUsageTotals] = [:]
        var priced: [String: Int] = [:]
        var unpriced: [String: Int] = [:]
        var usd: [String: Double] = [:]
        var modelsByProvider: [String: [String: ModelBucket]] = [:]
        var dayTokens: [String: Int] = [:]
        var dayCalls: [String: Int] = [:]
        var dayUSD: [String: Double] = [:]
        var dayPriced: [String: Int] = [:]

        for event in events where window.contains(event.date) {
            var running = totalsByProvider[event.providerID] ?? TokenUsageTotals()
            running.add(event.totals)
            totalsByProvider[event.providerID] = running
            let pricingModel = CodeBurnPricing.cleaned(event.model)
                ?? (event.providerID == "grok" ? "grok-build" : event.model)
            let amount = CodeBurnPricing.estimateUSD(
                provider: event.providerID,
                model: pricingModel,
                totals: event.totals
            )
            usd[event.providerID, default: 0] += amount
            let isPriced = CodeBurnPricing.hasBillableRate(pricingModel)
            if isPriced {
                priced[event.providerID, default: 0] += 1
            } else {
                unpriced[event.providerID, default: 0] += 1
            }
            if let model = CodeBurnPricing.cleaned(pricingModel) ?? (event.providerID == "grok" ? "grok-build" : nil) {
                var bucket = modelsByProvider[event.providerID, default: [:]][model] ?? ModelBucket()
                bucket.totals.add(event.totals)
                bucket.usd += amount
                if isPriced {
                    bucket.priced += 1
                } else {
                    bucket.unpriced += 1
                }
                modelsByProvider[event.providerID, default: [:]][model] = bucket
            }
            let day = TokenConsumptionClock.dayKey(event.date, timeZone: timeZone)
            dayTokens[day, default: 0] += event.totals.tokenCount
            dayCalls[day, default: 0] += 1
            dayUSD[day, default: 0] += amount
            dayPriced[day, default: 0] += 1
        }

        let daily = dayTokens.keys.sorted().compactMap { day -> TokenConsumptionDay? in
            let tokens = dayTokens[day] ?? 0
            guard tokens > 0 else { return nil }
            let pricedCount = dayPriced[day] ?? 0
            return TokenConsumptionDay(
                day: day,
                tokenCount: tokens,
                calls: dayCalls[day] ?? 0,
                estimatedUSD: pricedCount > 0 ? dayUSD[day] : nil,
                pricedEventCount: pricedCount
            )
        }

        let rows = ledgerProviderIDs.compactMap { id -> TokenConsumptionRow? in
            if CapacityDockProvider(rawValue: id) == nil, id != "cursor-agent" { return nil }
            let status = availability[id] ?? .noLocalTokenLog
            let measured = totalsByProvider[id] ?? TokenUsageTotals()
            let pricedCount = priced[id] ?? 0
            let unpricedCount = unpriced[id] ?? 0
            let namedModels = (modelsByProvider[id] ?? [:]).map { name, bucket in
                TokenConsumptionModelRow(
                    model: name,
                    totals: bucket.totals,
                    estimatedUSD: (bucket.priced + bucket.unpriced) > 0 ? bucket.usd : nil,
                    unpricedEventCount: bucket.unpriced,
                    pricedEventCount: bucket.priced
                )
            }
            .sorted { lhs, rhs in
                if lhs.totals.tokenCount != rhs.totals.tokenCount {
                    return lhs.totals.tokenCount > rhs.totals.tokenCount
                }
                return lhs.model < rhs.model
            }
            return TokenConsumptionRow(
                providerID: id,
                displayName: displayName(for: id),
                availability: status,
                totals: status == .logged ? measured : TokenUsageTotals(),
                estimatedUSD: (pricedCount + unpricedCount) > 0 ? usd[id] : nil,
                unpricedEventCount: unpricedCount,
                pricedEventCount: pricedCount,
                models: status == .logged ? namedModels : []
            )
        }
        return TokenConsumptionSnapshot(
            period: period,
            window: window,
            rows: rows,
            scannedAnyLog: scannedAnyLog,
            daily: daily
        )
    }
}

enum TokenConsumptionFormatting {
    static func tokens(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.locale = .current
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func usd(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US")
        if value > 0, value < 0.01 {
            formatter.minimumFractionDigits = 4
            formatter.maximumFractionDigits = 4
        } else {
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
        }
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }
}

enum TokenConsumptionHeroKind: Equatable, Sendable {
    case missingLogs
    case emptyPeriod
    case billed
    case tokensOnly
}

enum TokenConsumptionPresentation {
    static func heroKind(_ snapshot: TokenConsumptionSnapshot, providerID: String? = nil) -> TokenConsumptionHeroKind {
        if snapshot.allLogsMissing { return .missingLogs }
        let totals = snapshot.totals(matching: providerID)
        if totals.tokenCount == 0 && totals.loggedEventCount == 0 { return .emptyPeriod }
        return totals.showsCurrency ? .billed : .tokensOnly
    }

    /// Dollar hero, matching CodeBurn's menubar amount. Nil when there is no priced usage.
    static func heroAmount(_ totals: TokenConsumptionPeriodTotals) -> String? {
        guard totals.showsCurrency, let usd = totals.estimatedUSD else { return nil }
        return TokenConsumptionFormatting.usd(usd)
    }

    static func windowLabel(_ snapshot: TokenConsumptionSnapshot) -> String {
        let start = TokenConsumptionClock.dayKey(snapshot.window.start)
        let end = TokenConsumptionClock.dayKey(min(snapshot.window.now, snapshot.window.end.addingTimeInterval(-1)))
        if snapshot.period == .today || start == end {
            return "\(snapshot.period.title) · \(start)"
        }
        return "\(snapshot.period.title) · \(start) – \(end)"
    }

    static func callsText(_ count: Int) -> String {
        String(format: NSLocalizedString("%@ calls", comment: ""), TokenConsumptionFormatting.tokens(count))
    }

    static func tokensText(_ count: Int) -> String {
        String(format: NSLocalizedString("%@ tokens total", comment: ""), TokenConsumptionFormatting.tokens(count))
    }
}
