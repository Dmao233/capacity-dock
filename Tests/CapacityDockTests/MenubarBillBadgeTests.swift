import Foundation
import Testing
@testable import CapacityDock

@Suite("Menubar bill badge")
struct MenubarBillBadgeTests {
    @Test("CodeBurn compact and regular dollar strings")
    func formatsLikeCodeBurn() {
        #expect(MenubarBillBadge.pending.menubarText() == " $—")
        #expect(MenubarBillBadge.pending.menubarText(compact: true) == "$-")
        #expect(MenubarBillBadge.amount(12.34).menubarText() == " $12.34")
        #expect(MenubarBillBadge.amount(12.34).menubarText(compact: true) == "$12")
        #expect(MenubarBillBadge.amount(0).menubarText() == " $0.00")
    }

    @Test("missing logs stay pending so the badge does not invent $0")
    func missingLogsStayPending() {
        let window = TokenConsumptionClock.window(
            for: .today,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let missing = TokenConsumptionSnapshot(
            period: .today,
            window: window,
            rows: [],
            scannedAnyLog: false
        )
        #expect(MenubarBillBadge.from(snapshot: missing) == .pending)

        let idle = TokenConsumptionSnapshot(
            period: .today,
            window: window,
            rows: [TokenConsumptionRow(
                providerID: "codex", displayName: "Codex", availability: .logged,
                totals: TokenUsageTotals(), estimatedUSD: nil,
                unpricedEventCount: 0, pricedEventCount: 0
            )],
            scannedAnyLog: true
        )
        #expect(MenubarBillBadge.from(snapshot: idle) == .amount(0))
    }

    @Test("unreadable logs and unpriced calls are not zero bills")
    func unknownAmountsStayPending() {
        var sample = fixtureSnapshot()
        sample.rows[0].availability = .unreadable
        #expect(MenubarBillBadge.from(snapshot: sample) == .pending)
        sample.rows[0].availability = .cursorHashOnly
        #expect(MenubarBillBadge.from(snapshot: sample) == .pending)
        sample.rows[0].availability = .logged
        sample.rows[0].pricedEventCount = 0
        sample.rows[0].unpricedEventCount = 1
        sample.rows[0].estimatedUSD = nil
        #expect(MenubarBillBadge.from(snapshot: sample) == .pending)

        // A real priced zero and a known subtotal remain amounts.
        sample.rows[0].pricedEventCount = 1
        sample.rows[0].unpricedEventCount = 0
        sample.rows[0].estimatedUSD = 0
        #expect(MenubarBillBadge.from(snapshot: sample) == .amount(0))
        sample.rows[0].estimatedUSD = 12.5
        sample.rows[0].unpricedEventCount = 1
        #expect(MenubarBillBadge.from(snapshot: sample) == .amount(12.5))
    }

    @Test("background, page and forced reload share a scan even if a waiter is cancelled")
    @MainActor
    func coalescesScans() async {
        let sample = fixtureSnapshot()
        let reader = DelayedBillReader(snapshot: sample)
        let store = MenubarBillStore(cacheURL: nil, now: { sample.window.now }, load: { period, _, _ in
            await reader.load(period)
        })
        let background = Task { await store.refresh(force: false) }
        await reader.waitForRequest()
        var pageStarted = false
        var forcedStarted = false
        let page = Task {
            pageStarted = true
            return await store.snapshot(for: .today)
        }
        let forced = Task {
            forcedStarted = true
            return await store.snapshot(for: .today, force: true)
        }
        while !pageStarted || !forcedStarted { await Task.yield() }
        page.cancel()
        await reader.finish()
        await background.value
        #expect(await page.value == sample)
        #expect(await forced.value == sample)
        #expect(await reader.calls == 1)
        #expect(store.badge == .amount(12.5))

        _ = await store.snapshot(for: .today)
        #expect(await reader.calls == 1)
        _ = await store.snapshot(for: .today, force: true)
        #expect(await reader.calls == 2)
        let week = await store.snapshot(for: .week)
        #expect(week.period == .week)
        #expect(store.snapshot?.period == .today)
        #expect(await reader.calls == 3)
    }

    @Test("today cache expires on TTL and at midnight; late yesterday results are rejected")
    @MainActor
    func expiresTodayCache() async {
        let zone = TimeZone.gmt
        let sample = fixtureSnapshot()
        var now = sample.window.now
        let reader = DelayedBillReader(snapshot: sample)
        await reader.finish()
        let store = MenubarBillStore(cacheURL: nil, now: { now }, timeZone: zone, load: { period, date, zone in
            var result = await reader.load(period)
            result.window = TokenConsumptionClock.window(for: period, now: date, timeZone: zone)
            return result
        })
        _ = await store.snapshot(for: .today)
        now = now.addingTimeInterval(MenubarBillStore.ttl)
        _ = await store.snapshot(for: .today)
        #expect(await reader.calls == 2)

        now = TokenConsumptionClock.window(for: .today, now: now, timeZone: zone).end.addingTimeInterval(-1)
        _ = await store.snapshot(for: .today)
        let yesterday = store.snapshot!
        now = now.addingTimeInterval(2)
        let today = await store.snapshot(for: .today)
        #expect(await reader.calls == 4)
        #expect(today.window.start > yesterday.window.start)
        store.apply(yesterday)
        #expect(store.badge == .pending)
        #expect(store.snapshot == nil)
    }

    @Test("an incomplete persisted amount never becomes zero")
    @MainActor
    func invalidPersistedAmount() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("capacity-dock-bill-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let sample = fixtureSnapshot()
        let url = dir.appendingPathComponent("bill.json")
        let data = try JSONSerialization.data(withJSONObject: [
            "day": TokenConsumptionClock.dayKey(sample.window.now, timeZone: .gmt),
            "pending": false,
            "generatedAt": sample.window.now.timeIntervalSince1970
        ])
        try SafeFile.write(data, to: url.path)
        let store = MenubarBillStore(cacheURL: url, now: { sample.window.now }, timeZone: .gmt)
        #expect(store.badge == .pending)
    }

    @Test("persisted today amount survives a store relaunch")
    @MainActor
    func persistsTodayAmount() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("capacity-dock-bill-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("menubar-bill.json")
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let zone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt
        let window = TokenConsumptionClock.window(for: .today, now: now, timeZone: zone)
        let first = MenubarBillStore(cacheURL: url, now: { now }, timeZone: zone)
        first.apply(
            TokenConsumptionSnapshot(
                period: .today,
                window: window,
                rows: [
                    TokenConsumptionRow(
                        providerID: "codex",
                        displayName: "Codex",
                        availability: .logged,
                        totals: TokenUsageTotals(input: 100),
                        estimatedUSD: 12.5,
                        unpricedEventCount: 0,
                        pricedEventCount: 1
                    )
                ],
                scannedAnyLog: true
            )
        )
        #expect(first.badge == .amount(12.5))
        let billed = MenubarBillStore(cacheURL: url, now: { now }, timeZone: zone)
        #expect(billed.badge == .amount(12.5))

        let nextDay = MenubarBillStore(
            cacheURL: url,
            now: { now.addingTimeInterval(86_400) },
            timeZone: zone
        )
        #expect(nextDay.badge == .pending)
    }

    private func fixtureSnapshot() -> TokenConsumptionSnapshot {
        TokenConsumptionSnapshot(
            period: .today,
            window: TokenConsumptionClock.window(for: .today, now: Date(timeIntervalSince1970: 1_700_000_000), timeZone: .gmt),
            rows: [TokenConsumptionRow(
                providerID: "codex", displayName: "Codex", availability: .logged,
                totals: TokenUsageTotals(input: 100), estimatedUSD: 12.5,
                unpricedEventCount: 0, pricedEventCount: 1
            )],
            scannedAnyLog: true
        )
    }
}

private actor DelayedBillReader {
    let snapshot: TokenConsumptionSnapshot
    private(set) var calls = 0
    private var finished = false
    private var pending: [CheckedContinuation<Void, Never>] = []
    private var started: CheckedContinuation<Void, Never>?

    init(snapshot: TokenConsumptionSnapshot) { self.snapshot = snapshot }

    func load(_ period: TokenConsumptionPeriod) async -> TokenConsumptionSnapshot {
        calls += 1
        started?.resume()
        started = nil
        if !finished { await withCheckedContinuation { pending.append($0) } }
        var result = snapshot
        result.period = period
        return result
    }

    func waitForRequest() async {
        if calls > 0 { return }
        await withCheckedContinuation { started = $0 }
    }

    func finish() {
        finished = true
        pending.forEach { $0.resume() }
        pending.removeAll()
    }
}
