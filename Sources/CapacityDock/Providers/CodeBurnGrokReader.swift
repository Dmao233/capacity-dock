import Foundation

/// CodeBurn `src/providers/grok.ts` `parseUpdates` / `chooseAuthoritativeModel`.
/// One session → one call. Does not read `~/.grok/logs/unified.jsonl`.
enum CodeBurnGrokReader {
    static let fallbackModel = "grok-build"

    struct SessionUsage: Equatable, Sendable {
        var input = 0
        var cacheRead = 0
        var output = 0
        var cacheCreation = 0
        var reasoning = 0
        var modelIds: [String] = []
        var authoritative = false
        var hasUncompletedTurn = false

        var hasPositiveTotals: Bool {
            input > 0 || cacheRead > 0 || output > 0 || cacheCreation > 0 || reasoning > 0
        }
    }

    struct AuthoritativeUsage {
        var inputTokens = 0
        var outputTokens = 0
        var cacheReadTokens = 0
        var cacheCreationTokens = 0
        var reasoningTokens = 0
        var modelUsage: [String: AuthoritativeUsage] = [:]

        var hasPositiveTopLevel: Bool {
            inputTokens > 0 || outputTokens > 0 || cacheReadTokens > 0
                || cacheCreationTokens > 0 || reasoningTokens > 0
        }
    }

    static func parseUpdates(_ text: String) -> SessionUsage {
        var turns: [String: (first: Int, last: Int)] = [:]
        var completed: [String: AuthoritativeUsage] = [:]
        var prevTotal = -1
        var segmentPeak = 0
        var inputFresh = 0
        var completedWithoutPromptId = 0

        text.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let params = root["params"] as? [String: Any]
            else { return }

            if let meta = params["_meta"] as? [String: Any],
               let total = finiteNonNegative(meta["totalTokens"]) {
                if prevTotal >= 0, total < prevTotal / 2 {
                    inputFresh = addTokenCounts(inputFresh, segmentPeak)
                    segmentPeak = 0
                }
                if total > segmentPeak { segmentPeak = total }
                prevTotal = total
                if let promptId = meta["promptId"] as? String, !promptId.isEmpty {
                    if var turn = turns[promptId] {
                        turn.last = total
                        turns[promptId] = turn
                    } else {
                        turns[promptId] = (first: total, last: total)
                    }
                }
            }

            guard let update = params["update"] as? [String: Any],
                  update["sessionUpdate"] as? String == "turn_completed",
                  let usage = parseAuthoritativeUsage(update["usage"])
            else { return }

            let promptId: String
            if let id = update["prompt_id"] as? String, !id.isEmpty {
                promptId = id
            } else {
                promptId = "turn_completed:\(completedWithoutPromptId)"
                completedWithoutPromptId += 1
            }
            completed[promptId] = usage
        }

        inputFresh = addTokenCounts(inputFresh, segmentPeak)
        var sumFirst = 0
        var estimatedOutput = 0
        for turn in turns.values {
            sumFirst = addTokenCounts(sumFirst, turn.first)
            estimatedOutput = addTokenCounts(estimatedOutput, max(0, turn.last - turn.first))
        }

        var totals = SessionUsage()
        var seen = Set<String>()
        for usage in completed.values {
            addUsage(&totals, usage)
            for modelId in usage.modelUsage.keys where seen.insert(modelId).inserted {
                totals.modelIds.append(modelId)
            }
        }

        let hasPositiveCompleted = completed.values.contains { $0.hasPositiveTopLevel }
        if !hasPositiveCompleted || !totals.hasPositiveTotals {
            return SessionUsage(
                input: inputFresh,
                cacheRead: max(0, sumFirst - inputFresh),
                output: estimatedOutput,
                authoritative: false
            )
        }

        totals.authoritative = true
        totals.hasUncompletedTurn = turns.keys.contains { completed[$0] == nil }
        return totals
    }

    static func chooseAuthoritativeModel(modelIds: [String], existingModel: String) -> String {
        if let priced = modelIds.first(where: { CodeBurnPricing.getModelCosts($0) != nil }) {
            return priced
        }
        if CodeBurnPricing.getModelCosts(existingModel) != nil {
            return existingModel
        }
        return modelIds.first ?? existingModel
    }

    static func existingModel(summary: [String: Any], signals: [String: Any]?) -> String {
        if let current = CodeBurnPricing.cleaned(summary["current_model_id"] as? String) {
            return current
        }
        if let primary = CodeBurnPricing.cleaned(signals?["primaryModelId"] as? String) {
            return primary
        }
        if let used = signals?["modelsUsed"] as? [String],
           let first = used.lazy.compactMap(CodeBurnPricing.cleaned).first {
            return first
        }
        return fallbackModel
    }

    static func event(
        updates: String,
        summary: [String: Any],
        signals: [String: Any]?
    ) -> TokenConsumptionEvent? {
        let parsed = parseUpdates(updates)
        guard parsed.hasPositiveTotals else { return nil }
        let existing = existingModel(summary: summary, signals: signals)
        let model = parsed.authoritative
            ? chooseAuthoritativeModel(modelIds: parsed.modelIds, existingModel: existing)
            : existing
        let timestamp = (summary["updated_at"] as? String)
            ?? (summary["last_active_at"] as? String)
            ?? (summary["created_at"] as? String)
        guard let date = TokenConsumptionClock.parseTimestamp(timestamp) else { return nil }
        let reasoning = min(parsed.reasoning, parsed.output)
        return TokenConsumptionEvent(
            providerID: "grok",
            date: date,
            model: model,
            totals: TokenUsageTotals(
                input: parsed.input,
                output: parsed.output - reasoning,
                cacheRead: parsed.cacheRead,
                cacheWrite: parsed.cacheCreation,
                reasoning: reasoning,
                outputIncludesReasoning: false
            )
        )
    }

    static func scan(
        window: TokenConsumptionWindow,
        home: URL,
        cache: inout TokenLogDayCache
    ) -> (events: [TokenConsumptionEvent], sawLog: Bool) {
        let root = grokHome(from: home).appendingPathComponent("sessions", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else {
            return ([], false)
        }
        var events: [TokenConsumptionEvent] = []
        var saw = false
        guard let cwds = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return ([], false) }

        for cwd in cwds {
            guard (try? cwd.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                  let sessions = try? FileManager.default.contentsOfDirectory(
                    at: cwd,
                    includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                  )
            else { continue }
            for session in sessions {
                guard (try? session.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                else { continue }
                let updatesURL = session.appendingPathComponent("updates.jsonl")
                let summaryURL = session.appendingPathComponent("summary.json")
                guard FileManager.default.fileExists(atPath: updatesURL.path),
                      FileManager.default.fileExists(atPath: summaryURL.path)
                else { continue }
                saw = true
                // CodeBurn parser.ts skips sources whose data-file mtime is
                // before the window. A rewritten summary.json must not pull
                // an untouched updates.jsonl into today.
                let mtime = (try? updatesURL.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate
                if let mtime, mtime < window.start { continue }

                let fingerprint = TokenLogDayCache.fingerprint(of: updatesURL)
                if let cached = cache.events(for: updatesURL, fingerprint: fingerprint, providerID: "grok") {
                    events.append(contentsOf: cached.filter { window.contains($0.date) })
                    continue
                }
                guard let summaryData = try? SafeFile.read(from: summaryURL.path, maxBytes: SafeFile.defaultReadLimit),
                      let summaryObj = try? JSONSerialization.jsonObject(with: summaryData) as? [String: Any]
                else { continue }
                let signalsURL = session.appendingPathComponent("signals.json")
                let signals: [String: Any]?
                if FileManager.default.fileExists(atPath: signalsURL.path),
                   let data = try? SafeFile.read(from: signalsURL.path, maxBytes: SafeFile.defaultReadLimit) {
                    signals = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                } else {
                    signals = nil
                }
                var updates = ""
                JSONLStreamer.forEachLine(at: updatesURL) { line in
                    updates.append(line)
                    updates.append("\n")
                }
                let parsed = event(
                    updates: updates,
                    summary: summaryObj,
                    signals: signals
                )
                let stored = parsed.map { [$0] } ?? []
                cache.store(file: updatesURL, fingerprint: fingerprint, events: stored)
                events.append(contentsOf: stored.filter { window.contains($0.date) })
            }
        }
        return (events, saw)
    }

    private static func grokHome(from home: URL) -> URL {
        if let override = ProcessInfo.processInfo.environment["GROK_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return home.appendingPathComponent(".grok", isDirectory: true)
    }

    private static func parseAuthoritativeUsage(_ raw: Any?) -> AuthoritativeUsage? {
        guard let usage = raw as? [String: Any] else { return nil }
        var result = AuthoritativeUsage(
            inputTokens: finiteNonNegative(usage["inputTokens"]) ?? 0,
            outputTokens: finiteNonNegative(usage["outputTokens"]) ?? 0,
            cacheReadTokens: finiteNonNegative(usage["cachedReadTokens"]) ?? 0,
            cacheCreationTokens: finiteNonNegative(usage["cacheCreationTokens"]) ?? 0,
            reasoningTokens: finiteNonNegative(usage["reasoningTokens"]) ?? 0
        )
        if let modelUsage = usage["modelUsage"] as? [String: Any] {
            for (modelId, rawModel) in modelUsage {
                guard !modelId.isEmpty, let values = rawModel as? [String: Any] else { continue }
                let parsed = AuthoritativeUsage(
                    inputTokens: finiteNonNegative(values["inputTokens"]) ?? 0,
                    outputTokens: finiteNonNegative(values["outputTokens"]) ?? 0,
                    cacheReadTokens: finiteNonNegative(values["cachedReadTokens"]) ?? 0,
                    cacheCreationTokens: finiteNonNegative(values["cacheCreationTokens"]) ?? 0,
                    reasoningTokens: finiteNonNegative(values["reasoningTokens"]) ?? 0
                )
                if parsed.hasPositiveTopLevel {
                    result.modelUsage[modelId] = parsed
                }
            }
        }
        return result
    }

    private static func addUsage(_ totals: inout SessionUsage, _ usage: AuthoritativeUsage) {
        let reasoning = min(usage.reasoningTokens, usage.outputTokens)
        totals.input = addTokenCounts(
            totals.input,
            max(0, usage.inputTokens - usage.cacheReadTokens - usage.cacheCreationTokens)
        )
        totals.cacheRead = addTokenCounts(totals.cacheRead, usage.cacheReadTokens)
        totals.output = addTokenCounts(totals.output, usage.outputTokens)
        totals.cacheCreation = addTokenCounts(totals.cacheCreation, usage.cacheCreationTokens)
        totals.reasoning = addTokenCounts(totals.reasoning, reasoning)
    }

    private static func finiteNonNegative(_ value: Any?) -> Int? {
        let number: Double?
        if let int = value as? Int { number = Double(int) }
        else if let double = value as? Double { number = double }
        else { number = nil }
        guard let number, number.isFinite, number >= 0 else { return nil }
        return Int(min(number, Double(Int.max)))
    }

    private static func addTokenCounts(_ left: Int, _ right: Int) -> Int {
        let sum = left.addingReportingOverflow(right)
        return sum.overflow ? Int.max : sum.partialValue
    }
}
