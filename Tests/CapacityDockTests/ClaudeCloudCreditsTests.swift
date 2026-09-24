import Foundation
import Testing
@testable import CapacityDock

@Suite("Claude cloud session credits")
struct ClaudeCloudCreditsTests {
    /// Trimmed from a real `/usage` response; the credits live under the
    /// codename `iguana_necktie`.
    private static let payload = """
    {
      "five_hour": {"utilization": 59.0, "resets_at": "2026-09-24T10:20:00.684430+00:00",
                    "limit_dollars": null, "used_dollars": null, "remaining_dollars": null},
      "seven_day": {"utilization": 35.0, "resets_at": "2026-09-28T00:00:00.684448+00:00"},
      "seven_day_opus": null,
      "seven_day_sonnet": null,
      "iguana_necktie": {"utilization": 35.523716, "resets_at": "2026-11-05T07:59:00+00:00",
                         "limit_dollars": 100, "used_dollars": 35.523716,
                         "remaining_dollars": 64.47628399999999, "locked_reason": null},
      "nimbus_quill": {"utilization": 0.0, "resets_at": null, "limit_dollars": null},
      "extra_usage": {"is_enabled": false, "monthly_limit": null},
      "limits": [{"kind": "session", "percent": 59, "resets_at": "2026-09-24T10:20:00.684430+00:00", "scope": null}]
    }
    """

    @Test("iguana_necktie decodes into cloud credits")
    func decodesCredits() throws {
        let usage = try ClaudeSubscriptionService.parseUsage(Data(Self.payload.utf8), rawTier: "pro")
        let credits = try #require(usage.cloudCredits)
        #expect(credits.limitDollars == 100)
        #expect(abs(credits.remainingDollars - 64.476284) < 0.0001)
        #expect(credits.expiresAt == ISO8601DateFormatter().date(from: "2026-11-05T07:59:00Z"))
        #expect(usage.fiveHourPercent == 59)
    }

    @Test("Credits render as a remaining-dollars row after the plan limits")
    func presentsCredits() throws {
        let usage = try ClaudeSubscriptionService.parseUsage(Data(Self.payload.utf8), rawTier: "pro")
        let summary = LiveQuotaPresentation.claude(usage)
        let row = try #require(summary.details.last)
        #expect(row.label == "Cloud session credits")
        #expect(row.valueLabel == "$64 of $100 left")
        #expect(abs(row.percent - 0.35523716) < 0.0001)
        #expect(row.expires)
        #expect(summary.headlineWindow?.label == "Weekly")
        #expect(CapacityDockQuotaPresentation.displayLabel(row.label) == "Cloud credits")
    }

    @Test("Expiry reads as a date, not a weekly reset")
    func expiryLabel() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-11-05T07:59:00Z"))
        let shanghai = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let english = QuotaSummary.Window.formatExpiresAt(date, locale: Locale(identifier: "en_US"), timeZone: shanghai)
        #expect(english.hasPrefix("Expires Nov 5"))
        #expect(english.contains("3:59"))
        let chinese = QuotaSummary.Window.formatExpiresAt(date, locale: Locale(identifier: "zh_CN"), timeZone: shanghai)
        #expect(chinese.contains("11月5日"))
        #expect(chinese.contains("15:59"))
    }

    @Test("Missing or zero-limit credits add no row")
    func noCredits() throws {
        let json = #"{"seven_day": {"utilization": 10, "resets_at": null}, "iguana_necktie": {"limit_dollars": null}}"#
        let usage = try ClaudeSubscriptionService.parseUsage(Data(json.utf8), rawTier: "pro")
        #expect(usage.cloudCredits == nil)
        #expect(LiveQuotaPresentation.claude(usage).details.map(\.label) == ["Weekly"])
    }
}
