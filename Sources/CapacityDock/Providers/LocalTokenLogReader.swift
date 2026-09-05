import Foundation

/// Read-only local JSONL token logs. Quota percentages are not a source.
enum LocalTokenLogReader {
    static let parsedProviderIDs: Set<String> = ["claude", "codex", "grok", "cursor", "cursor-agent"]

    struct Deps: Sendable {
        var home: URL
        var now: Date
        var timeZone: TimeZone
        var cacheURL: URL?

        static func live(now: Date = Date()) -> Deps {
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            return Deps(
                home: FileManager.default.homeDirectoryForCurrentUser,
                now: now,
                timeZone: .current,
                cacheURL: root
                    .appendingPathComponent("CapacityDock", isDirectory: true)
                    .appendingPathComponent("token-log-cache.json")
            )
        }
    }

    static func load(
        period: TokenConsumptionPeriod,
        deps: Deps = .live()
    ) -> TokenConsumptionSnapshot {
        let window = TokenConsumptionClock.window(for: period, now: deps.now, timeZone: deps.timeZone)
        var cache = TokenLogDayCache.load(from: deps.cacheURL)
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

        cache.save(to: deps.cacheURL)
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
            events.append(contentsOf: cachedOrParse(file: file, providerID: "claude", window: window, deps: deps, cache: &cache) { line in
                TokenLogLineParser.claudeEvent(from: line).map { [$0] } ?? []
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
        for file in files {
            events.append(contentsOf: parseCodexFile(file, window: window, deps: deps, cache: &cache))
        }
        return ScanResult(events: events, availability: sawAny ? .logged : .noLocalTokenLog, sawLogFile: sawAny)
    }

    static func parseCodexFile(
        _ file: URL,
        window: TokenConsumptionWindow,
        deps: Deps,
        cache: inout TokenLogDayCache
    ) -> [TokenConsumptionEvent] {
        let fingerprint = TokenLogDayCache.fingerprint(of: file)
        if let cached = cache.events(for: file, fingerprint: fingerprint, providerID: "codex") {
            return cached.filter { window.contains($0.date) }
        }
        var model: String?
        var sessionID = file.deletingPathExtension().lastPathComponent
        var forkCutoff: String?
        var prevCumulative: Int?
        var prevInput = 0
        var prevCached = 0
        var prevCacheWrite = 0
        var prevOutput = 0
        var prevReasoning = 0
        var parsed: [TokenConsumptionEvent] = []
        var seenKeys = Set<String>()
        JSONLStreamer.forEachLine(at: file) { line in
            guard line.contains("token_count")
                    || line.contains("session_meta")
                    || line.contains("turn_context") else { return }
            switch TokenLogLineParser.codexRecord(from: line) {
            case .sessionMeta(let name, let id, let forkedFrom, let timestamp):
                if let name { model = name }
                if let id { sessionID = id }
                if let forkedFrom, !forkedFrom.isEmpty, let timestamp,
                   let base = TokenConsumptionClock.parseTimestamp(timestamp) {
                    forkCutoff = ISO8601DateFormatter().string(from: base.addingTimeInterval(5))
                }
            case .model(let name):
                model = name
            case .token(let date, let last, let total, let cumulativeTotal, let eventModel, let timestamp):
                if let forkCutoff, let timestamp, timestamp < forkCutoff { return }
                if let prevCumulative, cumulativeTotal == prevCumulative { return }
                prevCumulative = cumulativeTotal
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
                    inputTokens = total.input - prevInput
                    cached = total.cached - prevCached
                    cacheWrite = total.cacheWrite - prevCacheWrite
                    output = total.output - prevOutput
                    reasoning = total.reasoning - prevReasoning
                }
                if let total {
                    prevInput = total.input
                    prevCached = total.cached
                    prevCacheWrite = total.cacheWrite
                    prevOutput = total.output
                    prevReasoning = total.reasoning
                }
                guard inputTokens + cached + output + reasoning > 0 else { return }
                let uncached = max(0, inputTokens - cached)
                let writeClamped = max(0, min(cacheWrite, uncached))
                let resolved = eventModel ?? model ?? "gpt-5"
                let billedWrite = writeClamped > 0
                    && (CodeBurnPricing.getModelCosts(resolved)?.cacheWriteCostIsExplicit == true)
                    ? writeClamped : 0
                let billedInput = uncached - billedWrite
                let dedup = "codex:\(sessionID):\(cumulativeTotal):\(total?.input ?? 0):\(total?.cached ?? 0):\(total?.output ?? 0):\(total?.reasoning ?? 0)"
                if !seenKeys.insert(dedup).inserted { return }
                parsed.append(TokenConsumptionEvent(
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
                ))
            case .none:
                break
            }
        }
        cache.store(file: file, fingerprint: fingerprint, events: parsed)
        return parsed.filter { window.contains($0.date) }
    }

    static func cachedOrParse(
        file: URL,
        providerID: String,
        window: TokenConsumptionWindow,
        deps: Deps,
        cache: inout TokenLogDayCache,
        parseLine: (String) -> [TokenConsumptionEvent]
    ) -> [TokenConsumptionEvent] {
        let fingerprint = TokenLogDayCache.fingerprint(of: file)
        if let cached = cache.events(for: file, fingerprint: fingerprint, providerID: providerID) {
            return cached.filter { window.contains($0.date) }
        }
        var parsed: [TokenConsumptionEvent] = []
        JSONLStreamer.forEachLine(at: file) { line in
            parsed.append(contentsOf: parseLine(line))
        }
        cache.store(file: file, fingerprint: fingerprint, events: parsed)
        return parsed.filter { window.contains($0.date) }
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

    static func forEachLine(at url: URL, body: (String) -> Void) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        var leftover = Data()
        while true {
            let chunk = handle.readData(ofLength: 64 * 1024)
            if chunk.isEmpty { break }
            leftover.append(chunk)
            while let range = leftover.range(of: Data([0x0A])) {
                let lineData = leftover.subdata(in: leftover.startIndex..<range.lowerBound)
                leftover.removeSubrange(leftover.startIndex...range.lowerBound)
                emit(lineData, body: body)
            }
            if leftover.count > maxLineBytes {
                leftover.removeAll(keepingCapacity: true)
            }
        }
        if !leftover.isEmpty {
            emit(leftover, body: body)
        }
    }

    private static func emit(_ data: Data, body: (String) -> Void) {
        guard data.count <= maxLineBytes,
              let line = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .ascii)
        else { return }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") else { return }
        body(trimmed)
    }
}

/// Daily event cache so week/month does not reread unchanged JSONL.
/// Stores only provider, day, model, and token counts — never session text.
struct TokenLogDayCache: Equatable, Codable, Sendable {
    var version = 4
    var files: [String: FileEntry] = [:]

    struct FileEntry: Equatable, Codable, Sendable {
        var size: Int
        var mtime: TimeInterval
        var events: [StoredEvent]
    }

    struct StoredEvent: Equatable, Codable, Sendable {
        var providerID: String
        var day: String
        var timestamp: TimeInterval
        var model: String?
        var input: Int
        var output: Int
        var cacheRead: Int
        var cacheWrite: Int
        var reasoning: Int
        var outputIncludesReasoning: Bool
    }

    struct Fingerprint: Equatable {
        var size: Int
        var mtime: TimeInterval
    }

    static func fingerprint(of url: URL) -> Fingerprint {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return Fingerprint(
            size: values?.fileSize ?? 0,
            mtime: values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        )
    }

    static func load(from url: URL?) -> TokenLogDayCache {
        guard let url,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? SafeFile.read(from: url.path, maxBytes: SafeFile.defaultReadLimit),
              let decoded = try? JSONDecoder().decode(TokenLogDayCache.self, from: data),
              decoded.version == 4
        else { return TokenLogDayCache() }
        return decoded
    }

    func save(to url: URL?) {
        guard let url else { return }
        do {
            let data = try JSONEncoder().encode(self)
            try SafeFile.write(data, to: url.path)
        } catch {
            return
        }
    }

    func events(for file: URL, fingerprint: Fingerprint, providerID: String) -> [TokenConsumptionEvent]? {
        guard let entry = files[file.path],
              entry.size == fingerprint.size,
              entry.mtime == fingerprint.mtime
        else { return nil }
        return entry.events.compactMap { stored in
            guard stored.providerID == providerID else { return nil }
            return TokenConsumptionEvent(
                providerID: stored.providerID,
                date: Date(timeIntervalSince1970: stored.timestamp),
                model: stored.model,
                totals: TokenUsageTotals(
                    input: stored.input,
                    output: stored.output,
                    cacheRead: stored.cacheRead,
                    cacheWrite: stored.cacheWrite,
                    reasoning: stored.reasoning,
                    outputIncludesReasoning: stored.outputIncludesReasoning
                )
            )
        }
    }

    mutating func store(file: URL, fingerprint: Fingerprint, events: [TokenConsumptionEvent]) {
        files[file.path] = FileEntry(
            size: fingerprint.size,
            mtime: fingerprint.mtime,
            events: events.map { event in
                StoredEvent(
                    providerID: event.providerID,
                    day: TokenConsumptionClock.dayKey(event.date),
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
