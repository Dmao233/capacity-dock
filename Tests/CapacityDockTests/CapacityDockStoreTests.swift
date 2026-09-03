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
}
