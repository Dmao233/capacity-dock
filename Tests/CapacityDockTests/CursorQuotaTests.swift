import Foundation
import Testing
@testable import CapacityDock

@Suite("Cursor quota")
struct CursorQuotaDecodeTests {
    @Test("usage-summary JSON maps monthly percent and plan")
    func decodesUsageSummary() throws {
        let data = Data("""
        {
          "billingCycleStart": "2026-08-01T00:00:00Z",
          "billingCycleEnd": "2026-09-01T00:00:00Z",
          "membershipType": "pro",
          "individualUsage": {
            "plan": {
              "enabled": true,
              "used": 850,
              "limit": 2000,
              "remaining": 1150,
              "autoPercentUsed": 20,
              "apiPercentUsed": 65,
              "totalPercentUsed": 42.5
            }
          }
        }
        """.utf8)
        let summary = try CursorSubscriptionService.decode(data)
        #expect(summary.connection == .connected)
        #expect(summary.headlineWindow?.percent == 0.425)
        #expect(summary.planLabel != nil)
    }
}
