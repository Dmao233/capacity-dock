import Foundation
import Testing
@testable import CapacityDock

@Suite("Bill popover projections")
struct BillPopoverTests {
    private func snapshot(now: Date, period: TokenConsumptionPeriod = .month, zone: TimeZone = .gmt) -> TokenConsumptionSnapshot {
        TokenConsumptionSnapshot(period: period, window: TokenConsumptionClock.window(for: period, now: now, timeZone: zone), rows: [], scannedAnyLog: true)
    }

    @Test("Calendar gaps stay missing, measured zero stays zero, no future dates")
    func preservesMissingDays() {
        let now = TokenConsumptionClock.parseTimestamp("2026-09-04T12:00:00Z")!
        var value = snapshot(now: now)
        value.daily = [.init(day: "2026-09-01", tokenCount: 42, calls: 1, estimatedUSD: 1, pricedEventCount: 1),
                       .init(day: "2026-09-03", tokenCount: 0, calls: 1, estimatedUSD: 0, pricedEventCount: 1)]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let days = BillPopoverPresentation.days(value, calendar: calendar)
        #expect(days.count == 4)
        #expect(days.map(\.tokens) == [42, nil, 0, nil])
        #expect(days.last?.label == "2026-09-04")
    }

    @Test("Calendar chart crosses daylight-saving without dropping or duplicating dates")
    func daylightSavingDays() {
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        let now = TokenConsumptionClock.parseTimestamp("2026-03-10T18:00:00Z")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let days = BillPopoverPresentation.days(snapshot(now: now, zone: zone), calendar: calendar)
        #expect(days.count == 10)
        #expect(Set(days.map(\.label)).count == 10)
        #expect(days[8].date.timeIntervalSince(days[7].date) == 23 * 3600)
    }

    @Test("Activity always spans 30 calendar days including today across DST")
    func activityHistoryWindow() {
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        let now = TokenConsumptionClock.parseTimestamp("2026-03-10T18:00:00Z")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let value = TokenConsumptionSnapshot(period: .month,
            window: TokenConsumptionClock.activityWindow(now: now, timeZone: zone), rows: [], scannedAnyLog: false)
        let days = BillPopoverPresentation.days(value, calendar: calendar)
        #expect(days.count == 30)
        #expect(Set(days.map(\.label)).count == 30)
        #expect(days.last?.label == "2026-03-10")
        #expect(days.allSatisfy { $0.tokens == nil })
    }

    @Test("Hover breakdown isolates days and providers, reconciles tokens and preserves unknown pricing")
    func dailyModelBreakdown() throws {
        let now = TokenConsumptionClock.parseTimestamp("2026-09-04T12:00:00Z")!
        let old = now.addingTimeInterval(-86400)
        let events: [TokenConsumptionEvent] = [
            .init(providerID: "codex", date: now, model: "gpt-6-astra", totals: .init(input: 100)),
            .init(providerID: "codex", date: now, model: "gpt-6-astra", totals: .init(output: 20)),
            .init(providerID: "grok", date: now, model: "unpriced-test-model", totals: .init(input: 30)),
            .init(providerID: "codex", date: old, model: "gpt-6-astra", totals: .init(input: 900))
        ]
        let value = TokenConsumptionAggregator.snapshot(period: .month,
            window: TokenConsumptionClock.window(for: .month, now: now, timeZone: .gmt),
            events: events, availability: ["codex": .logged, "grok": .logged], scannedAnyLog: true, timeZone: .gmt)
        let day = try #require(value.daily.first { $0.day == "2026-09-04" })
        #expect(day.models.count == 2)
        #expect(day.models.reduce(0) { $0 + $1.tokens } == day.tokenCount)
        #expect(day.models.first?.tokens == 120)
        let expectedUSD = CodeBurnPricing.estimateUSD(provider: "codex", model: "gpt-6-astra", totals: .init(input: 100, output: 20))
        #expect(abs((day.models.first?.estimatedUSD ?? 0) - expectedUSD) < 0.000001)
        #expect(day.models.last?.estimatedUSD == nil)
    }

    @Test("Same model across providers has distinct identity and filters correctly")
    func modelIdentityAndFilter() {
        var value = snapshot(now: Date())
        let model = TokenConsumptionModelRow(model: "shared", totals: .init(input: 10), estimatedUSD: nil, unpricedEventCount: 1, pricedEventCount: 0)
        value.rows = ["codex", "grok"].map {
            TokenConsumptionRow(providerID: $0, displayName: $0, availability: .logged,
                                totals: model.totals, estimatedUSD: nil, unpricedEventCount: 1, pricedEventCount: 0, models: [model])
        }
        let models = BillPopoverPresentation.models(value, providerID: nil)
        #expect(models.count == 2)
        #expect(Set(models.map(\.id)).count == 2)
        #expect(BillPopoverPresentation.models(value, providerID: "grok").map(\.providerID) == ["grok"])
        #expect(models.allSatisfy { $0.model.estimatedUSD == nil })
    }

    @Test("Chart categories reconcile with the hero and do not double-count reasoning")
    func compositionReconciles() {
        var value = snapshot(now: Date())
        value.rows = [.init(providerID: "codex", displayName: "Codex", availability: .logged,
                            totals: .init(input: 100, output: 50, cacheRead: 200, cacheWrite: 10, reasoning: 20, outputIncludesReasoning: true),
                            estimatedUSD: 1, unpricedEventCount: 0, pricedEventCount: 1)]
        let totals = value.periodTotals
        #expect(BillPopoverPresentation.composition(totals).map(\.value) == [100, 50, 210])
        #expect(BillPopoverPresentation.composition(totals).reduce(0) { $0 + $1.value } == totals.tokenCount)
    }
}
