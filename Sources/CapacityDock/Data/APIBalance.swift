import Foundation
import CoreFoundation
import Observation

struct APIBalanceAccount: Codable, Equatable, Identifiable, Sendable {
    var id = UUID().uuidString
    var name = "DeepSeek"
    var kind = Kind.deepSeek
    var endpoint = ""
    var amountPath = "data.balance"
    var currency = "USD"
    var divisor = "1"
    enum Kind: String, Codable, CaseIterable, Sendable { case deepSeek, relay }
    var credentialID: String { "api-balance-\(id)" }

    func validatedURL() throws -> URL {
        let raw = kind == .deepSeek ? "https://api.deepseek.com/user/balance" : endpoint
        guard let url = URL(string: raw), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw APIBalanceError.message("请填写名称和完整 HTTPS 余额接口地址，不要在地址中包含密钥或查询参数。")
        }
        if kind == .relay {
            guard !amountPath.isEmpty, currency.count == 3,
                  currency.unicodeScalars.allSatisfy({ (65...90).contains($0.value) }),
                  let scale = APIBalanceParser.decimal(divisor), scale > 0 else {
                throw APIBalanceError.message("请填写金额 JSON 字段路径、三位币种代码和大于零的单位换算除数。")
            }
        }
        return url
    }
}

struct APIBalanceAmount: Codable, Equatable, Sendable {
    var currency: String
    var value: Decimal
    var granted: Decimal?
    var toppedUp: Decimal?
    var text: String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return "\(formatter.string(from: NSDecimalNumber(decimal: value)) ?? "—") \(currency)"
    }
}

struct APIBalanceSnapshot: Codable, Equatable, Sendable {
    var account: APIBalanceAccount
    var amounts: [APIBalanceAmount]
    var fetchedAt: Date
    var isAvailable: Bool?
}

enum APIBalanceError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let text): text } }
}

enum APIBalanceParser {
    static func decimal(_ raw: String) -> Decimal? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.range(of: #"^-?[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil,
              text.count <= 38, let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
              !value.isNaN else { return nil }
        return value
    }

    static func amount(_ value: Any?) -> Decimal? {
        if let string = value as? String { return decimal(string) }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            return decimal(number.stringValue)
        }
        return nil
    }

    static func parse(_ data: Data, account: APIBalanceAccount, now: Date = Date()) throws -> APIBalanceSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["error"] == nil, (root["success"] as? Bool) != false else {
            throw APIBalanceError.message("余额接口返回错误或格式不支持。")
        }
        var amounts: [APIBalanceAmount] = []
        var available: Bool?
        if account.kind == .deepSeek {
            guard let flag = root["is_available"] as? Bool,
                  let rows = root["balance_infos"] as? [[String: Any]] else {
                throw APIBalanceError.message("DeepSeek 余额响应缺少必要字段。")
            }
            available = flag
            for row in rows {
                guard let currency = row["currency"] as? String, ["CNY", "USD"].contains(currency),
                      let value = amount(row["total_balance"]),
                      !amounts.contains(where: { $0.currency == currency }) else {
                    throw APIBalanceError.message("DeepSeek 返回了无效的余额或币种。")
                }
                amounts.append(APIBalanceAmount(currency: currency, value: value,
                    granted: amount(row["granted_balance"]), toppedUp: amount(row["topped_up_balance"])))
            }
        } else {
            _ = try account.validatedURL()
            var node: Any = root
            for part in account.amountPath.split(separator: ".", omittingEmptySubsequences: false) {
                if let dict = node as? [String: Any], let value = dict[String(part)] { node = value }
                else if let array = node as? [Any], let index = Int(part), array.indices.contains(index) { node = array[index] }
                else { throw APIBalanceError.message("找不到金额字段，请核对 JSON 路径。") }
            }
            guard let value = amount(node), let divisor = decimal(account.divisor) else {
                throw APIBalanceError.message("金额字段不是有效数字。")
            }
            let converted = value / divisor
            guard !converted.isNaN else { throw APIBalanceError.message("金额超出可处理范围。") }
            amounts = [APIBalanceAmount(currency: account.currency, value: converted)]
        }
        guard !amounts.isEmpty else { throw APIBalanceError.message("平台未提供余额，不能视为零。") }
        return APIBalanceSnapshot(account: account, amounts: amounts, fetchedAt: now, isAvailable: available)
    }

    /// A partial sum must never look like the balance of all configured accounts.
    static func total(accounts: [APIBalanceAccount], snapshots: [String: APIBalanceSnapshot]) -> [APIBalanceAmount]? {
        guard !accounts.isEmpty else { return nil }
        var totals: [String: Decimal] = [:]
        for account in accounts {
            guard let snapshot = snapshots[account.id], snapshot.account == account else { return nil }
            for amount in snapshot.amounts {
                totals[amount.currency, default: 0] += amount.value
                guard totals[amount.currency]?.isNaN == false else { return nil }
            }
        }
        return totals.keys.sorted().map { APIBalanceAmount(currency: $0, value: totals[$0]!) }
    }
}

/// Never forward a balance credential to a redirected origin, or accept an HTML login page.
private final class APIBalanceRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum APIBalanceClient {
    static func fetch(account: APIBalanceAccount, key: String, configuration: URLSessionConfiguration = .ephemeral) async throws -> APIBalanceSnapshot {
        var request = URLRequest(url: try account.validatedURL())
        request.timeoutInterval = 15
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        configuration.timeoutIntervalForResource = 20
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: APIBalanceRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw APIBalanceError.message(code == 401 || code == 403 ? "凭据无效或没有余额查询权限。" : "余额查询失败（HTTP \(code)）。")
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 262_144 else { throw APIBalanceError.message("余额响应过大，已停止读取。") }
            data.append(byte)
        }
        try Task.checkCancellation()
        return try APIBalanceParser.parse(data, account: account)
    }
}

@MainActor @Observable
final class APIBalanceStore {
    static let shared = APIBalanceStore()
    private(set) var accounts: [APIBalanceAccount]
    private(set) var snapshots: [String: APIBalanceSnapshot]
    private(set) var errors: [String: String] = [:]
    private(set) var isRefreshing = false
    private var task: Task<Void, Never>?
    private var revision = UUID()
    private var nextRefresh: [String: Date] = [:]
    private var timer: Timer?
    private let defaults: UserDefaults
    private static let accountsKey = "CapacityDockAPIBalanceAccounts"
    private static let cacheKey = "CapacityDockAPIBalanceCache"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let loadedAccounts = defaults.data(forKey: Self.accountsKey).flatMap { try? JSONDecoder().decode([APIBalanceAccount].self, from: $0) } ?? []
        accounts = loadedAccounts
        let cached = defaults.data(forKey: Self.cacheKey).flatMap { try? JSONDecoder().decode([String: APIBalanceSnapshot].self, from: $0) } ?? [:]
        snapshots = cached.filter { entry in entry.key == entry.value.account.id && loadedAccounts.contains(entry.value.account) }
    }

    var menuText: String? {
        guard !accounts.isEmpty else { return nil }
        let totals = APIBalanceParser.total(accounts: accounts, snapshots: snapshots)
        let text = totals?.map(\.text).joined(separator: " · ") ?? "—"
        let stale = accounts.contains { account in
            errors[account.id] != nil || snapshots[account.id].map { Date().timeIntervalSince($0.fetchedAt) > 300 } == true
        }
        return text + (stale ? " ↻" : "")
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer?.tolerance = 10
        refresh()
    }

    func refresh(force: Bool = false) {
        guard task == nil, !accounts.isEmpty else { return }
        let pending = accounts.filter { force || (nextRefresh[$0.id] ?? .distantPast) <= Date() }
        guard !pending.isEmpty else { return }
        let generation = revision
        isRefreshing = true
        task = Task { [weak self] in
            guard let self else { return }
            for account in pending {
                do {
                    let credential = try await CapacityDockProviderCredentialStore.loadAsync(for: account.credentialID)
                    try Task.checkCancellation()
                    guard !credential.apiKey.isEmpty else { throw APIBalanceError.message("请在 API 账户设置中填写密钥。") }
                    let snapshot = try await APIBalanceClient.fetch(account: account, key: credential.apiKey)
                    guard revision == generation else { return }
                    snapshots[account.id] = snapshot
                    errors[account.id] = nil
                    nextRefresh[account.id] = Date().addingTimeInterval(60)
                } catch {
                    guard revision == generation, !Task.isCancelled else { return }
                    errors[account.id] = (error as? APIBalanceError)?.localizedDescription ?? "查询未完成，请检查网络或钥匙串后重试。"
                    nextRefresh[account.id] = Date().addingTimeInterval(300)
                }
            }
            guard revision == generation else { return }
            isRefreshing = false
            task = nil
            persist()
        }
    }

    func save(_ account: APIBalanceAccount, key: String) async throws {
        _ = try account.validatedURL()
        let cleaned = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty {
            guard !cleaned.contains("\n"), !cleaned.contains("\r") else { throw APIBalanceError.message("密钥不能包含换行。") }
            try await CapacityDockProviderCredentialStore.saveAsync(CapacityDockProviderCredential(apiKey: cleaned), for: account.credentialID)
        } else if !accounts.contains(where: { $0.id == account.id }) {
            throw APIBalanceError.message("请填写 API 密钥。")
        } else if let original = accounts.first(where: { $0.id == account.id }),
                  try original.validatedURL() != account.validatedURL() {
            throw APIBalanceError.message("余额地址已改变，请重新填写目标平台的密钥。")
        }
        cancelRefresh()
        accounts.removeAll { $0.id == account.id }
        accounts.append(account)
        snapshots[account.id] = nil
        errors[account.id] = nil
        nextRefresh[account.id] = nil
        persist()
        refresh()
    }

    func remove(_ account: APIBalanceAccount) async throws {
        try await CapacityDockProviderCredentialStore.saveAsync(CapacityDockProviderCredential(), for: account.credentialID)
        cancelRefresh()
        accounts.removeAll { $0.id == account.id }
        snapshots[account.id] = nil
        errors[account.id] = nil
        nextRefresh[account.id] = nil
        persist()
        refresh()
    }

    private func cancelRefresh() {
        revision = UUID()
        task?.cancel()
        task = nil
        isRefreshing = false
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(accounts), forKey: Self.accountsKey)
        defaults.set(try? JSONEncoder().encode(snapshots), forKey: Self.cacheKey)
        NotificationCenter.default.post(name: .capacityDockMenubarBillDidChange, object: nil)
    }
}
