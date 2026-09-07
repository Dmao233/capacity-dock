import Foundation

/// CodeBurn-style menubar figure: today's priced total, or `$—` until a
/// successful local scan exists. Compact form matches
/// `Double.asCompactCurrency` / `asCompactCurrencyWhole`.
enum MenubarBillBadge: Equatable, Sendable {
    case pending
    case amount(Double)

    static func from(snapshot: TokenConsumptionSnapshot) -> MenubarBillBadge {
        let totals = snapshot.periodTotals
        if totals.pricedEventCount > 0, let amount = totals.estimatedUSD,
           amount.isFinite, amount >= 0 {
            return .amount(amount)
        }
        guard snapshot.scannedAnyLog,
              snapshot.rows.contains(where: { $0.availability == .logged }),
              totals.loggedEventCount == 0,
              totals.tokenCount == 0,
              !snapshot.rows.contains(where: { $0.availability == .unreadable })
        else { return .pending }
        return .amount(0)
    }

    func menubarText(compact: Bool = false, currency: DisplayCurrency = .usd) -> String {
        switch self {
        case .pending:
            return currency.menubarText(amount: nil, compact: compact)
        case .amount(let usd):
            return currency.menubarText(amount: usd, compact: compact)
        }
    }
}

/// Keeps the status-item dollar figure warm the way CodeBurn keeps
/// `menubar-status.json`: last amount on disk, in-memory snapshot for Today,
/// 30s TTL, and a background scan that never blocks the click.
@MainActor
final class MenubarBillStore {
    static let shared = MenubarBillStore()
    static let ttl: TimeInterval = 30

    private(set) var badge: MenubarBillBadge = .pending
    private(set) var snapshot: TokenConsumptionSnapshot?
    private var lastRefresh: Date?
    private var scans: [TokenConsumptionPeriod: Task<TokenConsumptionSnapshot, Never>] = [:]
    private var timer: Timer?
    private let cacheURL: URL?
    private let now: () -> Date
    private let timeZone: TimeZone
    private let load: @Sendable (TokenConsumptionPeriod, Date, TimeZone) async -> TokenConsumptionSnapshot

    init(
        cacheURL: URL? = MenubarBillStore.defaultCacheURL,
        now: @escaping () -> Date = Date.init,
        timeZone: TimeZone = .current,
        load: @escaping @Sendable (TokenConsumptionPeriod, Date, TimeZone) async -> TokenConsumptionSnapshot = MenubarBillStore.loadLocal
    ) {
        self.cacheURL = cacheURL
        self.now = now
        self.timeZone = timeZone
        self.load = load
        loadPersisted()
    }

    func start() {
        if timer != nil { return }
        Task { await refresh(force: false) }
        let timer = Timer(timeInterval: Self.ttl, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh(force: false)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func apply(_ snapshot: TokenConsumptionSnapshot) {
        guard snapshot.period == .today else { return }
        guard snapshot.window.contains(now()) else {
            self.snapshot = nil
            badge = .pending
            lastRefresh = nil
            persist()
            NotificationCenter.default.post(name: .capacityDockMenubarBillDidChange, object: nil)
            return
        }
        self.snapshot = snapshot
        badge = MenubarBillBadge.from(snapshot: snapshot)
        lastRefresh = now()
        persist()
        NotificationCenter.default.post(name: .capacityDockMenubarBillDidChange, object: nil)
    }

    func snapshot(for period: TokenConsumptionPeriod, force: Bool = false) async -> TokenConsumptionSnapshot {
        // A forced reload bypasses completed cache entries, but joins an active scan.
        if let scan = scans[period] { return await scan.value }
        if period == .today,
           !force,
           let snapshot,
           let lastRefresh,
           snapshot.window.contains(now()),
           now().timeIntervalSince(lastRefresh) >= 0,
           now().timeIntervalSince(lastRefresh) < Self.ttl {
            return snapshot
        }
        let scan = Task {
            let result = await load(period, now(), timeZone)
            if period == .today { apply(result) }
            scans[period] = nil
            return result
        }
        scans[period] = scan
        return await scan.value
    }

    func refresh(force: Bool) async {
        _ = await snapshot(for: .today, force: force)
    }

    private nonisolated static func loadLocal(
        period: TokenConsumptionPeriod, now: Date, timeZone: TimeZone
    ) async -> TokenConsumptionSnapshot {
        await Task.detached(priority: .utility) {
            var deps = LocalTokenLogReader.Deps.live(now: now)
            deps.timeZone = timeZone
            return LocalTokenLogReader.load(period: period, deps: deps)
        }.value
    }

    private struct Record: Codable {
        var day: String
        var usd: Double?
        var pending: Bool
        var generatedAt: TimeInterval
    }

    private static var defaultCacheURL: URL? {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return root
            .appendingPathComponent("CapacityDock", isDirectory: true)
            .appendingPathComponent("menubar-bill.json")
    }

    private func loadPersisted() {
        guard let cacheURL,
              let data = try? SafeFile.read(from: cacheURL.path, maxBytes: 64 * 1024),
              let record = try? JSONDecoder().decode(Record.self, from: data)
        else { return }
        let today = TokenConsumptionClock.dayKey(now(), timeZone: timeZone)
        guard record.day == today else { return }
        if !record.pending, let usd = record.usd, usd.isFinite, usd >= 0 {
            badge = .amount(usd)
        }
    }

    private func persist() {
        guard let cacheURL else { return }
        let record = Record(
            day: TokenConsumptionClock.dayKey(now(), timeZone: timeZone),
            usd: {
                if case .amount(let value) = badge { return value }
                return nil
            }(),
            pending: badge == .pending,
            generatedAt: now().timeIntervalSince1970
        )
        guard let data = try? JSONEncoder().encode(record) else { return }
        try? SafeFile.write(data, to: cacheURL.path, mode: 0o600)
    }
}

extension Notification.Name {
    static let capacityDockMenubarBillDidChange = Notification.Name(
        "com.dmao233.capacityDockMenubarBillDidChange"
    )
}
