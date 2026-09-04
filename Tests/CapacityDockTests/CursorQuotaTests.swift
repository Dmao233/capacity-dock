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

    @Test("agent API planUsage maps monthly percent and epoch reset")
    func decodesPlanUsage() throws {
        let data = Data("""
        {
          "billingCycleStart": "1785504000000",
          "billingCycleEnd": "1788182400000",
          "planUsage": {
            "includedSpend": 850,
            "limit": 2000,
            "autoPercentUsed": 20,
            "apiPercentUsed": 65,
            "totalPercentUsed": 42.5
          }
        }
        """.utf8)
        let summary = try CursorSubscriptionService.decode(data, membershipType: "pro")
        #expect(summary.connection == .connected)
        #expect(summary.primary?.percent == 0.425)
        #expect(summary.details.map(\.label) == ["Monthly", "Auto", "API"])
        #expect(summary.planLabel == "Pro")
        #expect(summary.primary?.resetsAt == Date(timeIntervalSince1970: 1_788_182_400))
    }

    @Test @MainActor
    func refreshPostsBearerTokenToAgentAPI() async throws {
        let token = Self.syntheticJWT()
        nonisolated(unsafe) var recorded: URLRequest?
        let deps = CursorSubscriptionService.Deps(
            loadAccessToken: { token },
            loadMembershipType: { "pro" },
            fetch: { request in
                recorded = request
                return (
                    Data("""
                    {
                      "billingCycleEnd": "1788182400000",
                      "planUsage": { "totalPercentUsed": 42.5 }
                    }
                    """.utf8),
                    HTTPURLResponse(
                        url: request.url ?? CursorSubscriptionService.usageURL,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            }
        )

        let summary = try await CursorSubscriptionService.refresh(deps: deps)
        #expect(summary.connection == .connected)
        #expect(recorded?.url == CursorSubscriptionService.usageURL)
        #expect(recorded?.httpMethod == "POST")
        #expect(recorded?.value(forHTTPHeaderField: "Authorization") == "Bearer \(token)")
        #expect(recorded?.value(forHTTPHeaderField: "Connect-Protocol-Version") == "1")
        #expect(recorded?.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(recorded?.httpBody == Data("{}".utf8))
    }

    private static func syntheticJWT(
        expiresAt: Date = Date(timeIntervalSinceNow: 3_600)
    ) -> String {
        let header = Data(#"{"alg":"none","typ":"JWT"}"#.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let expiration = Int(expiresAt.timeIntervalSince1970)
        let payload = Data(#"{"sub":"auth0|user_123","exp":\#(expiration)}"#.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "\(header).\(payload).synthetic-signature"
    }
}
