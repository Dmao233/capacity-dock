import Foundation
import SQLite3

/// Reads Cursor.app's local session database in read-only mode, keeps the
/// token in memory for one request, and never copies it into Capacity Dock's
/// Keychain or support directory.
///
/// Quota is fetched from Cursor's agent API (`api2.cursor.sh`). The dashboard
/// host `cursor.com` is a different network path and is often blocked or hung
/// behind local HTTP proxies even while the Cursor app itself still works.
enum CursorSubscriptionService {
    static let usageURL = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")!
    private static let timeoutSeconds: TimeInterval = 15

    enum FetchError: Error, Equatable, LocalizedError, Sendable {
        case noCredentials
        case expiredSession
        case authenticationRejected
        case appDataUnreadable
        case rateLimited
        case providerUnavailable
        case parseFailure
        case network

        enum Classification: Equatable, Sendable {
            case terminalAuth
            case transient
            case parseFailure
        }

        var classification: Classification {
            switch self {
            case .noCredentials, .expiredSession, .authenticationRejected:
                return .terminalAuth
            case .appDataUnreadable, .rateLimited, .providerUnavailable, .network:
                return .transient
            case .parseFailure:
                return .parseFailure
            }
        }

        var errorDescription: String? {
            switch self {
            case .noCredentials:
                return "Sign in to the Cursor app, then click Retry."
            case .expiredSession:
                return "The Cursor app session is expired or invalid. Sign in again, then click Retry."
            case .authenticationRejected:
                return "Cursor rejected the current app session. Sign in again, then click Retry."
            case .appDataUnreadable:
                return "Could not read the Cursor app's local session data. Quit and reopen Cursor, then click Retry."
            case .rateLimited:
                return "Cursor rate-limited the quota request."
            case .providerUnavailable:
                return "Cursor is temporarily unavailable."
            case .parseFailure:
                return "Cursor returned an unrecognized quota response."
            case .network:
                return "Network error fetching Cursor quota."
            }
        }
    }

    struct Deps: Sendable {
        var loadAccessToken: @Sendable () throws -> String?
        var loadMembershipType: @Sendable () throws -> String?
        var fetch: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

        init(
            loadAccessToken: @escaping @Sendable () throws -> String?,
            loadMembershipType: @escaping @Sendable () throws -> String? = { nil },
            fetch: @escaping @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
        ) {
            self.loadAccessToken = loadAccessToken
            self.loadMembershipType = loadMembershipType
            self.fetch = fetch
        }

        static let live = Deps(
            loadAccessToken: {
                try CursorAppSessionStore().loadAccessToken()
            },
            loadMembershipType: {
                try CursorAppSessionStore().loadMembershipType()
            },
            fetch: { request in
                let configuration = URLSessionConfiguration.ephemeral
                configuration.httpCookieStorage = nil
                configuration.httpShouldSetCookies = false
                configuration.urlCache = nil
                configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
                configuration.timeoutIntervalForRequest = timeoutSeconds
                configuration.timeoutIntervalForResource = timeoutSeconds
                let session = URLSession(configuration: configuration)
                defer { session.invalidateAndCancel() }
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw FetchError.network }
                return (data, http)
            }
        )
    }

    @MainActor
    static func refresh(deps: Deps = .live) async throws -> QuotaSummary {
        let accessToken: String
        let membershipType: String?
        do {
            // The store read is synchronous SQLite with a 250ms busy timeout;
            // keep it off the main actor so a lock held by Cursor cannot
            // stall the UI.
            let loadAccessToken = deps.loadAccessToken
            let loadMembershipType = deps.loadMembershipType
            let loaded = try await Task.detached {
                let token = try loadAccessToken()
                let membership = try? loadMembershipType()
                return (token, membership)
            }.value
            guard let raw = loaded.0?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty else {
                throw FetchError.noCredentials
            }
            accessToken = raw
            membershipType = loaded.1?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
        } catch let error as FetchError {
            throw error
        } catch {
            throw FetchError.appDataUnreadable
        }

        try requireFreshAccessToken(accessToken)
        var request = URLRequest(url: usageURL)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("{}".utf8)

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await deps.fetch(request)
        } catch let error as FetchError {
            throw error
        } catch {
            throw FetchError.network
        }

        switch response.statusCode {
        case 200:
            break
        case 401, 403:
            throw FetchError.authenticationRejected
        case 429:
            throw FetchError.rateLimited
        case 500...599:
            throw FetchError.providerUnavailable
        default:
            throw FetchError.parseFailure
        }

        return try decode(data, membershipType: membershipType)
    }

    static func decode(_ data: Data, membershipType: String? = nil) throws -> QuotaSummary {
        let summary: UsageSummary
        do {
            summary = try JSONDecoder().decode(UsageSummary.self, from: data)
        } catch {
            throw FetchError.parseFailure
        }

        let plan = summary.planUsage?.asMeter ?? summary.individualUsage?.plan
        let overall = summary.individualUsage?.overall
        let pooled = summary.teamUsage?.pooled
        let autoPercent = normalizedProviderPercent(plan?.autoPercentUsed)
        let apiPercent = normalizedProviderPercent(plan?.apiPercentUsed)

        let monthlyPercent: Double? = {
            if let total = normalizedProviderPercent(plan?.totalPercentUsed) { return total }
            // A capacity gauge must surface the pool that is about to run
            // out; averaging would hide an exhausted pool behind an idle one.
            if let autoPercent, let apiPercent { return max(autoPercent, apiPercent) }
            if let apiPercent { return apiPercent }
            if let autoPercent { return autoPercent }
            if let ratio = ratio(used: plan?.used, limit: plan?.limit) { return ratio }
            if let ratio = ratio(used: overall?.used, limit: overall?.limit) { return ratio }
            if let ratio = ratio(used: pooled?.used, limit: pooled?.limit) { return ratio }
            if summary.isUnlimited == true { return 0 }
            return nil
        }()
        guard let monthlyPercent else { throw FetchError.parseFailure }

        let reset = parseDate(summary.billingCycleEnd)
        let primary = QuotaSummary.Window(label: "Monthly", percent: monthlyPercent, resetsAt: reset)
        var details = [primary]
        if let autoPercent {
            details.append(QuotaSummary.Window(label: "Auto", percent: autoPercent, resetsAt: reset))
        }
        if let apiPercent {
            details.append(QuotaSummary.Window(label: "API", percent: apiPercent, resetsAt: reset))
        }
        if let onDemand = summary.individualUsage?.onDemand,
           onDemand.enabled != false,
           let percent = ratio(used: onDemand.used, limit: onDemand.limit) {
            details.append(QuotaSummary.Window(label: "On-demand", percent: percent, resetsAt: reset))
        } else if let spend = summary.spendLimitUsage,
                  let percent = ratio(used: spend.totalSpend, limit: spend.individualLimit) {
            details.append(QuotaSummary.Window(label: "On-demand", percent: percent, resetsAt: reset))
        }
        if let percent = ratio(used: pooled?.used, limit: pooled?.limit)
            ?? ratio(used: summary.spendLimitUsage?.pooledUsed, limit: summary.spendLimitUsage?.pooledLimit) {
            details.append(QuotaSummary.Window(label: "Team pool", percent: percent, resetsAt: reset))
        }

        return QuotaSummary(
            providerFilter: .cursor,
            connection: .connected,
            primary: primary,
            details: details,
            planLabel: planLabel(summary.membershipType ?? membershipType),
            footerLines: ["Source: Cursor app"]
        )
    }

    private struct Claims: Decodable {
        let exp: Double?
    }

    private static func requireFreshAccessToken(_ token: String, now: Date = Date()) throws {
        let components = token.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3,
              let payload = decodeBase64URL(String(components[1])),
              let claims = try? JSONDecoder().decode(Claims.self, from: payload),
              let expiration = claims.exp,
              Date(timeIntervalSince1970: expiration).timeIntervalSince(now) > 60 else {
            throw FetchError.expiredSession
        }
    }

    private static func decodeBase64URL(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }

    private static func normalizedProviderPercent(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return min(1, value / 100)
    }

    private static func ratio(used: Int?, limit: Int?) -> Double? {
        guard let used, let limit, used >= 0, limit > 0 else { return nil }
        return min(1, max(0, Double(used) / Double(limit)))
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.allSatisfy(\.isNumber), let value = Double(raw) {
            let seconds = value > 10_000_000_000 ? value / 1000 : value
            return Date(timeIntervalSince1970: seconds)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }

    private static func planLabel(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        switch value.lowercased() {
        case "pro": return "Pro"
        case "pro_plus", "pro plus": return "Pro Plus"
        case "business": return "Business"
        case "enterprise": return "Enterprise"
        case "hobby", "free": return "Hobby"
        case "ultra": return "Ultra"
        default: return value
        }
    }

    private struct UsageSummary: Decodable {
        let billingCycleEnd: String?
        let membershipType: String?
        let isUnlimited: Bool?
        let planUsage: PlanUsage?
        let spendLimitUsage: SpendLimitUsage?
        let individualUsage: IndividualUsage?
        let teamUsage: TeamUsage?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            billingCycleEnd = try container.decodeFlexibleStringIfPresent(forKey: .billingCycleEnd)
            membershipType = try container.decodeIfPresent(String.self, forKey: .membershipType)
            isUnlimited = try container.decodeIfPresent(Bool.self, forKey: .isUnlimited)
            planUsage = try container.decodeIfPresent(PlanUsage.self, forKey: .planUsage)
            spendLimitUsage = try container.decodeIfPresent(SpendLimitUsage.self, forKey: .spendLimitUsage)
            individualUsage = try container.decodeIfPresent(IndividualUsage.self, forKey: .individualUsage)
            teamUsage = try container.decodeIfPresent(TeamUsage.self, forKey: .teamUsage)
        }

        private enum CodingKeys: String, CodingKey {
            case billingCycleEnd
            case membershipType
            case isUnlimited
            case planUsage
            case spendLimitUsage
            case individualUsage
            case teamUsage
        }
    }

    private struct PlanUsage: Decodable {
        let totalSpend: Int?
        let includedSpend: Int?
        let remaining: Int?
        let limit: Int?
        let autoPercentUsed: Double?
        let apiPercentUsed: Double?
        let totalPercentUsed: Double?

        var asMeter: Meter {
            Meter(
                enabled: true,
                used: includedSpend ?? totalSpend,
                limit: limit,
                autoPercentUsed: autoPercentUsed,
                apiPercentUsed: apiPercentUsed,
                totalPercentUsed: totalPercentUsed
            )
        }
    }

    private struct SpendLimitUsage: Decodable {
        let totalSpend: Int?
        let individualLimit: Int?
        let pooledUsed: Int?
        let pooledLimit: Int?
    }

    private struct IndividualUsage: Decodable {
        let plan: Meter?
        let onDemand: Meter?
        let overall: Meter?
    }

    private struct TeamUsage: Decodable {
        let pooled: Meter?
    }

    private struct Meter: Decodable {
        let enabled: Bool?
        let used: Int?
        let limit: Int?
        let autoPercentUsed: Double?
        let apiPercentUsed: Double?
        let totalPercentUsed: Double?
    }
}

/// Narrow read-only adapter for Cursor's own VS Code state database.
struct CursorAppSessionStore: Sendable {
    private static let accessTokenKey = "cursorAuth/accessToken"
    private static let membershipTypeKey = "cursorAuth/stripeMembershipType"
    let databaseURL: URL

    init(databaseURL: URL = Self.defaultDatabaseURL()) {
        self.databaseURL = databaseURL
    }

    static func defaultDatabaseURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage", isDirectory: true)
            .appendingPathComponent("state.vscdb", isDirectory: false)
    }

    func loadAccessToken() throws -> String? {
        try loadString(for: Self.accessTokenKey)
    }

    func loadMembershipType() throws -> String? {
        try loadString(for: Self.membershipTypeKey)
    }

    private func loadString(for key: String) throws -> String? {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return nil }
        do {
            return try value(for: key, immutable: false)
        } catch let error as SQLiteFailure
            where error.code == SQLITE_CANTOPEN && walSidecarsAreMissing {
            return try value(for: key, immutable: true)
        } catch {
            throw CursorAppSessionStoreError.unreadable
        }
    }

    private func value(for key: String, immutable: Bool) throws -> String? {
        var database: OpaquePointer?
        let filename = immutable ? "\(databaseURL.absoluteURL.absoluteString)?immutable=1" : databaseURL.path
        let flags = immutable ? SQLITE_OPEN_READONLY | SQLITE_OPEN_URI : SQLITE_OPEN_READONLY
        let openResult = sqlite3_open_v2(filename, &database, flags, nil)
        guard openResult == SQLITE_OK else {
            let failure = SQLiteFailure(code: database.map(sqlite3_errcode) ?? openResult)
            sqlite3_close(database)
            throw failure
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 250)

        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(
            database,
            "SELECT value FROM ItemTable WHERE key = ? LIMIT 1;",
            -1,
            &statement,
            nil
        )
        guard prepareResult == SQLITE_OK else {
            throw SQLiteFailure(code: sqlite3_errcode(database))
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, key, -1, sqliteTransient)

        let stepResult = sqlite3_step(statement)
        if stepResult == SQLITE_DONE { return nil }
        guard stepResult == SQLITE_ROW else {
            throw SQLiteFailure(code: sqlite3_errcode(database))
        }
        switch sqlite3_column_type(statement, 0) {
        case SQLITE_TEXT:
            guard let text = sqlite3_column_text(statement, 0) else { return nil }
            return String(cString: text)
        case SQLITE_BLOB:
            guard let bytes = sqlite3_column_blob(statement, 0) else { return nil }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
            return String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .utf16LittleEndian)
        default:
            return nil
        }
    }

    private var walSidecarsAreMissing: Bool {
        !FileManager.default.fileExists(atPath: databaseURL.path + "-wal") &&
            !FileManager.default.fileExists(atPath: databaseURL.path + "-shm")
    }

    private struct SQLiteFailure: Error {
        let code: Int32
    }
}

private enum CursorAppSessionStoreError: Error {
    case unreadable
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleStringIfPresent(forKey key: Key) throws -> String? {
        guard contains(key) else { return nil }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int64.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return String(Int64(value))
        }
        return nil
    }
}
