import Foundation

enum LiveQuotaPresentation {
    static func claude(_ usage: SubscriptionUsage) -> QuotaSummary {
        var primary: QuotaSummary.Window?
        var details: [QuotaSummary.Window] = []
        if let pct = usage.fiveHourPercent {
            details.append(.init(label: "5-hour", percent: pct / 100, resetsAt: usage.fiveHourResetsAt))
        }
        if let pct = usage.sevenDayPercent {
            let weekly = QuotaSummary.Window(
                label: "Weekly",
                percent: pct / 100,
                resetsAt: usage.sevenDayResetsAt
            )
            primary = weekly
            details.append(weekly)
        }
        if let pct = usage.sevenDayOpusPercent {
            details.append(.init(
                label: "Weekly · Opus",
                percent: pct / 100,
                resetsAt: usage.sevenDayOpusResetsAt
            ))
        }
        if let pct = usage.sevenDaySonnetPercent {
            details.append(.init(
                label: "Weekly · Sonnet",
                percent: pct / 100,
                resetsAt: usage.sevenDaySonnetResetsAt
            ))
        }
        for scoped in usage.scopedWeekly {
            details.append(.init(
                label: "Weekly · \(scoped.label)",
                percent: scoped.percent / 100,
                resetsAt: scoped.resetsAt
            ))
        }
        return QuotaSummary(
            providerFilter: .claude,
            connection: .connected,
            primary: primary,
            details: details,
            planLabel: usage.tier.displayName,
            footerLines: ["Source: Claude CLI"]
        )
    }

    static func codex(_ usage: CodexUsage) -> QuotaSummary {
        var primary: QuotaSummary.Window?
        var details: [QuotaSummary.Window] = []
        if let window = usage.primary {
            let row = QuotaSummary.Window(
                label: window.windowLabel,
                percent: window.usedPercent / 100,
                resetsAt: window.resetsAt
            )
            primary = row
            details.append(row)
        }
        if let window = usage.secondary {
            let row = QuotaSummary.Window(
                label: window.windowLabel,
                percent: window.usedPercent / 100,
                resetsAt: window.resetsAt
            )
            if primary == nil { primary = row }
            details.append(row)
        }
        for extra in usage.additionalLimits {
            if let p = extra.primary, p.usedPercent > 0 {
                details.append(.init(
                    label: "\(extra.name) · \(p.windowLabel)",
                    percent: p.usedPercent / 100,
                    resetsAt: p.resetsAt
                ))
            }
            if let s = extra.secondary, s.usedPercent > 0 {
                details.append(.init(
                    label: "\(extra.name) · \(s.windowLabel)",
                    percent: s.usedPercent / 100,
                    resetsAt: s.resetsAt
                ))
            }
        }
        if let credits = usage.creditLimit {
            let row = QuotaSummary.Window(
                label: credits.shortLabel,
                percent: credits.usedPercent / 100,
                resetsAt: credits.resetsAt
            )
            if primary == nil { primary = row }
            details.append(row)
        }
        var footerLines: [String] = []
        if let balance = usage.creditsBalance, balance > 0 {
            let inCredits = usage.hasCredits == true
            let formatter = NumberFormatter()
            formatter.numberStyle = inCredits ? .decimal : .currency
            formatter.maximumFractionDigits = inCredits ? 0 : 2
            formatter.roundingMode = .halfUp
            formatter.locale = Locale(identifier: "en_US")
            if !inCredits { formatter.currencyCode = "USD" }
            let fallback = inCredits ? "\(Int(balance.rounded()))" : "$\(balance)"
            let formatted = formatter.string(from: NSNumber(value: balance)) ?? fallback
            footerLines.append("Credits remaining · \(formatted)")
        }
        if usage.creditLimit == nil, usage.creditsUnlimited == true {
            footerLines.append("Credits · Unlimited")
        }
        footerLines.append("Source: Codex CLI")
        return QuotaSummary(
            providerFilter: .codex,
            connection: .connected,
            primary: primary,
            details: details,
            planLabel: usage.plan.displayName,
            footerLines: footerLines
        )
    }

    static func gemini(_ usage: GeminiUsage) -> QuotaSummary {
        windows(
            provider: .gemini,
            details: usage.details.map {
                .init(label: $0.label, percent: $0.usedPercent / 100, resetsAt: $0.resetsAt)
            },
            planLabel: usage.plan,
            footer: ["Source: Gemini CLI"]
        )
    }

    static func copilot(_ usage: CopilotUsage) -> QuotaSummary {
        windows(
            provider: .copilot,
            details: usage.details.map {
                .init(label: $0.label, percent: $0.usedPercent / 100, resetsAt: $0.resetsAt)
            },
            planLabel: usage.plan,
            footer: ["Source: GitHub Copilot"]
        )
    }

    static func antigravity(_ usage: AntigravityUsage) -> QuotaSummary {
        windows(
            provider: .antigravity,
            details: usage.details.map {
                .init(label: $0.label, percent: $0.usedPercent / 100, resetsAt: $0.resetsAt)
            },
            planLabel: usage.plan,
            footer: ["Source: Antigravity app"]
        )
    }

    static func kimi(_ usage: KimiUsage) -> QuotaSummary {
        var details: [QuotaSummary.Window] = []
        if let primary = usage.primary {
            details.append(.init(
                label: primary.label,
                percent: primary.usedPercent / 100,
                resetsAt: primary.resetsAt
            ))
        }
        details.append(contentsOf: usage.details.map {
            .init(label: $0.label, percent: $0.usedPercent / 100, resetsAt: $0.resetsAt)
        })
        return windows(
            provider: .kimiCode,
            details: details,
            planLabel: usage.plan,
            footer: ["Source: Kimi CLI"]
        )
    }

    private static func windows(
        provider: ProviderFilter,
        details: [QuotaSummary.Window],
        planLabel: String?,
        footer: [String]
    ) -> QuotaSummary {
        QuotaSummary(
            providerFilter: provider,
            connection: .connected,
            primary: details.first,
            details: details,
            planLabel: planLabel,
            footerLines: footer
        )
    }

    static func disconnected(_ provider: CapacityDockProvider, reason: String? = nil) -> QuotaSummary {
        QuotaSummary(
            providerFilter: provider.legacyFilter ?? .all,
            connection: .disconnected,
            primary: nil,
            details: [],
            planLabel: nil,
            footerLines: reason.map { [$0] } ?? []
        )
    }

    static func failure(
        _ provider: CapacityDockProvider,
        message: String,
        terminal: Bool,
        previous: QuotaSummary?
    ) -> QuotaSummary {
        if terminal {
            return QuotaSummary(
                providerFilter: provider.legacyFilter ?? .all,
                connection: .terminalFailure(reason: message),
                primary: previous?.primary,
                details: previous?.details ?? [],
                planLabel: previous?.planLabel,
                footerLines: [message]
            )
        }
        if let previous, previous.primary != nil || !previous.details.isEmpty {
            return QuotaSummary(
                providerFilter: previous.providerFilter,
                connection: .transientFailure,
                primary: previous.primary,
                details: previous.details,
                planLabel: previous.planLabel,
                footerLines: previous.footerLines + [message]
            )
        }
        return QuotaSummary(
            providerFilter: provider.legacyFilter ?? .all,
            connection: .transientFailure,
            primary: nil,
            details: [],
            planLabel: nil,
            footerLines: [message]
        )
    }
}
