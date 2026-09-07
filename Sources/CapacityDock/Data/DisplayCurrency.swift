import Foundation
import Observation

/// Same ISO list as CodeBurn `SupportedCurrency`. Display only — bills stay USD.
enum SupportedCurrency: String, CaseIterable, Identifiable, Sendable {
    case USD, GBP, EUR, AUD, CAD, NZD, JPY, CNY, CHF, INR, BRL, SEK, SGD, HKD, KRW, MXN, ZAR, DKK, RON

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .USD: NSLocalizedString("US Dollar", comment: "")
        case .GBP: NSLocalizedString("British Pound", comment: "")
        case .EUR: NSLocalizedString("Euro", comment: "")
        case .AUD: NSLocalizedString("Australian Dollar", comment: "")
        case .CAD: NSLocalizedString("Canadian Dollar", comment: "")
        case .NZD: NSLocalizedString("New Zealand Dollar", comment: "")
        case .JPY: NSLocalizedString("Japanese Yen", comment: "")
        case .CNY: NSLocalizedString("Chinese Yuan", comment: "")
        case .CHF: NSLocalizedString("Swiss Franc", comment: "")
        case .INR: NSLocalizedString("Indian Rupee", comment: "")
        case .BRL: NSLocalizedString("Brazilian Real", comment: "")
        case .SEK: NSLocalizedString("Swedish Krona", comment: "")
        case .SGD: NSLocalizedString("Singapore Dollar", comment: "")
        case .HKD: NSLocalizedString("Hong Kong Dollar", comment: "")
        case .KRW: NSLocalizedString("South Korean Won", comment: "")
        case .MXN: NSLocalizedString("Mexican Peso", comment: "")
        case .ZAR: NSLocalizedString("South African Rand", comment: "")
        case .DKK: NSLocalizedString("Danish Krone", comment: "")
        case .RON: NSLocalizedString("Romanian Leu", comment: "")
        }
    }
}

/// CodeBurn `asCompactCurrency` / `asCurrency`: USD amount × rate, then a symbol.
struct DisplayCurrency: Equatable, Sendable {
    var code: String
    var rate: Double
    var symbol: String

    static let usd = DisplayCurrency(code: "USD", rate: 1, symbol: "$")

    static func symbol(for code: String) -> String {
        switch code.uppercased() {
        case "USD", "CAD", "AUD", "NZD", "HKD", "SGD", "MXN": return "$"
        case "EUR": return "€"
        case "GBP": return "£"
        case "JPY", "CNY": return "¥"
        case "KRW": return "₩"
        case "INR": return "₹"
        case "BRL": return "R$"
        case "CHF": return "CHF"
        case "SEK", "DKK": return "kr"
        case "ZAR": return "R"
        case "RON": return "lei"
        default: return code
        }
    }

    func convert(_ usd: Double) -> Double { usd * rate }

    func compactAmount(_ usd: Double) -> String {
        String(format: "%@%.2f", symbol, convert(usd))
    }

    func compactWhole(_ usd: Double) -> String {
        "\(symbol)\(Int(convert(usd).rounded()))"
    }

    func grouped(_ usd: Double) -> String {
        let value = convert(usd)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        if value > 0, value < 0.01 {
            formatter.minimumFractionDigits = 4
            formatter.maximumFractionDigits = 4
        } else {
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
        }
        return symbol + (formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value))
    }

    func menubarText(amount usd: Double?, compact: Bool = false) -> String {
        guard let usd else {
            return compact ? "\(symbol)-" : " \(symbol)—"
        }
        return compact ? compactWhole(usd) : " " + compactAmount(usd)
    }
}

/// Live display currency. Source of truth is Capacity Dock prefs; CodeBurn's
/// `~/.config/codeburn/config.json` is inherited and written so both stay aligned.
@MainActor
@Observable
final class DisplayCurrencyState {
    static let shared = DisplayCurrencyState()

    private(set) var snapshot: DisplayCurrency = .usd
    private(set) var isUpdating = false
    private(set) var errorMessage: String?

    var code: String { snapshot.code }

    private let defaults: UserDefaults
    private let sharedFile: CodeBurnCurrencyFile
    private let rates: any FXRateProviding
    private var selectionGeneration: UInt64 = 0

    init(
        defaults: UserDefaults = .standard,
        sharedFile: CodeBurnCurrencyFile = .standard,
        rates: any FXRateProviding = FXRateCache.shared
    ) {
        self.defaults = defaults
        self.sharedFile = sharedFile
        self.rates = rates
    }

    func start() {
        select(resolvedCode(), persist: false)
    }

    @discardableResult
    func select(_ raw: String) -> Task<Void, Never> {
        select(raw, persist: true)
    }

    private func resolvedCode() -> String {
        if let stored = CapacityDockPreferences.currencyCode(defaults: defaults),
           SupportedCurrency(rawValue: stored) != nil {
            return stored
        }
        if let inherited = sharedFile.loadCode(),
           SupportedCurrency(rawValue: inherited) != nil {
            return inherited
        }
        return "USD"
    }

    @discardableResult
    private func select(_ raw: String, persist: Bool) -> Task<Void, Never> {
        selectionGeneration &+= 1
        let generation = selectionGeneration
        let code = SupportedCurrency(rawValue: raw.uppercased())?.rawValue ?? "USD"
        isUpdating = true
        errorMessage = nil
        return Task {
            guard generation == selectionGeneration else { return }
            defer {
                if generation == selectionGeneration { isUpdating = false }
            }
            if code == "USD" {
                accept(.usd, persist: persist)
                return
            }
            let symbol = DisplayCurrency.symbol(for: code)
            let cached = await rates.cachedRate(for: code)
            guard generation == selectionGeneration else { return }
            if let cached {
                accept(DisplayCurrency(code: code, rate: cached, symbol: symbol), persist: persist)
            }
            let fresh = await rates.rate(for: code)
            guard generation == selectionGeneration else { return }
            if let rate = fresh {
                accept(DisplayCurrency(code: code, rate: rate, symbol: symbol), persist: persist && cached == nil)
            } else if cached == nil {
                errorMessage = NSLocalizedString("Exchange rate unavailable. The displayed currency has not changed. Try again.", comment: "")
            }
        }
    }

    private func accept(_ currency: DisplayCurrency, persist: Bool) {
        if persist {
            CapacityDockPreferences.setCurrencyCode(currency.code, defaults: defaults)
            if !sharedFile.persist(code: currency.code) {
                errorMessage = NSLocalizedString("Currency changed here, but CodeBurn settings could not be updated. Its existing file was preserved.", comment: "")
            }
        }
        apply(currency)
    }

    private func apply(_ currency: DisplayCurrency) {
        snapshot = currency
        NotificationCenter.default.post(name: .capacityDockCurrencyDidChange, object: nil)
    }
}

protocol FXRateProviding: Sendable {
    func cachedRate(for code: String) async -> Double?
    func rate(for code: String) async -> Double?
}

actor FXRateCache: FXRateProviding {
    static let shared = FXRateCache()

    private struct Entry: Codable {
        var rate: Double
        var savedAt: TimeInterval
    }

    private let cacheURL: URL?
    private let codeBurnCacheURL: URL?
    private let session: URLSession
    private var entries: [String: Entry] = [:]
    private var loaded = false

    private static let ttl: TimeInterval = 24 * 3600
    private static let minRate = 0.0001
    private static let maxRate = 1_000_000.0

    init(
        cacheURL: URL? = FXRateCache.defaultCacheURL,
        codeBurnCacheURL: URL? = FXRateCache.codeBurnCacheURL,
        session: URLSession = FXRateCache.makeSession()
    ) {
        self.cacheURL = cacheURL
        self.codeBurnCacheURL = codeBurnCacheURL
        self.session = session
    }

    func cachedRate(for code: String) -> Double? {
        if code == "USD" { return 1 }
        loadIfNeeded()
        return entries[code]?.rate
    }

    func rate(for code: String) async -> Double? {
        if code == "USD" { return 1 }
        loadIfNeeded()
        if let entry = entries[code],
           Date().timeIntervalSince1970 - entry.savedAt < Self.ttl {
            return entry.rate
        }
        guard let url = URL(string: "https://api.frankfurter.app/latest?from=USD&to=\(code)") else {
            return entries[code]?.rate
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return entries[code]?.rate
            }
            struct Response: Decodable { var rates: [String: Double] }
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            guard let fresh = decoded.rates[code],
                  fresh.isFinite, fresh >= Self.minRate, fresh <= Self.maxRate
            else { return entries[code]?.rate }
            entries[code] = Entry(rate: fresh, savedAt: Date().timeIntervalSince1970)
            persist()
            return fresh
        } catch {
            return entries[code]?.rate
        }
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        if let cacheURL, let data = try? SafeFile.read(from: cacheURL.path, maxBytes: 64 * 1024),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = decoded.filter { $0.value.rate.isFinite && $0.value.rate >= Self.minRate && $0.value.rate <= Self.maxRate }
        }
        if entries.isEmpty,
           let codeBurnCacheURL,
           let data = try? SafeFile.read(from: codeBurnCacheURL.path, maxBytes: 64 * 1024),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = decoded.filter { $0.value.rate.isFinite && $0.value.rate >= Self.minRate && $0.value.rate <= Self.maxRate }
        }
    }

    private func persist() {
        guard let cacheURL, let data = try? JSONEncoder().encode(entries) else { return }
        try? SafeFile.write(data, to: cacheURL.path, mode: 0o600)
    }

    private static var defaultCacheURL: URL? {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return root
            .appendingPathComponent("CapacityDock", isDirectory: true)
            .appendingPathComponent("fx-rates.json")
    }

    private static var codeBurnCacheURL: URL? {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/codeburn/fx-rates.json")
    }

    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        return URLSession(configuration: config)
    }
}

/// Read/write CodeBurn CLI `currency.code` so a switch here matches the menubar there.
struct CodeBurnCurrencyFile: Sendable {
    var home: URL

    static let standard = CodeBurnCurrencyFile(
        home: FileManager.default.homeDirectoryForCurrentUser
    )

    private var configPath: String {
        home.appendingPathComponent(".config/codeburn/config.json").path
    }

    private var lockPath: String {
        home.appendingPathComponent(".config/codeburn/.config.lock").path
    }

    func loadCode() -> String? {
        guard let data = try? SafeFile.read(from: configPath, maxBytes: 256 * 1024),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let currency = json["currency"] as? [String: Any],
              let code = currency["code"] as? String
        else { return nil }
        return code.uppercased()
    }

    @discardableResult
    func persist(code: String) -> Bool {
        do {
            return try SafeFile.withExclusiveLock(at: lockPath) {
                var existing: [String: Any] = [:]
                do {
                    let data = try SafeFile.read(from: configPath, maxBytes: 256 * 1024)
                    guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        return false
                    }
                    existing = parsed
                } catch SafeFile.Error.readFailed(_, let code) where code == ENOENT {
                    // Only a missing file permits creating a new configuration.
                }
                if code == "USD" {
                    existing.removeValue(forKey: "currency")
                } else {
                    var currency = existing["currency"] as? [String: Any] ?? [:]
                    currency["code"] = code
                    currency["symbol"] = DisplayCurrency.symbol(for: code)
                    existing["currency"] = currency
                }
                guard let data = try? JSONSerialization.data(
                    withJSONObject: existing,
                    options: [.prettyPrinted, .sortedKeys]
                ) else { return false }
                try SafeFile.write(data, to: configPath, mode: 0o600)
                return true
            }
        } catch {
            return false
        }
    }
}

extension Notification.Name {
    static let capacityDockCurrencyDidChange = Notification.Name(
        "com.dmao233.capacityDockCurrencyDidChange"
    )
}
