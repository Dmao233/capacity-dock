import Foundation
import Testing
@testable import CapacityDock

@Suite("Grok Build subscription service")
@MainActor
struct GrokBuildSubscriptionServiceTests {
    @Test("Grok Build credential discovery prefers the current OIDC login")
    func prefersOIDCCredential() throws {
        let data = Data(#"""
        {
          "https://accounts.x.ai/sign-in": {
            "key": "synthetic-legacy-token",
            "expires_at": "2026-09-08T10:00:00Z"
          },
          "https://auth.x.ai::synthetic-principal": {
            "key": "synthetic-oidc-token",
            "auth_mode": "oidc",
            "expires_at": "2026-09-09T10:00:00Z"
          }
        }
        """#.utf8)

        let credential = try GrokBuildCredentialStore.decode(data)

        #expect(credential.accessToken == "synthetic-oidc-token")
        #expect(credential.authMode == "oidc")
        #expect(credential.expiresAt == ISO8601DateFormatter().date(from: "2026-09-09T10:00:00Z"))
    }

    @Test("one refresh reuses Grok Build login for quota and plan")
    func refreshesWithExistingLogin() async throws {
        let requests = RequestCapture()
        let credential = GrokBuildCredentialStore.Credential(
            accessToken: "synthetic-oidc-token",
            authMode: "oidc",
            expiresAt: ISO8601DateFormatter().date(from: "2026-09-09T10:00:00Z")
        )
        let deps = GrokBuildSubscriptionService.Deps(
            loadCredential: { credential },
            fetch: { request in
                await requests.record(request)
                let body: String
                switch request.url?.path {
                case "/v1/billing":
                    body = #"""
                    {"config":{"creditUsagePercent":2,"currentPeriod":{"end":"2026-09-06T17:52:03Z"}}}
                    """#
                case "/v1/settings":
                    body = #"{"subscription_tier_display":"SuperGrok Heavy"}"#
                default:
                    Issue.record("Unexpected Grok endpoint")
                    body = "{}"
                }
                return (
                    Data(body.utf8),
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            }
        )

        let result = try await GrokBuildSubscriptionService.refresh(
            deps: deps,
            now: ISO8601DateFormatter().date(from: "2026-09-01T10:00:00Z")!
        )
        let captured = await requests.values

        #expect(result.connection == .connected)
        #expect(result.primary?.label == "Weekly")
        #expect(result.primary?.percent == 0.02)
        #expect(result.primary?.resetsAt == ISO8601DateFormatter().date(from: "2026-09-06T17:52:03Z"))
        #expect(result.planLabel == "SuperGrok Heavy")
        #expect(result.footerLines == ["Source: Grok Build"])
        #expect(captured.map(\.url?.path) == ["/v1/billing", "/v1/settings"])
        #expect(captured.allSatisfy {
            $0.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-oidc-token"
                && $0.value(forHTTPHeaderField: "x-xai-token-auth") == "xai-grok-cli"
        })
    }

    @Test("missing and expired Grok Build logins never reach the network")
    func rejectsUnavailableLoginBeforeFetching() async throws {
        let requests = RequestCapture()
        let fetch: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse) = { request in
            await requests.record(request)
            return (
                Data("{}".utf8),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        }
        let now = ISO8601DateFormatter().date(from: "2026-09-01T10:00:00Z")!

        do {
            _ = try await GrokBuildSubscriptionService.refresh(
                deps: .init(loadCredential: { nil }, fetch: fetch),
                now: now
            )
            Issue.record("Expected a missing-login failure")
        } catch let error as GrokBuildSubscriptionService.FetchError {
            #expect(error == .noCredentials)
        }

        let expired = GrokBuildCredentialStore.Credential(
            accessToken: "synthetic-expired-token",
            authMode: "oidc",
            expiresAt: now.addingTimeInterval(-1)
        )
        do {
            _ = try await GrokBuildSubscriptionService.refresh(
                deps: .init(loadCredential: { expired }, fetch: fetch),
                now: now
            )
            Issue.record("Expected an expired-login failure")
        } catch let error as GrokBuildSubscriptionService.FetchError {
            #expect(error == .expiredSession)
        }

        #expect(await requests.values.isEmpty)
    }

    @Test("Grok billing failures retain actionable classifications")
    func classifiesBillingFailures() async throws {
        let credential = GrokBuildCredentialStore.Credential(
            accessToken: "synthetic-oidc-token",
            authMode: "oidc",
            expiresAt: nil
        )
        let cases: [(Int, GrokBuildSubscriptionService.FetchError)] = [
            (401, .authenticationRejected),
            (403, .authenticationRejected),
            (429, .rateLimited),
            (503, .providerUnavailable),
            (418, .parseFailure),
        ]

        for (status, expected) in cases {
            let deps = GrokBuildSubscriptionService.Deps(
                loadCredential: { credential },
                fetch: { request in
                    (
                        Data("{}".utf8),
                        HTTPURLResponse(
                            url: request.url!,
                            statusCode: status,
                            httpVersion: nil,
                            headerFields: nil
                        )!
                    )
                }
            )
            do {
                _ = try await GrokBuildSubscriptionService.refresh(deps: deps)
                Issue.record("Expected HTTP \(status) to fail")
            } catch let error as GrokBuildSubscriptionService.FetchError {
                #expect(error == expected)
            }
        }
    }

    @Test("on-demand billing is a safe fallback when percent is absent")
    func usesOnDemandFallback() async throws {
        let credential = GrokBuildCredentialStore.Credential(
            accessToken: "synthetic-oidc-token",
            authMode: "oidc",
            expiresAt: nil
        )
        let deps = GrokBuildSubscriptionService.Deps(
            loadCredential: { credential },
            fetch: { request in
                let body: String
                let status: Int
                if request.url?.path == "/v1/billing" {
                    body = #"{"config":{"onDemandUsed":{"val":25},"onDemandCap":{"val":100},"billingPeriodEnd":"2026-10-01T10:00:00Z","subscriptionTier":"supergrok"}}"#
                    status = 200
                } else {
                    body = "{}"
                    status = 503
                }
                return (
                    Data(body.utf8),
                    HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
                )
            }
        )

        let result = try await GrokBuildSubscriptionService.refresh(
            deps: deps,
            now: ISO8601DateFormatter().date(from: "2026-09-01T10:00:00Z")!
        )

        #expect(result.primary?.percent == 0.25)
        #expect(result.primary?.label == "Monthly")
        #expect(result.planLabel == "SuperGrok")
    }

    @Test("cancellation during the optional plan request cancels the refresh")
    func cancellationWinsDuringPlanFetch() async throws {
        let credential = GrokBuildCredentialStore.Credential(
            accessToken: "synthetic-oidc-token",
            authMode: "oidc",
            expiresAt: nil
        )
        let deps = GrokBuildSubscriptionService.Deps(
            loadCredential: { credential },
            fetch: { request in
                if request.url?.path == "/v1/settings" {
                    throw CancellationError()
                }
                return (
                    Data(#"{"config":{"creditUsagePercent":2}}"#.utf8),
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                )
            }
        )

        await #expect(throws: CancellationError.self) {
            try await GrokBuildSubscriptionService.refresh(deps: deps)
        }
    }

    private actor RequestCapture {
        private(set) var values: [URLRequest] = []
        func record(_ request: URLRequest) { values.append(request) }
    }
}
