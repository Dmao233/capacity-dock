import Foundation
import Testing
@testable import CapacityDock

@Suite("Quota reset stamp")
struct QuotaSummaryResetsAtLabelTests {
    private let locale = Locale(identifier: "zh-Hans")
    private let timeZone = TimeZone(identifier: "Asia/Shanghai")!

    @Test("00:00 through 04:59 is 凌晨, not 上午")
    func weeHoursUseWeeHoursPeriod() {
        #expect(stamp(hour: 0, minute: 0).contains("凌晨"))
        #expect(!stamp(hour: 0, minute: 0).contains("上午"))
        #expect(stamp(hour: 1, minute: 41).contains("凌晨"))
        #expect(stamp(hour: 1, minute: 41).contains("1:41"))
        #expect(!stamp(hour: 1, minute: 41).contains("上午"))
        #expect(stamp(hour: 4, minute: 59).contains("凌晨"))
        #expect(!stamp(hour: 4, minute: 59).contains("上午"))
    }

    @Test("05:00 stays 上午")
    func fiveAMStaysMorning() {
        let label = stamp(hour: 5, minute: 0)
        #expect(label.contains("上午"))
        #expect(!label.contains("凌晨"))
    }

    @Test("afternoon keeps 下午")
    func afternoonKeepsAfternoon() {
        let label = stamp(hour: 13, minute: 20)
        #expect(label.contains("下午"))
        #expect(!label.contains("凌晨"))
    }

    @Test("English keeps AM")
    func englishKeepsAM() {
        let label = QuotaSummary.Window.formatResetsAt(
            date(hour: 1, minute: 41),
            locale: Locale(identifier: "en_US"),
            timeZone: timeZone
        )
        #expect(label.contains("AM"))
        #expect(!label.contains("凌晨"))
    }

    private func stamp(hour: Int, minute: Int) -> String {
        QuotaSummary.Window.formatResetsAt(
            date(hour: hour, minute: minute),
            locale: locale,
            timeZone: timeZone
        )
    }

    private func date(hour: Int, minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 3, hour: hour, minute: minute
        ))!
    }
}
