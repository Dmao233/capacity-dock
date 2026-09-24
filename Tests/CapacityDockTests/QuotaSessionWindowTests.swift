import Foundation
import Testing
@testable import CapacityDock

@Suite("Quota session window")
struct QuotaSessionWindowTests {
    private func summary(primary: QuotaSummary.Window?, details: [QuotaSummary.Window]) -> QuotaSummary {
        QuotaSummary(providerFilter: .claude, connection: .connected, primary: primary,
                     details: details, planLabel: nil, footerLines: [])
    }

    @Test("Claude weekly headline gets the 5h window as the inner ring")
    func claudeSessionWindow() {
        let fiveHour = QuotaSummary.Window(label: "5-hour", percent: 0.64, resetsAt: nil)
        let weekly = QuotaSummary.Window(label: "Weekly", percent: 0.27, resetsAt: nil)
        let quota = summary(primary: weekly, details: [fiveHour, weekly])
        #expect(quota.headlineWindow == weekly)
        #expect(quota.sessionWindow == fiveHour)
    }

    @Test("No inner ring when 5h is the only window or only per-model scoped")
    func noSessionWindow() {
        let fiveHour = QuotaSummary.Window(label: "5-hour", percent: 0.4, resetsAt: nil)
        #expect(summary(primary: fiveHour, details: [fiveHour]).sessionWindow == nil)

        let weekly = QuotaSummary.Window(label: "Weekly", percent: 0.2, resetsAt: nil)
        let scoped = QuotaSummary.Window(label: "GPT-5.3-Codex-Spark · 5-hour", percent: 0.9, resetsAt: nil)
        #expect(summary(primary: weekly, details: [weekly, scoped]).sessionWindow == nil)

        let monthly = QuotaSummary.Window(label: "Monthly", percent: 0.5, resetsAt: nil)
        #expect(summary(primary: monthly, details: [monthly]).sessionWindow == nil)
    }
}
