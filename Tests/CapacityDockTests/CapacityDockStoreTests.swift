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
