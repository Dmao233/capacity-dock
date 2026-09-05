import Foundation
import SQLite3

/// CodeBurn cursor + cursor-agent bill collectors. Quota rings stay hash-only.
enum CodeBurnCursorBill {
    static let costModelAuto = "claude-sonnet-4-5"
    static let charsPerToken = 4

    static func estimateTokens(chars: Int) -> Int {
        guard chars > 0 else { return 0 }
        return (chars + charsPerToken - 1) / charsPerToken
    }

    static func resolveModel(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty, raw != "default" else { return costModelAuto }
        return raw
    }

    static func displayModel(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty, raw != "default" else { return "cursor-auto" }
        return raw
    }

    static func parseComposerId(from key: String) -> String? {
        guard let first = key.firstIndex(of: ":") else { return nil }
        let afterFirst = key.index(after: first)
        guard let second = key[afterFirst...].firstIndex(of: ":") else { return nil }
        let candidate = String(key[afterFirst..<second])
        guard !candidate.isEmpty,
              candidate.rangeOfCharacter(from: CharacterSet(charactersIn: "\r\n\0")) == nil
        else { return nil }
        return candidate
    }

    static func parseCursorTimestamp(_ raw: Any?) -> Date? {
        if let text = raw as? String {
            if let date = TokenConsumptionClock.parseTimestamp(text) { return date }
            if let ms = Double(text) { return dateFromEpoch(ms) }
            return nil
        }
        if let number = raw as? Double { return dateFromEpoch(number) }
        if let number = raw as? Int { return dateFromEpoch(Double(number)) }
        return nil
    }

    static func scanCursor(
        window: TokenConsumptionWindow,
        home: URL,
        cache: inout TokenLogDayCache
    ) -> (events: [TokenConsumptionEvent], availability: TokenLogAvailability, sawLog: Bool) {
        let dbURL = home
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage", isDirectory: true)
            .appendingPathComponent("state.vscdb")
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            return ([], .cursorHashOnly, false)
        }
        let fingerprint = TokenLogDayCache.fingerprint(of: dbURL)
        if let cached = cache.events(for: dbURL, fingerprint: fingerprint, providerID: "cursor") {
            return (cached.filter { window.contains($0.date) }, .logged, true)
        }
        var events: [TokenConsumptionEvent] = []
        do {
            try CursorDiskKV.open(dbURL) { db in
                events = parseCursorCalls(db: db, window: window)
            }
        } catch {
            return ([], .unreadable, true)
        }
        cache.store(file: dbURL, fingerprint: fingerprint, events: events)
        return (events.filter { window.contains($0.date) }, .logged, true)
    }

    enum InputSource: Equatable {
        case bubbleTokens
        case meter
        case text
    }

    static func inputSource(hasRealTokens: Bool, hasMeter: Bool) -> InputSource {
        if hasRealTokens { return .bubbleTokens }
        if hasMeter { return .meter }
        return .text
    }

    private struct BubbleRow {
        var key: String
        var composerID: String
        var input: Int
        var output: Int
        var model: String?
        var date: Date
        var textLen: Int
        var bubbleType: Int
    }

    private struct ComposerScan {
        var hasRealTokens = false
        var firstBubbleTs: Date?
        var assistantTextChars = 0
        var model: String?
    }

    private struct ComposerMeta {
        var tokens: Int
        var createdAt: Date?
    }

    private static func parseCursorCalls(db: OpaquePointer, window: TokenConsumptionWindow) -> [TokenConsumptionEvent] {
        let bubbles = loadBubbles(db: db, window: window)
        let meters = loadComposerMeta(db: db)
        var scans: [String: ComposerScan] = [:]
        for row in bubbles {
            var scan = scans[row.composerID] ?? ComposerScan()
            if row.input > 0 || row.output > 0 { scan.hasRealTokens = true }
            if row.bubbleType != 1 { scan.assistantTextChars += row.textLen }
            if scan.model == nil, let model = row.model { scan.model = model }
            if scan.firstBubbleTs == nil { scan.firstBubbleTs = row.date }
            scans[row.composerID] = scan
        }

        var events: [TokenConsumptionEvent] = []
        var seen = Set<String>()
        for row in bubbles {
            let scan = scans[row.composerID] ?? ComposerScan()
            let source = inputSource(hasRealTokens: scan.hasRealTokens, hasMeter: meters[row.composerID] != nil)
            var input = row.input
            var output = row.output
            if input == 0, output == 0 {
                if row.bubbleType == 1 {
                    if source == .text, row.textLen > 0 {
                        input = estimateTokens(chars: row.textLen)
                    }
                } else {
                    output = estimateTokens(chars: row.textLen)
                }
            }
            guard input > 0 || output > 0 else { continue }
            let dedup = "cursor:bubble:\(row.key)"
            if !seen.insert(dedup).inserted { continue }
            let model = row.model ?? scan.model
            events.append(TokenConsumptionEvent(
                providerID: "cursor",
                date: row.date,
                model: displayModel(model),
                totals: TokenUsageTotals(input: input, output: output, outputIncludesReasoning: true)
            ))
        }

        for (composerID, scan) in scans {
            let source = inputSource(hasRealTokens: scan.hasRealTokens, hasMeter: meters[composerID] != nil)
            guard source == .meter, let meter = meters[composerID] else { continue }
            let date = meter.createdAt ?? scan.firstBubbleTs
            guard let date else { continue }
            let dedup = "cursor:composer-input:\(composerID)"
            if !seen.insert(dedup).inserted { continue }
            events.append(TokenConsumptionEvent(
                providerID: "cursor",
                date: date,
                model: displayModel(scan.model),
                totals: TokenUsageTotals(input: meter.tokens, output: 0, outputIncludesReasoning: true)
            ))
        }
        return events
    }

    private static func loadBubbles(db: OpaquePointer, window: TokenConsumptionWindow) -> [BubbleRow] {
        let timeFloor = ISO8601DateFormatter().string(from: window.start)
        let floorMs = Int(window.start.timeIntervalSince1970 * 1000)
        let sql = """
        SELECT
          key,
          json_extract(value, '$.tokenCount.inputTokens') as input_tokens,
          json_extract(value, '$.tokenCount.outputTokens') as output_tokens,
          json_extract(value, '$.modelInfo.modelName') as model,
          json_extract(value, '$.createdAt') as created_at,
          length(json_extract(value, '$.text')) as text_length,
          json_extract(value, '$.type') as bubble_type
        FROM cursorDiskKV
        WHERE key LIKE 'bubbleId:%'
          AND json_extract(value, '$.createdAt') IS NOT NULL
          AND (
            json_extract(value, '$.createdAt') > ?
            OR CAST(json_extract(value, '$.createdAt') AS INTEGER) > ?
          )
        """
        var rows: [BubbleRow] = []
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, timeFloor, -1, sqliteTransient)
        sqlite3_bind_int64(statement, 2, sqlite3_int64(floorMs))
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let keyPtr = sqlite3_column_text(statement, 0) else { continue }
            let key = String(cString: keyPtr)
            guard let composerID = parseComposerId(from: key) else { continue }
            let created = columnValue(statement, 4)
            guard let date = parseCursorTimestamp(created), window.contains(date) else { continue }
            rows.append(BubbleRow(
                key: key,
                composerID: composerID,
                input: columnInt(statement, 1),
                output: columnInt(statement, 2),
                model: columnText(statement, 3),
                date: date,
                textLen: columnInt(statement, 5),
                bubbleType: columnInt(statement, 6)
            ))
        }
        return rows
    }

    private static func loadComposerMeta(db: OpaquePointer) -> [String: ComposerMeta] {
        let sql = """
        SELECT
          substr(key, length('composerData:') + 1) as composer_id,
          json_extract(value, '$.promptTokenBreakdown.totalUsedTokens') as used,
          json_extract(value, '$.contextTokensUsed') as ctx,
          json_extract(value, '$.createdAt') as created_at
        FROM cursorDiskKV
        WHERE key >= 'composerData:' AND key < 'composerData;'
        """
        var meters: [String: ComposerMeta] = [:]
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idPtr = sqlite3_column_text(statement, 0) else { continue }
            let composerID = String(cString: idPtr)
            let used = columnInt(statement, 1)
            let ctx = columnInt(statement, 2)
            let tokens = used > 0 ? used : ctx
            guard !composerID.isEmpty, tokens > 0 else { continue }
            meters[composerID] = ComposerMeta(
                tokens: tokens,
                createdAt: parseCursorTimestamp(columnValue(statement, 3))
            )
        }
        return meters
    }

    static func scanCursorAgent(
        window: TokenConsumptionWindow,
        home: URL,
        cache: inout TokenLogDayCache
    ) -> (events: [TokenConsumptionEvent], sawLog: Bool) {
        let projects = home.appendingPathComponent(".cursor/projects", isDirectory: true)
        guard FileManager.default.fileExists(atPath: projects.path) else { return ([], false) }
        var events: [TokenConsumptionEvent] = []
        var saw = false
        for file in transcriptFiles(under: projects) {
            saw = true
            let values = try? file.resourceValues(forKeys: [.contentModificationDateKey])
            if let modified = values?.contentModificationDate, modified < window.start { continue }
            let fingerprint = TokenLogDayCache.fingerprint(of: file)
            if let cached = cache.events(for: file, fingerprint: fingerprint, providerID: "cursor-agent") {
                events.append(contentsOf: cached.filter { window.contains($0.date) })
                continue
            }
            let date = values?.contentModificationDate ?? Date()
            let parsed = parseTranscriptFile(file)
            let stored = parsed.enumerated().compactMap { index, turn -> TokenConsumptionEvent? in
                let input = estimateTokens(chars: turn.user.count)
                let output = estimateTokens(chars: turn.body.count)
                let reasoning = estimateTokens(chars: turn.reasoning.count)
                guard input > 0 || output > 0 || reasoning > 0 else { return nil }
                return TokenConsumptionEvent(
                    providerID: "cursor-agent",
                    date: date,
                    model: "cursor-agent-auto",
                    totals: TokenUsageTotals(
                        input: input,
                        output: output,
                        reasoning: reasoning,
                        outputIncludesReasoning: false
                    )
                )
            }
            cache.store(file: file, fingerprint: fingerprint, events: stored)
            events.append(contentsOf: stored.filter { window.contains($0.date) })
        }
        return (events, saw)
    }

    struct AgentTurn {
        var user: String
        var body: String
        var reasoning: String
    }

    static func parseJsonlTranscript(_ raw: String) -> [AgentTurn] {
        var turns: [AgentTurn] = []
        var currentUser = ""
        raw.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }
            let role = root["role"] as? String
            let content = ((root["message"] as? [String: Any])?["content"]) as? [[String: Any]] ?? []
            if role == "user" {
                let texts = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
                let combined = texts.joined(separator: " ")
                currentUser = extractUserQuery(combined)
                if currentUser.isEmpty { currentUser = String(combined.prefix(500)) }
                return
            }
            if role == "assistant", !currentUser.isEmpty {
                let body = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                turns.append(AgentTurn(user: currentUser, body: body, reasoning: ""))
                currentUser = ""
            }
        }
        return turns
    }

    static func extractUserQuery(_ block: String) -> String {
        let open = "<user_query>"
        let close = "</user_query>"
        var chunks: [String] = []
        var cursor = block.startIndex
        while let openRange = block.range(of: open, range: cursor..<block.endIndex) {
            let start = openRange.upperBound
            if let closeRange = block.range(of: close, range: start..<block.endIndex) {
                chunks.append(block[start..<closeRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines))
                cursor = closeRange.upperBound
            } else {
                chunks.append(block[start...].trimmingCharacters(in: .whitespacesAndNewlines))
                break
            }
        }
        return String(chunks.filter { !$0.isEmpty }.joined(separator: " ").replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).prefix(500))
    }

    private static func parseTranscriptFile(_ file: URL) -> [AgentTurn] {
        if file.pathExtension == "jsonl" {
            var text = ""
            JSONLStreamer.forEachLine(at: file) { line in
                text.append(line)
                text.append("\n")
            }
            return parseJsonlTranscript(text)
        }
        guard let raw = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return parsePlainTranscript(raw)
    }

    private static func parsePlainTranscript(_ raw: String) -> [AgentTurn] {
        var turns: [AgentTurn] = []
        var pendingUsers: [String] = []
        var active = "none"
        var userLines: [String] = []
        var assistantLines: [String] = []
        let userMarker = try! NSRegularExpression(pattern: #"^\s*user:\s*"#, options: .caseInsensitive)
        let assistantMarker = try! NSRegularExpression(pattern: #"^\s*A:\s*"#)
        let thinkingMarker = try! NSRegularExpression(pattern: #"^\s*\[Thinking\]\s*"#)

        func flushUser() {
            guard !userLines.isEmpty else { return }
            let query = extractUserQuery(userLines.joined(separator: "\n"))
            if !query.isEmpty { pendingUsers.append(query) }
            userLines = []
        }
        func flushAssistant() {
            guard !assistantLines.isEmpty else { return }
            var output = ""
            var reasoning = ""
            for line in assistantLines {
                if line.range(of: #"^\s*\[Tool result\]"#, options: .regularExpression) != nil { continue }
                let ns = line as NSString
                if thinkingMarker.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) != nil {
                    let body = thinkingMarker.stringByReplacingMatches(in: line, range: NSRange(location: 0, length: ns.length), withTemplate: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !body.isEmpty { reasoning += body + "\n" }
                    continue
                }
                if line.range(of: #"^\s*\[Tool call\]"#, options: .regularExpression) != nil { continue }
                output += line + "\n"
            }
            if !pendingUsers.isEmpty {
                turns.append(AgentTurn(
                    user: pendingUsers.removeFirst(),
                    body: output.trimmingCharacters(in: .whitespacesAndNewlines),
                    reasoning: reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
                ))
            }
            assistantLines = []
        }

        raw.enumerateLines { line, _ in
            let ns = line as NSString
            let range = NSRange(location: 0, length: ns.length)
            if userMarker.firstMatch(in: line, range: range) != nil {
                if active == "user" { flushUser() }
                if active == "assistant" { flushAssistant() }
                active = "user"
                userLines = [userMarker.stringByReplacingMatches(in: line, range: range, withTemplate: "")]
                return
            }
            if assistantMarker.firstMatch(in: line, range: range) != nil {
                if active == "user" { flushUser() }
                if active == "assistant" { flushAssistant() }
                active = "assistant"
                assistantLines = [assistantMarker.stringByReplacingMatches(in: line, range: range, withTemplate: "")]
                return
            }
            if active == "user" { userLines.append(line) }
            else if active == "assistant" { assistantLines.append(line) }
        }
        if active == "user" { flushUser() }
        if active == "assistant" { flushAssistant() }
        return turns
    }

    private static func transcriptFiles(under projects: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: projects,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            let path = url.path
            guard path.contains("/agent-transcripts/") else { continue }
            if url.pathExtension == "jsonl" || url.pathExtension == "txt" {
                files.append(url)
            }
        }
        return files
    }

    private static func dateFromEpoch(_ value: Double) -> Date? {
        let ms = value < 1e12 ? value * 1000 : value
        guard ms.isFinite, ms > 0 else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }

    private static func columnInt(_ statement: OpaquePointer?, _ index: Int32) -> Int {
        if sqlite3_column_type(statement, index) == SQLITE_NULL { return 0 }
        return Int(sqlite3_column_int64(statement, index))
    }

    private static func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let ptr = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: ptr)
    }

    private static func columnValue(_ statement: OpaquePointer?, _ index: Int32) -> Any? {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_TEXT:
            return columnText(statement, index)
        case SQLITE_INTEGER:
            return Int(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            return sqlite3_column_double(statement, index)
        default:
            return nil
        }
    }
}

private enum CursorDiskKV {
    static func open(_ url: URL, body: (OpaquePointer) throws -> Void) throws {
        var database: OpaquePointer?
        var flags = SQLITE_OPEN_READONLY
        var filename = url.path
        if sqlite3_open_v2(filename, &database, flags, nil) != SQLITE_OK {
            sqlite3_close(database)
            database = nil
            filename = "\(url.absoluteURL.absoluteString)?immutable=1"
            flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
            guard sqlite3_open_v2(filename, &database, flags, nil) == SQLITE_OK else {
                let code = database.map(sqlite3_errcode) ?? SQLITE_CANTOPEN
                sqlite3_close(database)
                throw SQLiteFailure(code: code)
            }
        }
        guard let database else { throw SQLiteFailure(code: SQLITE_CANTOPEN) }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 250)
        try body(database)
    }

    private struct SQLiteFailure: Error {
        let code: Int32
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
