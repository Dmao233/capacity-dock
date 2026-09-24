import Foundation
import Darwin

/// Read-only local JSONL token logs. Quota percentages are not a source.
enum LocalTokenLogReader {
    static let parsedProviderIDs: Set<String> = ["claude", "codex", "grok", "cursor", "cursor-agent"]

    struct Deps: Sendable {
        var home: URL
        var now: Date
        var timeZone: TimeZone
        var cacheURL: URL?
        var progress: (@Sendable (Int, Int) -> Void)? = nil
        /// Minimum seconds between cache writes. The resident app keeps the
        /// cache in memory and flushes on quit, so rewriting ~100 MB of history
        /// every minute bought nothing; one-shot callers keep 0 (always write).
        var cacheSaveInterval: TimeInterval = 0

        static func live(now: Date = Date()) -> Deps {
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            return Deps(
                home: FileManager.default.homeDirectoryForCurrentUser,
                now: now,
                timeZone: .current,
                cacheURL: root
                    .appendingPathComponent("CapacityDock", isDirectory: true)
                    .appendingPathComponent("token-log-cache.json"),
                cacheSaveInterval: 600
            )
        }
    }

    static func load(
        period: TokenConsumptionPeriod,
        deps: Deps = .live()
    ) -> TokenConsumptionSnapshot {
        var cache = TokenLogDayCache.load(from: deps.cacheURL)
        return load(period: period, deps: deps, cache: &cache)
    }

    /// Like CodeBurn's codex-cache memCaches: a resident caller loads the file
    /// cache once and reuses its fingerprints across period changes.
    static func load(period: TokenConsumptionPeriod, deps: Deps, cache: inout TokenLogDayCache, window customWindow: TokenConsumptionWindow? = nil) -> TokenConsumptionSnapshot {
        let window = customWindow ?? TokenConsumptionClock.window(for: period, now: deps.now, timeZone: deps.timeZone)
        var events: [TokenConsumptionEvent] = []
        var availability: [String: TokenLogAvailability] = [:]
        var scannedAnyLog = false

        for id in TokenConsumptionAggregator.ledgerProviderIDs {
            switch id {
            case "claude":
                let result = scanClaude(window: window, deps: deps, cache: &cache)
                events.append(contentsOf: result.events)
                availability[id] = result.availability
                scannedAnyLog = scannedAnyLog || result.sawLogFile
            case "codex":
                let result = scanCodex(window: window, deps: deps, cache: &cache)
                events.append(contentsOf: result.events)
                availability[id] = result.availability
                scannedAnyLog = scannedAnyLog || result.sawLogFile
            case "grok":
                let result = scanGrok(window: window, deps: deps, cache: &cache)
                events.append(contentsOf: result.events)
                availability[id] = result.availability
                scannedAnyLog = scannedAnyLog || result.sawLogFile
            case "cursor":
                let result = scanCursor(window: window, deps: deps, cache: &cache)
                events.append(contentsOf: result.events)
                availability[id] = result.availability
                scannedAnyLog = scannedAnyLog || result.sawLogFile
            case "cursor-agent":
                let result = scanCursorAgent(window: window, deps: deps, cache: &cache)
                events.append(contentsOf: result.events)
                availability[id] = result.availability
                scannedAnyLog = scannedAnyLog || result.sawLogFile
            default:
                availability[id] = .noLocalTokenLog
            }
        }

        cache.saveIfDue(to: deps.cacheURL, interval: deps.cacheSaveInterval)
        return TokenConsumptionAggregator.snapshot(
            period: period,
            window: window,
            events: events,
            availability: availability,
            scannedAnyLog: scannedAnyLog,
            timeZone: deps.timeZone
        )
    }

    fileprivate struct ScanResult {
        var events: [TokenConsumptionEvent]
        var availability: TokenLogAvailability
        var sawLogFile: Bool
    }
}

extension LocalTokenLogReader {
    /// Per-file Codex parser state. Kept between scans so a growing rollout
    /// resumes from its last line instead of being reparsed from the start.
    struct CodexParseState: Sendable, Equatable {
        var model: String?
        var sessionID: String
        var forkCutoff: String?
        var prevCumulative: Int?
        var prevInput = 0
        var prevCached = 0
        var prevCacheWrite = 0
        var prevOutput = 0
        var prevReasoning = 0
        var seenKeys = Set<String>()
    }
}

enum TokenLogLineParser {
    static func claudeEvent(from line: String) -> TokenConsumptionEvent? {
        guard line.contains("\"usage\""), let data = line.data(using: .utf8),
              let row = try? JSONDecoder().decode(ClaudeLine.self, from: data),
              row.type == "assistant",
              let usage = row.message?.usage,
              let model = row.message?.model, !model.isEmpty,
              let date = TokenConsumptionClock.parseTimestamp(row.timestamp)
        else { return nil }
        let totals = TokenUsageTotals(
            input: max(usage.input_tokens ?? 0, 0),
            output: max(usage.output_tokens ?? 0, 0),
            cacheRead: max(usage.cache_read_input_tokens ?? 0, 0),
            cacheWrite: max(usage.cache_creation_input_tokens ?? 0, 0),
            reasoning: 0,
            outputIncludesReasoning: false
        )
        guard totals.tokenCount > 0 else { return nil }
        return TokenConsumptionEvent(
            providerID: "claude",
            date: date,
            model: model,
            totals: totals
        )
    }

    static func codexRecord(from line: String) -> CodexRecord? {
        guard let data = line.data(using: .utf8),
              let row = try? JSONDecoder().decode(CodexLine.self, from: data)
        else { return nil }
        if row.type == "session_meta" {
            return .sessionMeta(
                model: nonempty(row.payload?.model),
                sessionID: nonempty(row.payload?.session_id),
                forkedFrom: nonempty(row.payload?.forked_from_id),
                timestamp: row.timestamp
            )
        }
        if row.type == "turn_context", let model = nonempty(row.payload?.model) {
            return .model(model)
        }
        if row.payload?.type == "model", let model = nonempty(row.payload?.model) {
            return .model(model)
        }
        guard row.type == "event_msg",
              row.payload?.type == "token_count",
              let date = TokenConsumptionClock.parseTimestamp(row.timestamp)
        else { return nil }
        let last = row.payload?.info?.last_token_usage
        let total = row.payload?.info?.total_token_usage
        let eventModel = nonempty(row.payload?.model)
            ?? nonempty(row.payload?.info?.model)
            ?? nonempty(row.payload?.info?.model_name)
        return .token(
            date: date,
            last: last.map(usageFrom),
            total: total.map(usageFrom),
            cumulativeTotal: total?.total_tokens ?? 0,
            model: eventModel,
            timestamp: row.timestamp
        )
    }

    enum CodexRecord {
        case sessionMeta(model: String?, sessionID: String?, forkedFrom: String?, timestamp: String?)
        case model(String)
        case token(
            date: Date,
            last: CodexUsage?,
            total: CodexUsage?,
            cumulativeTotal: Int,
            model: String?,
            timestamp: String?
        )
    }

    struct CodexUsage: Equatable {
        var input: Int
        var cached: Int
        var cacheWrite: Int
        var output: Int
        var reasoning: Int
        var totalTokens: Int
    }

    private static func usageFrom(_ usage: CodexLine.Usage) -> CodexUsage {
        CodexUsage(
            input: max(usage.input_tokens ?? 0, 0),
            cached: max(usage.cached_input_tokens ?? 0, 0),
            cacheWrite: max(usage.cache_write_input_tokens ?? 0, 0),
            output: max(usage.output_tokens ?? 0, 0),
            reasoning: max(usage.reasoning_output_tokens ?? 0, 0),
            totalTokens: max(usage.total_tokens ?? 0, 0)
        )
    }

    private static func nonempty(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        return raw
    }

    fileprivate struct ClaudeLine: Decodable {
        var type: String?
        var timestamp: String?
        var message: Message?
        struct Message: Decodable {
            var model: String?
            var usage: Usage?
        }
        struct Usage: Decodable {
            var input_tokens: Int?
            var output_tokens: Int?
            var cache_read_input_tokens: Int?
            var cache_creation_input_tokens: Int?
        }
    }

    fileprivate struct CodexLine: Decodable {
        var timestamp: String?
        var type: String?
        var payload: Payload?
        struct Payload: Decodable {
            var type: String?
            var model: String?
            var session_id: String?
            var forked_from_id: String?
            var info: Info?
        }
        struct Info: Decodable {
            var model: String?
            var model_name: String?
            var last_token_usage: Usage?
            var total_token_usage: Usage?
        }
        struct Usage: Decodable {
            var input_tokens: Int?
            var cached_input_tokens: Int?
            var output_tokens: Int?
            var reasoning_output_tokens: Int?
            var cache_write_input_tokens: Int?
            var total_tokens: Int?
        }
    }
}

private extension LocalTokenLogReader {
    static func scanClaude(
        window: TokenConsumptionWindow,
        deps: Deps,
        cache: inout TokenLogDayCache
    ) -> ScanResult {
        let root = deps.home.appendingPathComponent(".claude/projects", isDirectory: true)
        let files = jsonlFiles(under: root, modifiedSince: window.start.addingTimeInterval(-2 * 24 * 3600))
        let sawAny = directoryHasJSONL(root)
        guard sawAny else {
            return ScanResult(events: [], availability: .noLocalTokenLog, sawLogFile: false)
        }
        var events: [TokenConsumptionEvent] = []
        for file in files {
            events.append(contentsOf: incrementalParse(
                file: file, providerID: "claude", window: window, cache: &cache,
                initial: TokenLogDayCache.ParserState.none
            ) { bytes, _ in
                // Only assistant turns carry usage; skip the rest before
                // building a String or running the JSON decoder.
                guard JSONLStreamer.contains(bytes, "\"usage\""),
                      JSONLStreamer.contains(bytes, "\"assistant\"") else { return nil }
                return TokenLogLineParser.claudeEvent(from: JSONLStreamer.string(bytes))
            })
        }
        return ScanResult(events: events, availability: .logged, sawLogFile: true)
    }

    static func scanGrok(
        window: TokenConsumptionWindow,
        deps: Deps,
        cache: inout TokenLogDayCache
    ) -> ScanResult {
        let result = CodeBurnGrokReader.scan(window: window, home: deps.home, cache: &cache)
        return ScanResult(
            events: result.events,
            availability: result.sawLog ? .logged : .noLocalTokenLog,
            sawLogFile: result.sawLog
        )
    }

    static func scanCursor(
        window: TokenConsumptionWindow,
        deps: Deps,
        cache: inout TokenLogDayCache
    ) -> ScanResult {
        let result = CodeBurnCursorBill.scanCursor(window: window, home: deps.home, cache: &cache)
        return ScanResult(events: result.events, availability: result.availability, sawLogFile: result.sawLog)
    }

    static func scanCursorAgent(
        window: TokenConsumptionWindow,
        deps: Deps,
        cache: inout TokenLogDayCache
    ) -> ScanResult {
        let result = CodeBurnCursorBill.scanCursorAgent(window: window, home: deps.home, cache: &cache)
        return ScanResult(
            events: result.events,
            availability: result.sawLog ? .logged : .noLocalTokenLog,
            sawLogFile: result.sawLog
        )
    }

    static func scanCodex(
        window: TokenConsumptionWindow,
        deps: Deps,
        cache: inout TokenLogDayCache
    ) -> ScanResult {
        let files = codexRolloutFiles(home: deps.home, window: window)
        guard !files.isEmpty || directoryHasJSONL(deps.home.appendingPathComponent(".codex/sessions", isDirectory: true))
                || directoryHasJSONL(deps.home.appendingPathComponent(".codex/archived_sessions", isDirectory: true))
        else {
            return ScanResult(events: [], availability: .noLocalTokenLog, sawLogFile: false)
        }
        let sawAny = directoryHasJSONL(deps.home.appendingPathComponent(".codex/sessions", isDirectory: true))
            || directoryHasJSONL(deps.home.appendingPathComponent(".codex/archived_sessions", isDirectory: true))
        var events: [TokenConsumptionEvent] = []
        for (index, file) in files.enumerated() {
            deps.progress?(index, files.count)
            events.append(contentsOf: parseCodexFile(file, window: window, deps: deps, cache: &cache))
        }
        deps.progress?(files.count, files.count)
        return ScanResult(events: events, availability: sawAny ? .logged : .noLocalTokenLog, sawLogFile: sawAny)
    }

    static func parseCodexFile(
        _ file: URL,
        window: TokenConsumptionWindow,
        deps: Deps,
        cache: inout TokenLogDayCache
    ) -> [TokenConsumptionEvent] {
        incrementalParse(
            file: file, providerID: "codex", window: window, cache: &cache,
            initial: .codex(CodexParseState(sessionID: file.deletingPathExtension().lastPathComponent))
        ) { bytes, state in
            // These are ASCII JSON keys; searching the raw bytes skips the
            // large transcript lines without decoding them.
            guard JSONLStreamer.contains(bytes, "token_count") || JSONLStreamer.contains(bytes, "session_meta")
                    || JSONLStreamer.contains(bytes, "turn_context"),
                  case .codex(var codex) = state else { return nil }
            let event = consumeCodexLine(JSONLStreamer.string(bytes), state: &codex)
            state = .codex(codex)
            return event
        }
    }

    static func consumeCodexLine(_ line: String, state: inout CodexParseState) -> TokenConsumptionEvent? {
        switch TokenLogLineParser.codexRecord(from: line) {
        case .sessionMeta(let name, let id, let forkedFrom, let timestamp):
            if let name { state.model = name }
            if let id { state.sessionID = id }
            if let forkedFrom, !forkedFrom.isEmpty, let timestamp,
               let base = TokenConsumptionClock.parseTimestamp(timestamp) {
                state.forkCutoff = ISO8601DateFormatter().string(from: base.addingTimeInterval(5))
            }
            return nil
        case .model(let name):
            state.model = name
            return nil
        case .token(let date, let last, let total, let cumulativeTotal, let eventModel, let timestamp):
            if let forkCutoff = state.forkCutoff, let timestamp, timestamp < forkCutoff { return nil }
            if let prevCumulative = state.prevCumulative, cumulativeTotal == prevCumulative { return nil }
            state.prevCumulative = cumulativeTotal
            var inputTokens = 0
            var cached = 0
            var cacheWrite = 0
            var output = 0
            var reasoning = 0
            if let last {
                inputTokens = last.input
                cached = last.cached
                cacheWrite = last.cacheWrite
                output = last.output
                reasoning = last.reasoning
            } else if cumulativeTotal > 0, let total {
                inputTokens = total.input - state.prevInput
                cached = total.cached - state.prevCached
                cacheWrite = total.cacheWrite - state.prevCacheWrite
                output = total.output - state.prevOutput
                reasoning = total.reasoning - state.prevReasoning
            }
            if let total {
                state.prevInput = total.input
                state.prevCached = total.cached
                state.prevCacheWrite = total.cacheWrite
                state.prevOutput = total.output
                state.prevReasoning = total.reasoning
            }
            guard inputTokens + cached + output + reasoning > 0 else { return nil }
            let uncached = max(0, inputTokens - cached)
            let writeClamped = max(0, min(cacheWrite, uncached))
            let resolved = eventModel ?? state.model ?? "gpt-5"
            let billedWrite = writeClamped > 0
                && (CodeBurnPricing.getModelCosts(resolved)?.cacheWriteCostIsExplicit == true)
                ? writeClamped : 0
            let billedInput = uncached - billedWrite
            let dedup = "codex:\(state.sessionID):\(cumulativeTotal):\(total?.input ?? 0):\(total?.cached ?? 0):\(total?.output ?? 0):\(total?.reasoning ?? 0)"
            if !state.seenKeys.insert(dedup).inserted { return nil }
            return TokenConsumptionEvent(
                providerID: "codex",
                date: date,
                model: resolved,
                totals: TokenUsageTotals(
                    input: billedInput,
                    output: output,
                    cacheRead: cached,
                    cacheWrite: billedWrite,
                    reasoning: reasoning,
                    outputIncludesReasoning: true
                )
            )
        case .none:
            return nil
        }
    }

    /// Parses a JSONL log, resuming from the last complete line when the file
    /// has only grown since the previous scan in this process. A trailing line
    /// without its newline is still being written: it is parsed on a copy of
    /// the state so it counts now, and read again once complete.
    static func incrementalParse(
        file: URL,
        providerID: String,
        window: TokenConsumptionWindow,
        cache: inout TokenLogDayCache,
        initial: TokenLogDayCache.ParserState,
        parseLine: (UnsafeRawBufferPointer, inout TokenLogDayCache.ParserState) -> TokenConsumptionEvent?
    ) -> [TokenConsumptionEvent] {
        let fingerprint = TokenLogDayCache.fingerprint(of: file)
        if let cached = cache.events(for: file, fingerprint: fingerprint, providerID: providerID, window: window) {
            return cached
        }
        let identity = TokenLogDayCache.FileIdentity(of: file)
        var state = initial
        var complete: [TokenConsumptionEvent] = []
        var offset: UInt64 = 0
        if let tail = cache.tails[file.path], let identity, tail.identity == identity,
           UInt64(fingerprint.size) >= tail.consumed,
           let previous = cache.allEvents(for: file), previous.count >= tail.completeEventCount,
           JSONLStreamer.prefixDigest(of: file, upTo: tail.consumed) == tail.prefixDigest {
            state = tail.state
            complete = Array(previous.prefix(tail.completeEventCount))
            offset = tail.consumed
        }
        let result = JSONLStreamer.forEachLineBytes(at: file, from: offset) { bytes in
            if let event = parseLine(bytes, &state) { complete.append(event) }
        }
        var all = complete
        if let trailing = result.trailing {
            var provisional = state
            trailing.withUnsafeBytes { bytes in
                if let event = parseLine(bytes, &provisional) { all.append(event) }
            }
        }
        cache.store(file: file, fingerprint: fingerprint, events: all)
        if let identity, let digest = JSONLStreamer.prefixDigest(of: file, upTo: result.consumed) {
            cache.tails[file.path] = TokenLogDayCache.TailState(
                identity: identity,
                consumed: result.consumed,
                prefixDigest: digest,
                completeEventCount: complete.count,
                state: state
            )
        } else {
            cache.tails[file.path] = nil
        }
        return all.filter { window.contains($0.date) }
    }

    static func directoryHasJSONL(_ root: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return FileManager.default.fileExists(atPath: root.path) && root.pathExtension == "jsonl" }
        while let url = enumerator.nextObject() as? URL {
            if url.pathExtension == "jsonl" { return true }
        }
        return false
    }

    static func jsonlFiles(under root: URL, modifiedSince: Date) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "jsonl" else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            if let modified = values?.contentModificationDate, modified < modifiedSince {
                continue
            }
            files.append(url)
        }
        return files
    }

    static func codexRolloutFiles(home: URL, window: TokenConsumptionWindow) -> [URL] {
        let sessions = home.appendingPathComponent(".codex/sessions", isDirectory: true)
        let archived = home.appendingPathComponent(".codex/archived_sessions", isDirectory: true)
        var seen = Set<String>()
        var files: [URL] = []
        for file in datedCodexFiles(in: sessions, window: window)
            + flatCodexFiles(in: archived, window: window)
        {
            let name = file.lastPathComponent
            guard name.hasPrefix("rollout-"), name.hasSuffix(".jsonl") else { continue }
            if seen.contains(name) { continue }
            seen.insert(name)
            files.append(file)
        }
        return files
    }

    static func datedCodexFiles(in root: URL, window: TokenConsumptionWindow) -> [URL] {
        jsonlFiles(under: root, modifiedSince: window.start).filter {
            $0.lastPathComponent.hasPrefix("rollout-")
        }
    }

    static func flatCodexFiles(in root: URL, window: TokenConsumptionWindow) -> [URL] {
        guard let listed = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return listed.filter { file in
            guard file.lastPathComponent.hasPrefix("rollout-"), file.pathExtension == "jsonl" else {
                return false
            }
            let values = try? file.resourceValues(forKeys: [.contentModificationDateKey])
            if let modified = values?.contentModificationDate, modified < window.start {
                return false
            }
            return true
        }
    }
}

/// Streaming JSONL reader. Does not load the whole file; skips oversized lines.
enum JSONLStreamer {
    static let maxLineBytes = 1_048_576
    private static let chunkBytes = 256 * 1024

    static func forEachLine(at url: URL, body: (String) -> Void) {
        let result = forEachLineBytes(at: url) { body(string($0)) }
        if let trailing = result.trailing {
            trailing.withUnsafeBytes { body(string($0)) }
        }
    }

    /// Streams complete lines (trimmed, starting with `{`) from `offset`.
    /// Returns the offset just past the last newline read, and the trailing
    /// bytes of a final line that has no newline yet.
    @discardableResult
    static func forEachLineBytes(
        at url: URL,
        from offset: UInt64 = 0,
        body: (UnsafeRawBufferPointer) -> Void
    ) -> (consumed: UInt64, trailing: Data?) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return (offset, nil) }
        defer { try? handle.close() }
        if offset > 0 {
            do { try handle.seek(toOffset: offset) } catch { return (offset, nil) }
        }
        var leftover = Data()
        var leftoverStart = offset
        var discardingOversizedLine = false
        // Foundation bridges each chunk through autoreleased objects. Without
        // a per-chunk pool a long scan retains every consumed chunk.
        while autoreleasepool(invoking: { () -> Bool in
            let chunk = handle.readData(ofLength: chunkBytes)
            if chunk.isEmpty { return false }
            leftover.append(chunk)
            var cursor = 0
            leftover.withUnsafeBytes { buffer in
                guard let base = buffer.baseAddress else { return }
                while cursor < buffer.count,
                      let newline = memchr(base.advanced(by: cursor), 0x0A, buffer.count - cursor) {
                    let end = base.distance(to: newline)
                    if !discardingOversizedLine, end - cursor <= maxLineBytes {
                        emit(UnsafeRawBufferPointer(rebasing: buffer[cursor..<end]), body: body)
                    }
                    discardingOversizedLine = false
                    cursor = end + 1
                }
            }
            // Compact once per chunk, not once per line (quadratic byte copying).
            leftover.removeSubrange(leftover.startIndex..<(leftover.startIndex + cursor))
            leftoverStart += UInt64(cursor)
            if leftover.count > maxLineBytes {
                leftoverStart += UInt64(leftover.count)
                leftover.removeAll(keepingCapacity: true)
                discardingOversizedLine = true
            }
            return true
        }) {}
        if discardingOversizedLine || leftover.isEmpty { return (leftoverStart, nil) }
        return (leftoverStart, leftover)
    }

    private static func emit(_ line: UnsafeRawBufferPointer, body: (UnsafeRawBufferPointer) -> Void) {
        var start = 0
        var end = line.count
        func isSpace(_ byte: UInt8) -> Bool { byte == 0x20 || byte == 0x09 || byte == 0x0D || byte == 0x0A }
        while start < end, isSpace(line[start]) { start += 1 }
        while end > start, isSpace(line[end - 1]) { end -= 1 }
        guard start < end, line[start] == UInt8(ascii: "{") else { return }
        body(UnsafeRawBufferPointer(rebasing: line[start..<end]))
    }

    static func contains(_ bytes: UnsafeRawBufferPointer, _ needle: StaticString) -> Bool {
        guard let base = bytes.baseAddress, bytes.count >= needle.utf8CodeUnitCount else { return false }
        return memmem(base, bytes.count, needle.utf8Start, needle.utf8CodeUnitCount) != nil
    }

    static func string(_ bytes: UnsafeRawBufferPointer) -> String {
        String(decoding: bytes, as: UTF8.self)
    }

    /// FNV-1a over the first and last 4 KB of `[0, end)`, used to confirm a
    /// resume point: the file was appended to, not truncated or rewritten in
    /// place. A rewrite that keeps both ends of the consumed region
    /// byte-identical is not worth rereading every log to catch.
    static func prefixDigest(of url: URL, upTo end: UInt64) -> UInt64? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let sample: UInt64 = 4096
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        func mix(from start: UInt64, length: UInt64) -> Bool {
            guard length > 0 else { return true }
            guard (try? handle.seek(toOffset: start)) != nil else { return false }
            let bytes = handle.readData(ofLength: Int(length))
            guard bytes.count == Int(length) else { return false }
            for byte in bytes { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }
            return true
        }
        let headLength = min(end, sample)
        let tailStart = max(headLength, end > sample ? end - sample : 0)
        guard mix(from: 0, length: headLength), mix(from: tailStart, length: end - tailStart) else { return nil }
        return hash
    }
}

/// Daily event cache so week/month does not reread unchanged JSONL.
/// Stores only provider, time, model, and token counts — never session text.
struct TokenLogDayCache: Codable, Sendable {
    // 6: events are compact arrays and drop the derived day key. Version 5
    // files hold the same data in keyed form and are still read.
    var version = 6
    static let readableVersions: Set<Int> = [5, 6]
    static let readLimit = 128 * 1024 * 1024
    var files: [String: FileEntry] = [:] { didSet { needsSave = true } }
    /// In-memory resume points for growing logs; never written to disk. After
    /// a relaunch a changed file is parsed once from the start.
    var tails: [String: TailState] = [:]
    private var needsSave = false
    private var lastSavedAt: Date?
    private enum CodingKeys: String, CodingKey { case version, files }

    struct FileEntry: Equatable, Codable, Sendable {
        var size: Int
        var mtime: TimeInterval
        var events: [StoredEvent]
    }

    struct StoredEvent: Equatable, Codable, Sendable {
        var providerID: String
        var timestamp: TimeInterval
        var model: String?
        var input: Int
        var output: Int
        var cacheRead: Int
        var cacheWrite: Int
        var reasoning: Int
        var outputIncludesReasoning: Bool

        init(providerID: String, timestamp: TimeInterval, model: String?, input: Int, output: Int,
             cacheRead: Int, cacheWrite: Int, reasoning: Int, outputIncludesReasoning: Bool) {
            self.providerID = providerID
            self.timestamp = timestamp
            self.model = model
            self.input = input
            self.output = output
            self.cacheRead = cacheRead
            self.cacheWrite = cacheWrite
            self.reasoning = reasoning
            self.outputIncludesReasoning = outputIncludesReasoning
        }

        private enum LegacyKeys: String, CodingKey {
            case providerID, timestamp, model, input, output, cacheRead, cacheWrite, reasoning, outputIncludesReasoning
        }

        /// v6 array: [provider, timestamp, model|null, input, output, cacheRead, cacheWrite, reasoning, 0|1].
        init(from decoder: Decoder) throws {
            if var row = try? decoder.unkeyedContainer() {
                providerID = try row.decode(String.self)
                timestamp = try row.decode(TimeInterval.self)
                model = try row.decodeIfPresent(String.self)
                input = try row.decode(Int.self)
                output = try row.decode(Int.self)
                cacheRead = try row.decode(Int.self)
                cacheWrite = try row.decode(Int.self)
                reasoning = try row.decode(Int.self)
                outputIncludesReasoning = try row.decode(Int.self) != 0
                return
            }
            let keyed = try decoder.container(keyedBy: LegacyKeys.self)
            providerID = try keyed.decode(String.self, forKey: .providerID)
            timestamp = try keyed.decode(TimeInterval.self, forKey: .timestamp)
            model = try keyed.decodeIfPresent(String.self, forKey: .model)
            input = try keyed.decode(Int.self, forKey: .input)
            output = try keyed.decode(Int.self, forKey: .output)
            cacheRead = try keyed.decode(Int.self, forKey: .cacheRead)
            cacheWrite = try keyed.decode(Int.self, forKey: .cacheWrite)
            reasoning = try keyed.decode(Int.self, forKey: .reasoning)
            outputIncludesReasoning = try keyed.decode(Bool.self, forKey: .outputIncludesReasoning)
        }

        func encode(to encoder: Encoder) throws {
            var row = encoder.unkeyedContainer()
            try row.encode(providerID)
            try row.encode(timestamp)
            if let model { try row.encode(model) } else { try row.encodeNil() }
            try row.encode(input)
            try row.encode(output)
            try row.encode(cacheRead)
            try row.encode(cacheWrite)
            try row.encode(reasoning)
            try row.encode(outputIncludesReasoning ? 1 : 0)
        }
    }

    struct Fingerprint: Equatable {
        var size: Int
        var mtime: TimeInterval
    }

    /// Device + inode: a log replaced by a new file must not be resumed.
    struct FileIdentity: Equatable, Sendable {
        var device: UInt64
        var inode: UInt64

        init?(of url: URL) {
            var info = stat()
            guard stat(url.path, &info) == 0 else { return nil }
            device = UInt64(bitPattern: Int64(info.st_dev))
            inode = UInt64(info.st_ino)
        }
    }

    enum ParserState: Sendable, Equatable {
        case none
        case codex(LocalTokenLogReader.CodexParseState)
    }

    struct TailState: Sendable, Equatable {
        var identity: FileIdentity
        var consumed: UInt64
        var prefixDigest: UInt64
        var completeEventCount: Int
        var state: ParserState
    }

    static func fingerprint(of url: URL) -> Fingerprint {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return Fingerprint(
            size: values?.fileSize ?? 0,
            mtime: values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        )
    }

    static func load(from url: URL?, now: Date = Date()) -> TokenLogDayCache {
        guard let url,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? SafeFile.read(from: url.path, maxBytes: Self.readLimit),
              var decoded = try? JSONDecoder().decode(TokenLogDayCache.self, from: data),
              readableVersions.contains(decoded.version)
        else { return TokenLogDayCache() }
        // A v5 file is rewritten in the compact form on the next save.
        decoded.needsSave = decoded.version != 6
        decoded.version = 6
        decoded.lastSavedAt = now
        return decoded
    }

    /// Writes when there are pending changes and `interval` has passed since
    /// the last write (or load). `interval` 0 writes every time.
    mutating func saveIfDue(to url: URL?, interval: TimeInterval, now: Date = Date()) {
        if interval > 0, let lastSavedAt, now.timeIntervalSince(lastSavedAt) < interval { return }
        save(to: url, now: now)
    }

    mutating func save(to url: URL?, now: Date = Date()) {
        guard needsSave, let url else { return }
        do {
            try SafeFile.write(encoded(), to: url.path)
            needsSave = false
            lastSavedAt = now
        } catch {
            return
        }
    }

    /// Hand-written JSON: JSONEncoder spent seconds per write boxing ~500k
    /// events. Numbers and escaped strings go straight into one buffer.
    func encoded() -> Data {
        var out = [UInt8]()
        out.reserveCapacity(files.count * 256)
        func append(_ text: String) { out.append(contentsOf: text.utf8) }
        func appendString(_ value: String) {
            out.append(0x22)
            for byte in value.utf8 {
                switch byte {
                case 0x22: out.append(contentsOf: [0x5C, 0x22])
                case 0x5C: out.append(contentsOf: [0x5C, 0x5C])
                case 0x0A: out.append(contentsOf: [0x5C, 0x6E])
                case 0x0D: out.append(contentsOf: [0x5C, 0x72])
                case 0x09: out.append(contentsOf: [0x5C, 0x74])
                case 0..<0x20: append(String(format: "\\u%04x", byte))
                default: out.append(byte)
                }
            }
            out.append(0x22)
        }
        append("{\"version\":\(version),\"files\":{")
        var firstFile = true
        for (path, entry) in files {
            if !firstFile { out.append(0x2C) }
            firstFile = false
            appendString(path)
            append(":{\"size\":\(entry.size),\"mtime\":\(entry.mtime),\"events\":[")
            for (index, event) in entry.events.enumerated() {
                if index > 0 { out.append(0x2C) }
                out.append(0x5B)
                appendString(event.providerID)
                append(",\(event.timestamp),")
                if let model = event.model { appendString(model) } else { append("null") }
                append(",\(event.input),\(event.output),\(event.cacheRead),\(event.cacheWrite),\(event.reasoning),\(event.outputIncludesReasoning ? 1 : 0)]")
            }
            append("]}")
        }
        append("}}")
        return Data(out)
    }

    func events(for file: URL, fingerprint: Fingerprint, providerID: String, window: TokenConsumptionWindow? = nil) -> [TokenConsumptionEvent]? {
        guard let entry = files[file.path],
              entry.size == fingerprint.size,
              entry.mtime == fingerprint.mtime
        else { return nil }
        return entry.events.compactMap { stored in
            guard stored.providerID == providerID else { return nil }
            if let window,
               (stored.timestamp < window.start.timeIntervalSince1970 || stored.timestamp > window.end.timeIntervalSince1970) {
                return nil
            }
            return stored.event
        }
    }

    /// Every stored event for a file regardless of fingerprint, for resuming.
    func allEvents(for file: URL) -> [TokenConsumptionEvent]? {
        files[file.path]?.events.map(\.event)
    }

    mutating func store(file: URL, fingerprint: Fingerprint, events: [TokenConsumptionEvent]) {
        files[file.path] = FileEntry(
            size: fingerprint.size,
            mtime: fingerprint.mtime,
            events: events.map { event in
                StoredEvent(
                    providerID: event.providerID,
                    timestamp: event.date.timeIntervalSince1970,
                    model: event.model,
                    input: event.totals.input,
                    output: event.totals.output,
                    cacheRead: event.totals.cacheRead,
                    cacheWrite: event.totals.cacheWrite,
                    reasoning: event.totals.reasoning,
                    outputIncludesReasoning: event.totals.outputIncludesReasoning
                )
            }
        )
    }
}

extension TokenLogDayCache: Equatable {
    /// Persisted content only; resume points and save bookkeeping are transient.
    static func == (lhs: TokenLogDayCache, rhs: TokenLogDayCache) -> Bool {
        lhs.version == rhs.version && lhs.files == rhs.files
    }
}

private extension TokenLogDayCache.StoredEvent {
    var event: TokenConsumptionEvent {
        TokenConsumptionEvent(
            providerID: providerID,
            date: Date(timeIntervalSince1970: timestamp),
            model: model,
            totals: TokenUsageTotals(
                input: input,
                output: output,
                cacheRead: cacheRead,
                cacheWrite: cacheWrite,
                reasoning: reasoning,
                outputIncludesReasoning: outputIncludesReasoning
            )
        )
    }
}
