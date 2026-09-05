import Foundation

/// CodeBurn `src/models.ts` `calculateCost` / `getModelCosts` for the models
/// this Mac actually bills. Unknown ids return $0 and stay in the total.
enum CodeBurnPricing {
    struct ModelCosts: Equatable, Sendable {
        var inputCostPerToken: Double
        var outputCostPerToken: Double
        var cacheWriteCostPerToken: Double
        var cacheReadCostPerToken: Double
        var webSearchCostPerRequest: Double
        var fastMultiplier: Double
        var cacheWriteCostIsExplicit: Bool
    }

    private struct SnapshotEntry {
        var input: Double
        var output: Double
        var cacheWrite: Double?
        var cacheRead: Double?
        var fast: Double?
    }

    private static let webSearchCost = 0.01
    private static let oneHourCacheWriteMultiplier = 1.6
    private static let grok46PromptThreshold = 200_000
    private static let reasoningIncludedInOutput: Set<String> = ["claude", "codex", "copilot"]

    private static let aliases: [String: String] = [
        "grok-build": "grok-build-0.1",
        "claude-haiku-4.5": "claude-haiku-4-5",
        "claude-sonnet-4.6": "claude-sonnet-4-6",
        "claude-sonnet-4.5": "claude-sonnet-4-5",
        "claude-opus-4.7": "claude-opus-4-7",
        "claude-opus-4.6": "claude-opus-4-6",
        "claude-opus-4.5": "claude-opus-4-5",
        "cursor-auto": "claude-sonnet-4-5",
        "cursor-agent-auto": "claude-sonnet-4-5",
        "claude-4-sonnet": "claude-sonnet-4",
        "claude-4.5-sonnet": "claude-sonnet-4-5",
        "claude-4.6-sonnet": "claude-sonnet-4-6",
        "claude-4.6-sonnet-high": "claude-sonnet-4-6",
        "claude-4.6-sonnet-low": "claude-sonnet-4-6",
        "claude-4.6-sonnet-thinking": "claude-sonnet-4-6",
        "claude-4-opus": "claude-opus-4",
        "claude-4.5-opus": "claude-opus-4-5",
        "claude-4.6-opus": "claude-opus-4-6",
        "claude-4.5-haiku": "claude-haiku-4-5",
        "claude-4.6-haiku": "claude-haiku-4-5",
        "gemini-3.1-pro": "gemini-3.1-pro-preview",
        "gemini-3-flash": "gemini-3-flash-preview",
        "gemini-3-pro": "gemini-3-pro-preview"
    ]

    /// Composer house rates from CodeBurn `BUILTIN_PRICE_OVERRIDES`.
    private static let builtinOverrides: [String: SnapshotEntry] = [
        "composer-2.5": .init(input: 0.5e-6, output: 2.5e-6, cacheWrite: 0.5e-6, cacheRead: 0.2e-6),
        "composer-2": .init(input: 0.5e-6, output: 2.5e-6, cacheWrite: 0.5e-6, cacheRead: 0.2e-6),
        "composer-1.5": .init(input: 3.5e-6, output: 17.5e-6, cacheWrite: 3.5e-6, cacheRead: 0.35e-6),
        "composer-1": .init(input: 1.25e-6, output: 10e-6, cacheWrite: 1.25e-6, cacheRead: 0.125e-6)
    ]

    /// Compact LiteLLM snapshot rows used on this Mac. `cacheWrite == nil`
    /// means CodeBurn fabricates 1.25× input and marks it not explicit.
    private static let snapshot: [String: SnapshotEntry] = [
        "grok-4.6": .init(input: 2e-6, output: 6e-6, cacheWrite: nil, cacheRead: 5e-7),
        "grok-4.5": .init(input: 2e-6, output: 6e-6, cacheWrite: nil, cacheRead: 3e-7),
        "grok-build-0.1": .init(input: 1e-6, output: 2e-6, cacheWrite: nil, cacheRead: 2e-7),
        "grok-code-fast-1": .init(input: 2e-7, output: 1.5e-6, cacheWrite: nil, cacheRead: nil),
        "gpt-5.5": .init(input: 5e-6, output: 3e-5, cacheWrite: nil, cacheRead: 5e-7),
        "gpt-5.6-sol": .init(input: 4e-6, output: 2e-5, cacheWrite: 5e-6, cacheRead: 4e-7),
        "gpt-5.6-terra": .init(input: 2e-6, output: 1.2e-5, cacheWrite: 2.5e-6, cacheRead: 2e-7),
        "gpt-5.6-luna": .init(input: 2e-7, output: 1.2e-6, cacheWrite: 2.5e-7, cacheRead: 2e-8),
        "gpt-5.6-codex": .init(input: 5e-6, output: 3e-5, cacheWrite: 6.25e-6, cacheRead: 5e-7),
        "gpt-5.6-codex-max": .init(input: 5e-6, output: 3e-5, cacheWrite: 6.25e-6, cacheRead: 5e-7),
        "gpt-5": .init(input: 1.25e-6, output: 1e-5, cacheWrite: nil, cacheRead: 1.25e-7),
        "gpt-5.4": .init(input: 2.5e-6, output: 1.5e-5, cacheWrite: nil, cacheRead: 2.5e-7),
        "gpt-5.3-codex": .init(input: 1.75e-6, output: 1.4e-5, cacheWrite: nil, cacheRead: 1.75e-7),
        "claude-sonnet-4-5": .init(input: 3e-6, output: 1.5e-5, cacheWrite: 3.75e-6, cacheRead: 3e-7),
        "claude-sonnet-4-6": .init(input: 3e-6, output: 1.5e-5, cacheWrite: 3.75e-6, cacheRead: 3e-7),
        "claude-sonnet-4": .init(input: 3e-6, output: 1.5e-5, cacheWrite: 3.75e-6, cacheRead: 3e-7),
        "claude-opus-4-7": .init(input: 5e-6, output: 2.5e-5, cacheWrite: 6.25e-6, cacheRead: 5e-7),
        "claude-opus-4-6": .init(input: 5e-6, output: 2.5e-5, cacheWrite: 6.25e-6, cacheRead: 5e-7),
        "claude-opus-4-5": .init(input: 5e-6, output: 2.5e-5, cacheWrite: 6.25e-6, cacheRead: 5e-7),
        "claude-haiku-4-5": .init(input: 1e-6, output: 5e-6, cacheWrite: 1.25e-6, cacheRead: 1e-7),
        "claude-fable-5": .init(input: 1e-5, output: 5e-5, cacheWrite: 1.25e-5, cacheRead: 1e-6),
        "gemini-3.1-pro-preview": .init(input: 2e-6, output: 1.2e-5, cacheWrite: nil, cacheRead: 2e-7),
        "gemini-3-pro-preview": .init(input: 2e-6, output: 1.2e-5, cacheWrite: nil, cacheRead: 2e-7),
        "gemini-3-flash-preview": .init(input: 5e-7, output: 3e-6, cacheWrite: nil, cacheRead: 5e-8),
        "gemini-3.5-flash": .init(input: 1.5e-6, output: 9e-6, cacheWrite: nil, cacheRead: 1.5e-7)
    ]

    private static let knownNamespaces: Set<String> = [
        "anthropic", "openai", "x-ai", "xai", "azure_ai", "google", "gemini"
    ]

    private static let table: [String: ModelCosts] = {
        var map: [String: ModelCosts] = [:]
        for (name, raw) in snapshot {
            map[name] = costs(from: raw)
        }
        for (name, raw) in builtinOverrides {
            map[name] = costs(from: raw)
        }
        return map
    }()

    private static let sortedKeys: [String] = table.keys.sorted { $0.count > $1.count }

    private static let grok46HighPrompt = costs(
        from: .init(input: 4e-6, output: 12e-6, cacheWrite: nil, cacheRead: 1e-6)
    )

    static func billableOutputTokens(provider: String, output: Int, reasoning: Int) -> Int {
        reasoningIncludedInOutput.contains(provider) ? output : output + reasoning
    }

    static func resolveCanonicalModelId(_ model: String) -> String {
        let aliased = resolveAlias(canonicalName(model))
        guard let slash = aliased.lastIndex(of: "/") else { return aliased }
        let leaf = String(aliased[aliased.index(after: slash)...])
        guard !leaf.isEmpty else { return aliased }
        return resolveAlias(canonicalName(leaf))
    }

    static func getModelCosts(_ model: String) -> ModelCosts? {
        let withPrefix = model.replacingOccurrences(of: #"@.*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"-\d{8}$"#, with: "", options: .regularExpression)
        let name = canonicalName(model)
        let canonical = resolveAlias(name)

        if let costs = table[withPrefix] { return costs }
        if let costs = table[canonical] { return costs }
        if let costs = table[name] { return costs }

        for key in sortedKeys where canonical == key || canonical.hasPrefix(key + "-") {
            return table[key]
        }

        let lower = canonical.lowercased()
        if lower != canonical, let costs = table[lower] { return costs }
        return nil
    }

    static func calculateCost(
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheCreationTokens: Int,
        cacheReadTokens: Int,
        webSearchRequests: Int = 0,
        speed: String = "standard",
        oneHourCacheCreationTokens: Int = 0
    ) -> Double {
        guard let base = getModelCosts(model) else { return 0 }
        let input = safe(inputTokens)
        let output = safe(outputTokens)
        let cacheRead = safe(cacheReadTokens)
        let oneHour = safe(oneHourCacheCreationTokens)
        let cacheCreation = max(safe(cacheCreationTokens), oneHour)
        let fiveMinute = max(0, cacheCreation - oneHour)
        let prompt = input + cacheRead
        let costs = tieredCosts(model: model, base: base, promptTokens: prompt)
        let multiplier = speed == "fast" ? costs.fastMultiplier : 1
        return multiplier * (
            Double(input) * costs.inputCostPerToken
            + Double(output) * costs.outputCostPerToken
            + Double(fiveMinute) * costs.cacheWriteCostPerToken
            + Double(oneHour) * costs.cacheWriteCostPerToken * oneHourCacheWriteMultiplier
            + Double(cacheRead) * costs.cacheReadCostPerToken
            + Double(safe(webSearchRequests)) * costs.webSearchCostPerRequest
        )
    }

    static func estimateUSD(provider: String, model: String?, totals: TokenUsageTotals) -> Double {
        let output = totals.outputIncludesReasoning
            ? totals.output
            : billableOutputTokens(provider: provider, output: totals.output, reasoning: totals.reasoning)
        return calculateCost(
            model: model ?? "",
            inputTokens: totals.input,
            outputTokens: output,
            cacheCreationTokens: totals.cacheWrite,
            cacheReadTokens: totals.cacheRead
        )
    }

    static func hasBillableRate(_ model: String?) -> Bool {
        guard let model, let costs = getModelCosts(model) else { return false }
        return costs.inputCostPerToken > 0
            || costs.outputCostPerToken > 0
            || costs.cacheWriteCostPerToken > 0
            || costs.cacheReadCostPerToken > 0
    }

    static func cleaned(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty, value.lowercased() != "unknown" else { return nil }
        return value
    }

    private static func costs(from raw: SnapshotEntry) -> ModelCosts {
        ModelCosts(
            inputCostPerToken: raw.input,
            outputCostPerToken: raw.output,
            cacheWriteCostPerToken: raw.cacheWrite ?? raw.input * 1.25,
            cacheReadCostPerToken: raw.cacheRead ?? raw.input * 0.1,
            webSearchCostPerRequest: webSearchCost,
            fastMultiplier: raw.fast ?? 1,
            cacheWriteCostIsExplicit: raw.cacheWrite != nil
        )
    }

    private static func resolveAlias(_ model: String) -> String {
        if let mapped = aliases[model] { return mapped }
        let lower = model.lowercased()
        if lower != model, let mapped = aliases[lower] { return mapped }
        return model
    }

    private static func canonicalName(_ model: String) -> String {
        let cleaned = model
            .replacingOccurrences(of: #"@.*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"-\d{8}$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\[[^\]]*\]$"#, with: "", options: .regularExpression)
        if aliases[cleaned] != nil || aliases[cleaned.lowercased()] != nil {
            return cleaned
        }
        return stripKnownNamespace(cleaned)
    }

    private static func stripKnownNamespace(_ model: String) -> String {
        guard let slash = model.firstIndex(of: "/") else { return model }
        let head = String(model[..<slash]).lowercased()
        guard knownNamespaces.contains(head) else { return model }
        return String(model[model.index(after: slash)...])
    }

    private static func tieredCosts(model: String, base: ModelCosts, promptTokens: Int) -> ModelCosts {
        if resolveCanonicalModelId(model) == "grok-4.6", promptTokens >= grok46PromptThreshold {
            return grok46HighPrompt
        }
        return base
    }

    private static func safe(_ value: Int) -> Int {
        value > 0 ? value : 0
    }
}
