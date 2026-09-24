import Foundation
import Testing
@testable import CapacityDock

@Suite("Incremental log parsing")
struct IncrementalLogParseTests {
    private let now = TokenConsumptionClock.parseTimestamp("2026-09-07T12:00:00Z")!

    private func codexLine(_ minute: Int, input: Int, total: Int) -> String {
        let ts = String(format: "2026-09-07T10:%02d:00Z", minute)
        return #"{"timestamp":"\#(ts)","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":\#(input),"cached_input_tokens":0,"output_tokens":2,"reasoning_output_tokens":0},"total_token_usage":{"input_tokens":\#(total),"cached_input_tokens":0,"output_tokens":2,"reasoning_output_tokens":0,"total_tokens":\#(total + 2)}}}}"#
    }

    private func claudeLine(_ minute: Int, input: Int) -> String {
        let ts = String(format: "2026-09-07T10:%02d:00Z", minute)
        return #"{"type":"assistant","timestamp":"\#(ts)","message":{"model":"claude-sonnet-5","usage":{"input_tokens":\#(input),"output_tokens":3}}}"#
    }

    private func home() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("incremental-\(UUID())")
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".codex/sessions/2026/09/07"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".claude/projects/demo"), withIntermediateDirectories: true)
        return root
    }

    private func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
    }

    private func totals(_ snapshot: TokenConsumptionSnapshot) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: snapshot.rows.map { ($0.providerID, $0.totals.input) })
    }

    @Test("Appended and partially written lines match a fresh full parse at every step")
    func appendMatchesFullParse() throws {
        let root = try home()
        defer { try? FileManager.default.removeItem(at: root) }
        let codex = root.appendingPathComponent(".codex/sessions/2026/09/07/rollout-a.jsonl")
        let claude = root.appendingPathComponent(".claude/projects/demo/session.jsonl")
        try (codexLine(1, input: 10, total: 10) + "\n").write(to: codex, atomically: false, encoding: .utf8)
        try (claudeLine(1, input: 5) + "\n").write(to: claude, atomically: false, encoding: .utf8)
        let deps = LocalTokenLogReader.Deps(home: root, now: now, timeZone: .gmt, cacheURL: nil)
        var resident = TokenLogDayCache()

        func check(_ expected: [String: Int]) {
            let incremental = LocalTokenLogReader.load(period: .today, deps: deps, cache: &resident)
            var fresh = TokenLogDayCache()
            let full = LocalTokenLogReader.load(period: .today, deps: deps, cache: &fresh)
            #expect(incremental == full)
            #expect(totals(incremental)["codex"] == expected["codex"])
            #expect(totals(incremental)["claude"] == expected["claude"])
        }

        check(["codex": 10, "claude": 5])
        // A second line arrives, plus half of a third that is still being written.
        let third = codexLine(3, input: 30, total: 60)
        try append(codexLine(2, input: 20, total: 30) + "\n" + third.prefix(40), to: codex)
        let claudeThird = claudeLine(3, input: 9)
        try append(claudeLine(2, input: 7) + "\n" + claudeThird, to: claude)
        // The unterminated Claude line is complete JSON, so it counts now...
        check(["codex": 30, "claude": 21])
        // ...and finishing both lines must not count anything twice.
        try append(String(third.dropFirst(40)) + "\n", to: codex)
        try append("\n", to: claude)
        check(["codex": 60, "claude": 21])
    }

    @Test("A replaced log is parsed from the start, not resumed")
    func replacedFileRestarts() throws {
        let root = try home()
        defer { try? FileManager.default.removeItem(at: root) }
        let claude = root.appendingPathComponent(".claude/projects/demo/session.jsonl")
        try (claudeLine(1, input: 5) + "\n").write(to: claude, atomically: false, encoding: .utf8)
        let deps = LocalTokenLogReader.Deps(home: root, now: now, timeZone: .gmt, cacheURL: nil)
        var resident = TokenLogDayCache()
        _ = LocalTokenLogReader.load(period: .today, deps: deps, cache: &resident)
        // Atomic write swaps in a new inode with longer, different content.
        try (claudeLine(1, input: 100) + "\n" + claudeLine(2, input: 1) + "\n").write(to: claude, atomically: true, encoding: .utf8)
        let snapshot = LocalTokenLogReader.load(period: .today, deps: deps, cache: &resident)
        #expect(totals(snapshot)["claude"] == 101)
    }

    @Test("Legacy keyed v5 cache still loads and saves compactly as v7")
    func legacyCacheLoads() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("cache.json")
        let legacy = #"{"version":5,"files":{"/x/a.jsonl":{"size":3,"mtime":2,"events":[{"providerID":"codex","day":"2026-09-07","timestamp":100,"model":"gpt-5","input":7,"output":1,"cacheRead":0,"cacheWrite":0,"reasoning":0,"outputIncludesReasoning":true}]}}}"#
        try Data(legacy.utf8).write(to: url)
        var cache = TokenLogDayCache.load(from: url)
        #expect(cache.version == 7)
        #expect(cache.files["/x/a.jsonl"]?.events.first?.input == 7)
        cache.save(to: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains(#"[["codex",100.0,"gpt-5",7,1,0,0,0,1]]"#))
        #expect(TokenLogDayCache.load(from: url) == cache)
    }

    @Test("Throttled saves wait for the interval unless nothing was written yet")
    func throttledSave() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("throttle-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("cache.json")
        let start = Date(timeIntervalSince1970: 1_000_000)
        var cache = TokenLogDayCache()
        cache.store(file: URL(fileURLWithPath: "/x/a"), fingerprint: .init(size: 1, mtime: 1), events: [])
        cache.saveIfDue(to: url, interval: 600, now: start)
        #expect(FileManager.default.fileExists(atPath: url.path))
        cache.store(file: URL(fileURLWithPath: "/x/b"), fingerprint: .init(size: 1, mtime: 1), events: [])
        cache.saveIfDue(to: url, interval: 600, now: start.addingTimeInterval(60))
        #expect(TokenLogDayCache.load(from: url).files.count == 1)
        cache.saveIfDue(to: url, interval: 600, now: start.addingTimeInterval(601))
        #expect(TokenLogDayCache.load(from: url).files.count == 2)
    }
}
