import Foundation
import Testing
@testable import CapacityDock

@Suite("Historical bill loading")
struct BillLoadingTests {
    @Test("Timestamp parser preserves UTC, offsets and fractional log timestamps", arguments: [
        "2026-09-07T12:34:56Z", "2026-09-07T12:34:56.123Z", "2026-09-07T12:34:56.123456Z",
        "2026-09-07T20:34:56+08:00", "2026-09-07T20:34:56.123+08:00"
    ])
    func timestampCompatibility(raw: String) throws {
        let legacy = ISO8601DateFormatter()
        legacy.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fractional = legacy.date(from: raw)
        legacy.formatOptions = [.withInternetDateTime]
        let expected = try #require(fractional ?? legacy.date(from: raw))
        let actual = try #require(TokenConsumptionClock.parseTimestamp(raw))
        #expect(abs(actual.timeIntervalSince(expected)) < 0.001)
        #expect(TokenConsumptionClock.parseTimestamp("not a timestamp") == nil)
    }

    @Test("Streaming preserves chunk boundaries and discards whole oversized lines")
    func streamingBoundaries() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("bill-stream-\(UUID()).jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        let accepted = "{\"payload\":\"" + String(repeating: "中文", count: 14_000) + "\"}"
        let oversized = "{\"payload\":\"" + String(repeating: "x", count: JSONLStreamer.maxLineBytes + 65_000) + "\"}"
        let tail = "{\"tail\":true}"
        try Data((accepted + "\r\n" + oversized + "\n" + tail).utf8).write(to: file)
        var lines: [String] = []
        JSONLStreamer.forEachLine(at: file) { lines.append($0) }
        #expect(lines == [accepted, tail])
    }

    @Test("Week and month reuse completed results, force and TTL still rescan")
    @MainActor
    func historicalCache() async {
        let zone = TimeZone.gmt
        var now = TokenConsumptionClock.parseTimestamp("2026-09-07T12:00:00Z")!
        let reader = CountingReader()
        let store = MenubarBillStore(cacheURL: nil, now: { now }, timeZone: zone) { period, date, zone in
            await reader.load(period: period, now: date, zone: zone)
        }
        for period in [TokenConsumptionPeriod.week, .month] {
            _ = await store.snapshot(for: period)
            _ = await store.snapshot(for: period)
        }
        #expect(await reader.count == 2)
        #expect(store.snapshot == nil)
        _ = await store.snapshot(for: .week, force: true)
        #expect(await reader.count == 3)
        now = now.addingTimeInterval(MenubarBillStore.ttl)
        _ = await store.snapshot(for: .week)
        #expect(await reader.count == 4)
        now = TokenConsumptionClock.window(for: .today, now: now, timeZone: zone).end.addingTimeInterval(1)
        let nextDay = await store.snapshot(for: .month)
        #expect(await reader.count == 5)
        #expect(nextDay.window.contains(now))
    }

    @Test("Historical token cache larger than generic 8 MB limit stays reusable")
    func largeCacheRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bill-cache-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("session.jsonl")
        let target = root.appendingPathComponent("cache.json")
        try Data("{}".utf8).write(to: source)
        var cache = TokenLogDayCache()
        let event = TokenConsumptionEvent(providerID: "codex", date: Date(), model: String(repeating: "x", count: SafeFile.defaultReadLimit + 1), totals: .init(input: 1))
        cache.store(file: source, fingerprint: TokenLogDayCache.fingerprint(of: source), events: [event])
        cache.save(to: target)
        let loaded = TokenLogDayCache.load(from: target)
        #expect(loaded.files.count == 1)
        #expect(loaded.events(for: source, fingerprint: TokenLogDayCache.fingerprint(of: source), providerID: "codex")?.first?.totals.input == 1)
    }

    @Test("Unchanged cache is not rewritten; changed entries still persist")
    func cacheWritesOnlyChanges() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bill-dirty-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("cache.json")
        let source = root.appendingPathComponent("session.jsonl")
        let fingerprint = TokenLogDayCache.Fingerprint(size: 2, mtime: 1)
        var cache = TokenLogDayCache()
        cache.store(file: source, fingerprint: fingerprint, events: [])
        let escaped = root.appendingPathComponent("中文-\"quoted\".jsonl")
        cache.store(file: escaped, fingerprint: fingerprint, events: [
            TokenConsumptionEvent(providerID: "codex", date: Date(timeIntervalSince1970: 123), model: "test", totals: .init(input: 7))
        ])
        cache.save(to: target)
        #expect(TokenLogDayCache.load(from: target).files == cache.files)
        let sentinel = Date(timeIntervalSince1970: 1_000)
        try FileManager.default.setAttributes([.modificationDate: sentinel], ofItemAtPath: target.path)
        var loaded = TokenLogDayCache.load(from: target)
        loaded.save(to: target)
        cache.save(to: target)
        let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
        #expect(attributes[.modificationDate] as? Date == sentinel)
        loaded.store(file: source, fingerprint: .init(size: 3, mtime: 2), events: [])
        // A failed save must retain the pending change.
        loaded.save(to: root.appendingPathComponent("cache.json/invalid"))
        loaded.save(to: target)
        #expect(TokenLogDayCache.load(from: target).files[source.path]?.size == 3)
    }

    @Test("Cache filters by inclusive window before materializing events")
    func cachedWindowBoundaries() {
        let file = URL(fileURLWithPath: "/fixture/session.jsonl")
        let fingerprint = TokenLogDayCache.Fingerprint(size: 1, mtime: 1)
        let window = TokenConsumptionWindow(start: Date(timeIntervalSince1970: 100),
                                            end: Date(timeIntervalSince1970: 200), now: Date(timeIntervalSince1970: 150))
        var cache = TokenLogDayCache()
        let events = [99.0, 100, 150, 200, 201].map {
            TokenConsumptionEvent(providerID: "codex", date: Date(timeIntervalSince1970: $0), model: "test", totals: .init(input: 1))
        }
        cache.store(file: file, fingerprint: fingerprint, events: events)
        #expect(cache.events(for: file, fingerprint: fingerprint, providerID: "codex", window: window)?.map(\.date)
                == events.filter { window.contains($0.date) }.map(\.date))
        #expect(cache.events(for: file, fingerprint: fingerprint, providerID: "other", window: window)?.isEmpty == true)
        #expect(cache.events(for: file, fingerprint: .init(size: 2, mtime: 1), providerID: "codex", window: window) == nil)
    }

    private actor CountingReader {
        var count = 0
        func load(period: TokenConsumptionPeriod, now: Date, zone: TimeZone) -> TokenConsumptionSnapshot {
            count += 1
            return TokenConsumptionSnapshot(period: period, window: TokenConsumptionClock.window(for: period, now: now, timeZone: zone), rows: [], scannedAnyLog: true)
        }
    }
}
