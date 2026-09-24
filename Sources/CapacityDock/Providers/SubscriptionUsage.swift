import Foundation

struct SubscriptionUsage: Sendable, Equatable {
    enum Tier: String, Sendable, Equatable {
        case pro
        case max5x
        case max20x
        case team
        case enterprise
        case unknown

        var displayName: String {
            switch self {
            case .pro: "Pro"
            case .max5x: "Max 5x"
            case .max20x: "Max 20x"
            case .team: "Team"
            case .enterprise: "Enterprise"
            case .unknown: "Subscription"
            }
        }
    }

    /// A model-scoped weekly limit from the `limits` array (e.g. the Fable
    /// bucket). The label is the API's `scope.model.display_name`, so new
    /// model buckets show up without a client update.
    struct ScopedWindow: Sendable, Equatable {
        let label: String
        let percent: Double
        let resetsAt: Date?
    }

    /// Prepaid dollar credits for Claude Code cloud sessions (the usage
    /// endpoint's `iguana_necktie` block): a fixed grant that expires rather
    /// than resets.
    struct CloudCredits: Sendable, Equatable {
        let limitDollars: Double
        let usedDollars: Double
        let remainingDollars: Double
        let expiresAt: Date?
    }

    let tier: Tier
    let rawTier: String?
    let fiveHourPercent: Double?
    let fiveHourResetsAt: Date?
    let sevenDayPercent: Double?
    let sevenDayResetsAt: Date?
    let sevenDayOpusPercent: Double?
    let sevenDayOpusResetsAt: Date?
    let sevenDaySonnetPercent: Double?
    let sevenDaySonnetResetsAt: Date?
    let scopedWeekly: [ScopedWindow]
    let fetchedAt: Date
    var cloudCredits: CloudCredits? = nil

    static func tier(from raw: String?) -> Tier {
        guard let raw = raw?.lowercased() else { return .unknown }
        if raw.contains("max_20x") || raw.contains("max20x") || raw.contains("max-20x") { return .max20x }
        if raw.contains("max_5x") || raw.contains("max5x") || raw.contains("max-5x") { return .max5x }
        if raw.contains("max") { return .max5x }
        if raw.contains("pro") { return .pro }
        if raw.contains("team") { return .team }
        if raw.contains("enterprise") { return .enterprise }
        return .unknown
    }
}
