import Foundation
import Testing
@testable import CapacityDock

@Suite("Token consumption")
struct TokenConsumptionTests {
    private var shanghai: TimeZone { TimeZone(identifier: "Asia/Shanghai")! }

    @Test("week is rolling last 7 days and month starts on the 1st")
    func periodBoundsFollowCodeBurn() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = shanghai
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 20))!
        let today = TokenConsumptionClock.window(for: .today, now: now, timeZone: shanghai)
        let week = TokenConsumptionClock.window(for: .week, now: now, timeZone: shanghai)
        let month = TokenConsumptionClock.window(for: .month, now: now, timeZone: shanghai)

        #expect(calendar.component(.day, from: today.start) == 4)
        #expect(calendar.component(.hour, from: today.start) == 0)
        #expect(today.contains(now))
        #expect(!today.contains(today.start.addingTimeInterval(-1)))

        #expect(calendar.component(.day, from: week.start) == 28)
        #expect(calendar.component(.month, from: week.start) == 8)
        #expect(week.contains(calendar.date(from: DateComponents(year: 2026, month: 8, day: 28, hour: 1))!))

        #expect(calendar.component(.day, from: month.start) == 1)
        #expect(calendar.component(.month, from: month.start) == 9)
    }

    @Test("Claude assistant usage lines map input/output/cache")
    func parsesClaudeUsage() {
        let line = #"{"type":"assistant","timestamp":"2026-09-04T12:00:00.000Z","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":100,"output_tokens":20,"cache_read_input_tokens":5,"cache_creation_input_tokens":2}}}"#
        let event = TokenLogLineParser.claudeEvent(from: line)
        #expect(event?.providerID == "claude")
        #expect(event?.totals.input == 100)
        #expect(event?.totals.output == 20)
        #expect(event?.totals.cacheRead == 5)
        #expect(event?.totals.cacheWrite == 2)
        #expect(CodeBurnPricing.getModelCosts(event!.model!) != nil)
        #expect(CodeBurnPricing.estimateUSD(provider: "claude", model: event?.model, totals: event!.totals) > 0)
    }

    @Test("user lines and empty usage are not token events")
    func ignoresNonUsageClaude() {
        #expect(TokenLogLineParser.claudeEvent(from: #"{"type":"user","timestamp":"2026-09-04T12:00:00Z"}"#) == nil)
        #expect(TokenLogLineParser.claudeEvent(from: #"{"type":"assistant","timestamp":"2026-09-04T12:00:00Z","message":{"usage":{"input_tokens":0,"output_tokens":0}}}"#) == nil)
    }

    @Test("Codex last_token_usage is incremental and duplicate totals are dropped")
    func parsesCodexIncrements() {
        let first = #"{"timestamp":"2026-09-04T12:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":80,"cached_input_tokens":20,"output_tokens":10,"reasoning_output_tokens":4},"total_token_usage":{"input_tokens":80,"cached_input_tokens":20,"output_tokens":10,"reasoning_output_tokens":4}}}}"#
        let duplicate = #"{"timestamp":"2026-09-04T12:00:01Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":80,"cached_input_tokens":20,"output_tokens":10,"reasoning_output_tokens":4},"total_token_usage":{"input_tokens":80,"cached_input_tokens":20,"output_tokens":10,"reasoning_output_tokens":4}}}}"#
        let firstRecord = TokenLogLineParser.codexRecord(from: first)
        let duplicateRecord = TokenLogLineParser.codexRecord(from: duplicate)
        guard case .token(_, let last, let total, let cumulative, _, _) = firstRecord, let last else {
            Issue.record("expected first token record")
            return
        }
        #expect(last.input == 80)
        #expect(last.cached == 20)
        #expect(last.output == 10)
        #expect(last.reasoning == 4)
        #expect(cumulative == 0 || total != nil)
        guard case .token(_, _, let duplicateTotal, let duplicateCumulative, _, _) = duplicateRecord else {
            Issue.record("expected duplicate token record")
            return
        }
        #expect(total == duplicateTotal)
        #expect(cumulative == duplicateCumulative)
    }

    @Test("Grok turn_completed splits cache subsets and prices the session once")
    func parsesGrokSessionUpdates() {
        let updates = """
        {"params":{"update":{"sessionUpdate":"turn_completed","prompt_id":"p1","usage":{"inputTokens":12851663,"outputTokens":36633,"cachedReadTokens":12092032,"cacheCreationTokens":0,"reasoningTokens":29077}}}}
        """
        let parsed = CodeBurnGrokReader.parseUpdates(updates)
        #expect(parsed.input == 759631)
        #expect(parsed.cacheRead == 12092032)
        #expect(parsed.output == 36633)
        #expect(parsed.reasoning == 29077)
        #expect(parsed.authoritative)

        let event = CodeBurnGrokReader.event(
            updates: updates,
            summary: ["updated_at": "2026-09-04T12:00:00Z", "current_model_id": "grok-build"],
            signals: nil
        )
        #expect(event?.providerID == "grok")
        #expect(event?.model == "grok-build")
        #expect(event?.totals.input == 759631)
        #expect(event?.totals.output == 7556)
        #expect(event?.totals.reasoning == 29077)
        let cost = CodeBurnPricing.estimateUSD(provider: "grok", model: event?.model, totals: event!.totals)
        #expect(cost == CodeBurnPricing.calculateCost(
            model: "grok-build",
            inputTokens: 759631,
            outputTokens: 36633,
            cacheCreationTokens: 0,
            cacheReadTokens: 12092032
        ))
        #expect(abs(cost - CodeBurnPricing.calculateCost(
            model: "grok-build-0.1",
            inputTokens: 759631,
            outputTokens: 36633,
            cacheCreationTokens: 0,
            cacheReadTokens: 12092032
        )) < 0.0000001)
    }

    @Test("unknown models contribute $0 and stay in the total")
    func unknownModelIsZeroIncluded() {
        let totals = TokenUsageTotals(input: 100, output: 10)
        #expect(CodeBurnPricing.estimateUSD(provider: "grok", model: nil, totals: totals) == 0)
        #expect(CodeBurnPricing.estimateUSD(provider: "grok", model: "mystery-model-9", totals: totals) == 0)
        #expect(CodeBurnPricing.hasBillableRate("mystery-model-9") == false)
        #expect(CodeBurnPricing.estimateUSD(provider: "claude", model: "claude-sonnet-4-6", totals: totals) > 0)
        #expect(CodeBurnPricing.calculateCost(model: "grok-4.6", inputTokens: 100_000, outputTokens: 10_000, cacheCreationTokens: 0, cacheReadTokens: 99_999) == 0.3099995)
        #expect(CodeBurnPricing.calculateCost(model: "grok-4.6", inputTokens: 100_000, outputTokens: 10_000, cacheCreationTokens: 0, cacheReadTokens: 100_000) == 0.62)
    }

    @Test("missing logs never become a $0 row")
    func missingLogsAreNotZeroBills() {
        let now = Date()
        let window = TokenConsumptionClock.window(for: .today, now: now)
        let snapshot = TokenConsumptionAggregator.snapshot(
            period: .today,
            window: window,
            events: [],
            availability: [
                "claude": .noLocalTokenLog,
                "codex": .noLocalTokenLog,
                "grok": .noLocalTokenLog,
                "cursor": .cursorHashOnly
            ],
            scannedAnyLog: false
        )
        #expect(snapshot.allLogsMissing)
        #expect(snapshot.hasAnyMeasuredRow == false)
        for row in snapshot.rows {
            #expect(row.showsCurrency == false)
            #expect(row.estimatedUSD == nil)
            #expect(row.totals.tokenCount == 0)
            #expect(row.hasMeasuredTokens == false)
        }
        let cursor = snapshot.rows.first { $0.providerID == "cursor" }
        #expect(cursor?.availability == .cursorHashOnly)
    }

    @Test("period totals sum only logged tokens and priced amounts")
    func periodTotalsSkipMissingAndUnpriced() {
        let now = Date()
        let window = TokenConsumptionClock.window(for: .today, now: now)
        let claude = TokenConsumptionEvent(
            providerID: "claude",
            date: now,
            model: "claude-haiku-4-5",
            totals: TokenUsageTotals(input: 40, output: 8, cacheRead: 5, cacheWrite: 2)
        )
        let grok = TokenConsumptionEvent(
            providerID: "grok",
            date: now,
            model: nil,
            totals: TokenUsageTotals(input: 12, output: 3, reasoning: 1)
        )
        let snapshot = TokenConsumptionAggregator.snapshot(
            period: .today,
            window: window,
            events: [claude, grok],
            availability: [
                "claude": .logged,
                "codex": .noLocalTokenLog,
                "grok": .logged,
                "cursor": .cursorHashOnly,
                "gemini": .noLocalTokenLog
            ],
            scannedAnyLog: true
        )
        let totals = snapshot.periodTotals
        #expect(totals.input == 52)
        #expect(totals.output == 12)
        #expect(totals.cacheRead == 5)
        #expect(totals.cacheWrite == 2)
        #expect(totals.reasoning == 1)
        #expect(totals.measuredProviderCount == 2)
        #expect(totals.showsCurrency == true)
        #expect(totals.estimatedUSD != nil)
        #expect(totals.unpricedEventCount == 0)
        #expect(snapshot.rows.first { $0.providerID == "grok" }?.showsCurrency == true)
        #expect(snapshot.ledgerRows.contains { $0.providerID == "claude" })
        #expect(snapshot.ledgerRows.contains { $0.providerID == "grok" })
        #expect(snapshot.ledgerRows.contains { $0.providerID == "cursor" })
        #expect(snapshot.ledgerRows.contains { $0.providerID == "gemini" } == false)
        #expect(snapshot.ledgerRows.contains { $0.providerID == "codex" } == false)
        let missing = TokenConsumptionAggregator.snapshot(
            period: .today,
            window: window,
            events: [],
            availability: ["claude": .noLocalTokenLog, "cursor": .cursorHashOnly],
            scannedAnyLog: false
        )
        #expect(missing.periodTotals.showsCurrency == false)
        #expect(missing.periodTotals.estimatedUSD == nil)
        #expect(missing.periodTotals.tokenCount == 0)
    }

    @Test("logged empty period is measured idle, not a missing log")
    func loggedZeroIsNotMissing() {
        let now = Date()
        let window = TokenConsumptionClock.window(for: .today, now: now)
        let snapshot = TokenConsumptionAggregator.snapshot(
            period: .today,
            window: window,
            events: [],
            availability: ["claude": .logged],
            scannedAnyLog: true
        )
        let claude = snapshot.rows.first { $0.providerID == "claude" }
        #expect(claude?.availability == .logged)
        #expect(claude?.showsMeasuredZero == true)
        #expect(claude?.showsCurrency == false)
        #expect(snapshot.allLogsMissing == false)
    }

    @Test("reader only counts JSONL token fields from a fixture home")
    func readerUsesFixtureLogs() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("capacity-dock-token-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = shanghai
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 20))!

        let claudeDir = home.appendingPathComponent(".claude/projects/p", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let claude = """
        {"type":"user","timestamp":"2026-09-04T10:00:00Z"}
        {"type":"assistant","timestamp":"2026-08-01T10:01:00Z","message":{"model":"claude-haiku-4-5","usage":{"input_tokens":9999,"output_tokens":9}}}
        {"type":"assistant","timestamp":"2026-09-04T10:01:00Z","message":{"model":"claude-haiku-4-5","usage":{"input_tokens":40,"output_tokens":8}}}
        """
        try claude.write(
            to: claudeDir.appendingPathComponent("s.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let codexDir = home.appendingPathComponent(".codex/sessions/2026/09/04", isDirectory: true)
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
        let codex = """
        {"timestamp":"2026-09-04T10:00:00Z","type":"turn_context","payload":{"model":"gpt-5.5"}}
        {"timestamp":"2026-09-04T10:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":30,"cached_input_tokens":0,"output_tokens":6,"reasoning_output_tokens":1},"total_token_usage":{"input_tokens":30,"cached_input_tokens":0,"output_tokens":6,"reasoning_output_tokens":1}}}}
        """
        try codex.write(
            to: codexDir.appendingPathComponent("rollout-2026-09-04T10-01-00-test.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let grokSession = home.appendingPathComponent(".grok/sessions/proj/sess-1", isDirectory: true)
        try FileManager.default.createDirectory(at: grokSession, withIntermediateDirectories: true)
        try #"{"info":{"id":"sess-1"},"updated_at":"2026-09-04T10:02:00Z","current_model_id":"grok-4.6"}"#
            .write(to: grokSession.appendingPathComponent("summary.json"), atomically: true, encoding: .utf8)
        try #"{"params":{"update":{"sessionUpdate":"turn_completed","prompt_id":"p","usage":{"inputTokens":12,"outputTokens":3,"cachedReadTokens":0,"cacheCreationTokens":0,"reasoningTokens":0}}}}"#
            .write(to: grokSession.appendingPathComponent("updates.jsonl"), atomically: true, encoding: .utf8)

        try Data().write(to: home.appendingPathComponent("hash-only.json"))

        let snapshot = LocalTokenLogReader.load(
            period: .today,
            deps: .init(home: home, now: now, timeZone: shanghai, cacheURL: nil)
        )
        let claudeRow = snapshot.rows.first { $0.providerID == "claude" }
        let codexRow = snapshot.rows.first { $0.providerID == "codex" }
        let grokRow = snapshot.rows.first { $0.providerID == "grok" }
        let cursorRow = snapshot.rows.first { $0.providerID == "cursor" }
        #expect(claudeRow?.availability == .logged)
        #expect(claudeRow?.totals.input == 40)
        #expect(claudeRow?.showsCurrency == true)
        #expect(codexRow?.totals.input == 30)
        #expect(codexRow?.showsCurrency == true)
        #expect(grokRow?.totals.input == 12)
        #expect(grokRow?.totals.output == 3)
        #expect(grokRow?.showsCurrency == true)
        #expect(grokRow?.models.map(\.model) == ["grok-4.6"])
        #expect(cursorRow?.availability == .cursorHashOnly)
        #expect(cursorRow?.showsCurrency == false)
    }

    @Test("quota rings stay hash-only; bill may read cursor tokens")
    func cursorBillIsSeparateFromHashRings() {
        #expect(LocalTokenLogReader.parsedProviderIDs.contains("cursor"))
        #expect(LocalTokenLogReader.parsedProviderIDs.contains("cursor-agent"))
        #expect(LocalTokenLogReader.parsedProviderIDs.contains("grok"))
        #expect(CodeBurnCursorBill.inputSource(hasRealTokens: true, hasMeter: true) == .bubbleTokens)
        #expect(CodeBurnCursorBill.inputSource(hasRealTokens: false, hasMeter: true) == .meter)
        #expect(CodeBurnCursorBill.inputSource(hasRealTokens: false, hasMeter: false) == .text)
    }

    @Test("Codex reads flat archived_sessions without date folders")
    func readsFlatArchivedCodex() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("capacity-dock-archived-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = shanghai
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 20))!
        let archived = home.appendingPathComponent(".codex/archived_sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: archived, withIntermediateDirectories: true)
        let line = """
        {"timestamp":"2026-09-04T10:00:00Z","type":"turn_context","payload":{"model":"gpt-5.5"}}
        {"timestamp":"2026-09-04T10:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":30,"cached_input_tokens":0,"output_tokens":6,"reasoning_output_tokens":1},"total_token_usage":{"input_tokens":30,"cached_input_tokens":0,"output_tokens":6,"reasoning_output_tokens":1,"total_tokens":37}}}}
        """
        try line.write(
            to: archived.appendingPathComponent("rollout-2026-09-04T10-00-00-abcd.jsonl"),
            atomically: true,
            encoding: .utf8
        )
        let snapshot = LocalTokenLogReader.load(
            period: .today,
            deps: .init(home: home, now: now, timeZone: shanghai, cacheURL: nil)
        )
        let codex = snapshot.rows.first { $0.providerID == "codex" }
        #expect(codex?.availability == .logged)
        #expect(codex?.totals.input == 30)
        #expect(codex?.showsCurrency == true)
    }

    @Test("daily buckets keep only days with events and do not fill gaps")
    func dailyTrendDoesNotInventZeroDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = shanghai
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 20))!
        let first = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 10))!
        let last = calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 9))!
        let window = TokenConsumptionClock.window(for: .month, now: now, timeZone: shanghai)
        let snapshot = TokenConsumptionAggregator.snapshot(
            period: .month,
            window: window,
            events: [
                TokenConsumptionEvent(
                    providerID: "claude",
                    date: first,
                    model: "claude-haiku-4-5",
                    totals: TokenUsageTotals(input: 10, output: 2)
                ),
                TokenConsumptionEvent(
                    providerID: "claude",
                    date: last,
                    model: "claude-haiku-4-5",
                    totals: TokenUsageTotals(input: 20, output: 4)
                )
            ],
            availability: ["claude": .logged],
            scannedAnyLog: true,
            timeZone: shanghai
        )
        #expect(snapshot.daily.map(\.day) == ["2026-09-01", "2026-09-04"])
        #expect(snapshot.daily.map(\.calls) == [1, 1])
        #expect(snapshot.showsDailyTrend)
        #expect(snapshot.daily.contains { $0.day == "2026-09-02" } == false)
        #expect(snapshot.modelRows(matching: "claude").map(\.shortName) == ["claude-haiku-4-5"])
        #expect(TokenConsumptionPresentation.heroKind(snapshot) == .billed)
        #expect(TokenConsumptionPresentation.heroAmount(snapshot.periodTotals) != nil)
    }

    @Test("missing logs have no dollar hero")
    func missingLogsHaveNoHeroAmount() {
        let now = Date()
        let window = TokenConsumptionClock.window(for: .today, now: now)
        let snapshot = TokenConsumptionAggregator.snapshot(
            period: .today,
            window: window,
            events: [],
            availability: [
                "claude": .noLocalTokenLog,
                "cursor": .cursorHashOnly
            ],
            scannedAnyLog: false
        )
        #expect(TokenConsumptionPresentation.heroKind(snapshot) == .missingLogs)
        #expect(TokenConsumptionPresentation.heroAmount(snapshot.periodTotals) == nil)
        #expect(snapshot.periodTotals.showsCurrency == false)
        #expect(snapshot.daily.isEmpty)
    }

    @Test("provider filter totals only that provider's priced rows")
    func providerFilterUsesLoggedRows() {
        let now = Date()
        let window = TokenConsumptionClock.window(for: .today, now: now)
        let snapshot = TokenConsumptionAggregator.snapshot(
            period: .today,
            window: window,
            events: [
                TokenConsumptionEvent(
                    providerID: "claude",
                    date: now,
                    model: "claude-haiku-4-5",
                    totals: TokenUsageTotals(input: 40, output: 8)
                ),
                TokenConsumptionEvent(
                    providerID: "grok",
                    date: now,
                    model: nil,
                    totals: TokenUsageTotals(input: 12, output: 3)
                )
            ],
            availability: ["claude": .logged, "grok": .logged],
            scannedAnyLog: true
        )
        let all = snapshot.totals(matching: nil)
        let claude = snapshot.totals(matching: "claude")
        let grok = snapshot.totals(matching: "grok")
        #expect(all.loggedEventCount == 2)
        #expect(claude.showsCurrency)
        #expect(claude.loggedEventCount == 1)
        #expect(TokenConsumptionPresentation.heroKind(snapshot, providerID: "grok") == .billed)
        #expect(TokenConsumptionPresentation.heroAmount(grok) != nil)
        #expect(snapshot.billedProviderRows.map(\.providerID) == ["claude", "grok"])
    }

    @Test("Grok session model comes from summary then modelUsage")
    func grokSessionSummaryAttributesModel() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("capacity-dock-grok-summary-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = shanghai
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 20))!

        let session = home.appendingPathComponent(".grok/sessions/proj/sess-1", isDirectory: true)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        try #"{"info":{"id":"sess-1"},"updated_at":"2026-09-04T10:02:00Z","current_model_id":"grok-4.5"}"#
            .write(to: session.appendingPathComponent("summary.json"), atomically: true, encoding: .utf8)
        try #"{"params":{"update":{"sessionUpdate":"turn_completed","prompt_id":"p","usage":{"inputTokens":12,"outputTokens":3,"cachedReadTokens":0,"cacheCreationTokens":0,"reasoningTokens":0}}}}"#
            .write(to: session.appendingPathComponent("updates.jsonl"), atomically: true, encoding: .utf8)

        let snapshot = LocalTokenLogReader.load(
            period: .today,
            deps: .init(home: home, now: now, timeZone: shanghai, cacheURL: nil)
        )
        let grok = snapshot.rows.first { $0.providerID == "grok" }
        #expect(grok?.showsCurrency == true)
        #expect(grok?.models.map(\.model) == ["grok-4.5"])
        #expect(CodeBurnGrokReader.existingModel(summary: ["current_model_id": "grok-4.6"], signals: nil) == "grok-4.6")
        #expect(CodeBurnGrokReader.existingModel(summary: [:], signals: ["primaryModelId": "grok-4.5", "modelsUsed": ["grok-4.6"]]) == "grok-4.5")
        #expect(CodeBurnGrokReader.existingModel(summary: [:], signals: nil) == "grok-build")
        #expect(CodeBurnGrokReader.chooseAuthoritativeModel(modelIds: ["mystery-build", "grok-4.6"], existingModel: "grok-build") == "grok-4.6")
        #expect(CodeBurnPricing.getModelCosts("grok-build") != nil)
        #expect(CodeBurnPricing.resolveCanonicalModelId("grok-build") == "grok-build-0.1")
    }

    @Test("Grok ignores a rewritten summary when updates.jsonl was not touched today")
    func grokSkipsStaleUpdatesFile() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("capacity-dock-grok-mtime-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = shanghai
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 20))!
        let session = home.appendingPathComponent(".grok/sessions/proj/sess-old", isDirectory: true)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        let updates = session.appendingPathComponent("updates.jsonl")
        try #"{"info":{"id":"sess-old"},"updated_at":"2026-09-04T10:02:00Z","current_model_id":"grok-4.6"}"#
            .write(to: session.appendingPathComponent("summary.json"), atomically: true, encoding: .utf8)
        try #"{"params":{"update":{"sessionUpdate":"turn_completed","prompt_id":"p","usage":{"inputTokens":12000,"outputTokens":30,"cachedReadTokens":0,"cacheCreationTokens":0,"reasoningTokens":0}}}}"#
            .write(to: updates, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-86_400 * 2)],
            ofItemAtPath: updates.path
        )

        let snapshot = LocalTokenLogReader.load(
            period: .today,
            deps: .init(home: home, now: now, timeZone: shanghai, cacheURL: nil)
        )
        let grok = snapshot.rows.first { $0.providerID == "grok" }
        #expect(grok?.totals.tokenCount == 0)
        #expect(grok?.showsCurrency == false)
    }

    @Test("session-level 200k tier doubles the whole Grok package")
    func grokSessionTierIsOncePerSession() {
        let low = CodeBurnPricing.calculateCost(
            model: "grok-4.6",
            inputTokens: 100_000,
            outputTokens: 10_000,
            cacheCreationTokens: 0,
            cacheReadTokens: 99_999
        )
        let high = CodeBurnPricing.calculateCost(
            model: "grok-4.6",
            inputTokens: 100_000,
            outputTokens: 10_000,
            cacheCreationTokens: 0,
            cacheReadTokens: 100_000
        )
        #expect(low == 0.3099995)
        #expect(high == 0.62)
        let twoTurns = CodeBurnGrokReader.parseUpdates("""
        {"params":{"update":{"sessionUpdate":"turn_completed","prompt_id":"a","usage":{"inputTokens":100000,"outputTokens":5000,"cachedReadTokens":50000}}}}
        {"params":{"update":{"sessionUpdate":"turn_completed","prompt_id":"b","usage":{"inputTokens":100000,"outputTokens":5000,"cachedReadTokens":50000}}}}
        """)
        #expect(twoTurns.input + twoTurns.cacheRead == 200_000)
        let sessionCost = CodeBurnPricing.calculateCost(
            model: "grok-4.6",
            inputTokens: twoTurns.input,
            outputTokens: twoTurns.output,
            cacheCreationTokens: twoTurns.cacheCreation,
            cacheReadTokens: twoTurns.cacheRead
        )
        #expect(sessionCost == 0.62)
    }
}
