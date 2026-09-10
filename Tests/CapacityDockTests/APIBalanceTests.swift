import Foundation
import Testing
@testable import CapacityDock

@Suite("API balance accounting")
struct APIBalanceTests {
    func relay(path: String = "data.balance", divisor: String = "1") -> APIBalanceAccount {
        APIBalanceAccount(name: "Fixture relay", kind: .relay, endpoint: "https://example.com/balance", amountPath: path, divisor: divisor)
    }

    @Test func deepSeekCurrenciesAndCredits() throws {
        let data = Data(#"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"110.01","granted_balance":"10.00","topped_up_balance":"100.01"},{"currency":"USD","total_balance":2.50}]}"#.utf8)
        let result = try APIBalanceParser.parse(data, account: APIBalanceAccount())
        #expect(result.amounts.count == 2)
        #expect(result.amounts[0].value == Decimal(string: "110.01"))
        #expect(result.amounts[0].granted == 10)
        #expect(result.amounts[0].toppedUp == Decimal(string: "100.01"))
        #expect(result.amounts[1].text == "2.50 USD")
    }

    @Test(arguments: [
        #"{"is_available":false,"balance_infos":[]}"#,
        #"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":true}]}"#,
        #"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"0oops"}]}"#,
        #"{"error":"unauthorized"}"#,
        #"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"1"},{"currency":"CNY","total_balance":"2"}]}"#
    ])
    func missingAndInvalidNeverBecomeZero(json: String) {
        #expect(throws: (any Error).self) { try APIBalanceParser.parse(Data(json.utf8), account: APIBalanceAccount()) }
    }

    @Test func zeroIsARealBalance() throws {
        let result = try APIBalanceParser.parse(Data(#"{"is_available":false,"balance_infos":[{"currency":"CNY","total_balance":"0.00"}]}"#.utf8), account: APIBalanceAccount())
        #expect(result.amounts[0].value == 0)
        #expect(result.isAvailable == false)
    }

    @Test func relayUnitsAndArrayPaths() throws {
        let result = try APIBalanceParser.parse(Data(#"{"data":[{"quota":12345}]}"#.utf8), account: relay(path: "data.0.quota", divisor: "100"))
        #expect(result.amounts[0].value == Decimal(string: "123.45"))
        let negative = try APIBalanceParser.parse(Data(#"{"data":{"balance":"-0.10"}}"#.utf8), account: relay())
        #expect(negative.amounts[0].value == Decimal(string: "-0.10"))
    }

    @Test(arguments: [#"{"data":{"balance":null}}"#, #"{"data":{}}"#, #"{"data":{"balance":true}}"#, #"{"success":false,"data":{"balance":100}}"#])
    func relayErrorBodies(json: String) {
        #expect(throws: (any Error).self) { try APIBalanceParser.parse(Data(json.utf8), account: relay()) }
    }

    @Test(arguments: ["http://example.com/balance", "https://key@example.com/balance", "https://example.com/balance?key=secret", "https://example.com/balance#secret", "file:///tmp/balance", "not a url"])
    func credentialsHaveAnExplicitHTTPSDestination(endpoint: String) {
        var account = relay()
        account.endpoint = endpoint
        #expect(throws: (any Error).self) { try account.validatedURL() }
    }

    @Test(arguments: ["0", "-1", "NaN", "1oops", ""])
    func invalidDivisors(divisor: String) {
        #expect(throws: (any Error).self) { try relay(divisor: divisor).validatedURL() }
    }

    @Test func decimalMathDoesNotIntroduceFloatDrift() throws {
        let first = APIBalanceAccount()
        let second = APIBalanceAccount()
        let a = APIBalanceSnapshot(account: first, amounts: [.init(currency: "CNY", value: Decimal(string: "0.1")!), .init(currency: "USD", value: 2)], fetchedAt: Date())
        let b = APIBalanceSnapshot(account: second, amounts: [.init(currency: "CNY", value: Decimal(string: "0.2")!)], fetchedAt: Date())
        let total = try #require(APIBalanceParser.total(accounts: [first, second], snapshots: [first.id: a, second.id: b]))
        #expect(total.first(where: { $0.currency == "CNY" })?.value == Decimal(string: "0.3"))
        #expect(total.first(where: { $0.currency == "USD" })?.value == 2)
        #expect(APIBalanceParser.total(accounts: [first, second], snapshots: [first.id: a]) == nil)
        var edited = first
        edited.endpoint = "https://different.example.com"
        #expect(APIBalanceParser.total(accounts: [edited], snapshots: [first.id: a]) == nil)
    }

    @Test @MainActor func cachedBalancesSurviveRestartButEditsInvalidateThem() throws {
        let suite = "APIBalanceTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(APIBalanceStore(defaults: defaults).menuText == nil)
        let account = APIBalanceAccount()
        let snapshot = APIBalanceSnapshot(account: account, amounts: [.init(currency: "CNY", value: 12)], fetchedAt: Date().addingTimeInterval(-600))
        defaults.set(try JSONEncoder().encode([account]), forKey: "CapacityDockAPIBalanceAccounts")
        defaults.set(try JSONEncoder().encode([account.id: snapshot]), forKey: "CapacityDockAPIBalanceCache")
        #expect(APIBalanceStore(defaults: defaults).menuText == "12.00 CNY ↻")
        var changed = account
        changed.name = "New account settings"
        defaults.set(try JSONEncoder().encode([changed]), forKey: "CapacityDockAPIBalanceAccounts")
        #expect(APIBalanceStore(defaults: defaults).menuText == "—")
    }
}

private final class BalanceFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        let status = path == "/unauthorized" ? 401 : 200
        let body: Data
        if path == "/oversized" { body = Data(repeating: 32, count: 262_145) }
        else if request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-only" {
            body = Data(#"{"data":{"balance":"12.34"}}"#.utf8)
        } else { body = Data(#"{"error":"missing fixture credential"}"#.utf8) }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite("API balance offline transport")
struct APIBalanceTransportTests {
    @Test(arguments: ["balance", "unauthorized", "oversized"])
    func requestHandling(path: String) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BalanceFixtureProtocol.self]
        let account = APIBalanceAccount(name: "Offline fixture", kind: .relay, endpoint: "https://fixture.invalid/\(path)")
        do {
            let result = try await APIBalanceClient.fetch(account: account, key: "fixture-only", configuration: configuration)
            #expect(path == "balance")
            #expect(result.amounts.first?.value == Decimal(string: "12.34"))
        } catch {
            #expect(path != "balance")
            #expect(error is APIBalanceError)
        }
    }
}
