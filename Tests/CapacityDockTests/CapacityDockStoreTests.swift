import Foundation
import Testing
@testable import CapacityDock

@Suite("Capacity Dock store")
struct CapacityDockStoreTests {
    @MainActor
    @Test("shipping store does not invent connected usage")
    func liveStoreHasNoCannedQuotas() {
        let store = CapacityDockStore(summaries: [:])
        #expect(store.capacityDockQuotaSummary(for: .grok) == nil)
        #expect(store.capacityDockQuotaSummary(for: .claude) == nil)
        #expect(CapacityDockQuotaPresentation.ringPercentLabel(quota: nil) == "-")
    }

    @Test("transient fetch failure keeps last-known windows as an established session")
    func transientFailureKeepsLastKnownSession() {
        let previous = QuotaSummary(
            providerFilter: .grok,
            connection: .connected,
            primary: .init(label: "Weekly", percent: 0.23, resetsAt: nil),
            details: [.init(label: "Weekly", percent: 0.23, resetsAt: nil)],
            planLabel: "Heavy",
            footerLines: ["Source: Grok Build"]
        )
        let failed = LiveQuotaPresentation.failure(
            .grok,
            message: "Network error fetching Grok quota.",
            terminal: false,
            previous: previous
        )

        #expect(failed.connection == .transientFailure)
        #expect(failed.primary == previous.primary)
        #expect(failed.details == previous.details)
        #expect(failed.isEstablishedSession)
        #expect(CapacityDockQuotaPresentation.ringPercentLabel(quota: failed) == "23%")
    }

    @Test("empty transient failure and logout are not established sessions")
    func emptyFailureAndDisconnectAreNotSessions() {
        let emptyFailure = LiveQuotaPresentation.failure(
            .grok,
            message: "Network error fetching Grok quota.",
            terminal: false,
            previous: nil
        )
        let disconnected = LiveQuotaPresentation.disconnected(.grok, reason: "No credentials")

        #expect(emptyFailure.connection == .transientFailure)
        #expect(!emptyFailure.isEstablishedSession)
        #expect(!disconnected.isEstablishedSession)
        #expect(CapacityDockQuotaPresentation.ringPercentLabel(quota: disconnected) == "-")
    }
}

@Suite("Live refresh schedule")
struct LiveRefreshScheduleTests {
    @Test("Connected providers poll every minute; unconfigured ones back off")
    func intervals() {
        #expect(LiveRefreshSchedule.interval(after: .connected) == 60)
        #expect(LiveRefreshSchedule.interval(after: .transientFailure) == 120)
        #expect(LiveRefreshSchedule.interval(after: .disconnected) == 300)
        #expect(LiveRefreshSchedule.interval(after: nil) == 300)
        #expect(LiveRefreshSchedule.interval(after: .terminalFailure(reason: nil)) == 600)
    }

    @Test("A provider is due when it has never run or its time has come")
    func due() {
        let now = Date(timeIntervalSince1970: 1_000)
        #expect(LiveRefreshSchedule.isDue(nil, now: now))
        #expect(LiveRefreshSchedule.isDue(now, now: now))
        #expect(LiveRefreshSchedule.isDue(now.addingTimeInterval(1), now: now))
        #expect(!LiveRefreshSchedule.isDue(now.addingTimeInterval(LiveRefreshSchedule.tickSlack + 1), now: now))
    }

    @Test("A slow refresh is still due on the next timer tick")
    func deadlineFromCycleStart() {
        let start = Date(timeIntervalSince1970: 1_000)
        let deadline = LiveRefreshSchedule.deadline(after: .connected, startedAt: start)
        // The request took 10 s; the next 60 s tick must still pick it up.
        #expect(LiveRefreshSchedule.isDue(deadline, now: start.addingTimeInterval(60)))
        // A tick that fires a second early (timer tolerance) still counts.
        #expect(LiveRefreshSchedule.isDue(deadline, now: start.addingTimeInterval(59)))
        #expect(!LiveRefreshSchedule.isDue(deadline, now: start.addingTimeInterval(30)))
        let terminal = LiveRefreshSchedule.deadline(after: .terminalFailure(reason: nil), startedAt: start)
        #expect(LiveRefreshSchedule.isDue(terminal, now: start.addingTimeInterval(600)))
    }
}
