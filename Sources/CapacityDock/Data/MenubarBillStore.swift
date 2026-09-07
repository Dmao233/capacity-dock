import Foundation
import Observation

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
@Observable
final class MenubarBillStore {
    static let shared = MenubarBillStore()
    static let ttl: TimeInterval = 30

    private(set) var badge: MenubarBillBadge = .pending
    private(set) var snapshot: TokenConsumptionSnapshot?
    private(set) var scanProgress: [TokenConsumptionPeriod: String] = [:]
    private var scanIDs: [TokenConsumptionPeriod: UUID] = [:]
    private var activityTask: Task<TokenConsumptionSnapshot, Never>?
    private var activitySnapshot: TokenConsumptionSnapshot?
    private var activityRefreshedAt: Date?
    private(set) var activityProgress = ""
    private var scans: [TokenConsumptionPeriod: Task<TokenConsumptionSnapshot, Never>] = [:]
    private var timer: Timer?
    private var completed: [TokenConsumptionPeriod: (snapshot: TokenConsumptionSnapshot, refreshedAt: Date)] = [:]
    private let cacheURL: URL?
    private let now: () -> Date
    private let timeZone: TimeZone
    private let load: (@Sendable (TokenConsumptionPeriod, Date, TimeZone) async -> TokenConsumptionSnapshot)?

    init(
        cacheURL: URL? = MenubarBillStore.defaultCacheURL,
        now: @escaping () -> Date = Date.init,
        timeZone: TimeZone = .current,
        load: (@Sendable (TokenConsumptionPeriod, Date, TimeZone) async -> TokenConsumptionSnapshot)? = nil
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
            completed[.today] = nil
            badge = .pending
            persist()
            NotificationCenter.default.post(name: .capacityDockMenubarBillDidChange, object: nil)
            return
        }
        self.snapshot = snapshot
        badge = MenubarBillBadge.from(snapshot: snapshot)
        completed[.today] = (snapshot, now())
        persist()
        NotificationCenter.default.post(name: .capacityDockMenubarBillDidChange, object: nil)
    }

    func snapshot(for period: TokenConsumptionPeriod, force: Bool = false) async -> TokenConsumptionSnapshot {
        // A forced reload bypasses completed cache entries, but joins an active scan.
        if let scan = scans[period] { return await scan.value }
        if !force, let cached = completed[period],
           cached.snapshot.window.contains(now()),
           now().timeIntervalSince(cached.refreshedAt) >= 0,
           now().timeIntervalSince(cached.refreshedAt) < Self.ttl {
            return cached.snapshot
        }
        let request = UUID()
        scanIDs[period] = request
        scanProgress[period] = NSLocalizedString("Reading local logs…", comment: "")
        let scan = Task {
            let result: TokenConsumptionSnapshot
            if let load {
                result = await load(period, now(), timeZone)
            } else {
                result = await LocalBillLoader.shared.load(period: period, now: now(), timeZone: timeZone) { [weak self] count, total in
                    Task { @MainActor in
                        guard let self, self.scanIDs[period] == request else { return }
                        self.scanProgress[period] = String(format: NSLocalizedString("Reading Codex logs %d / %d", comment: ""), count, total)
                    }
                }
            }
            scanIDs[period] = nil
            scanProgress[period] = nil
            if result.window.contains(now()) { completed[period] = (result, now()) }
            if period == .today { apply(result) }
            scans[period] = nil
            return result
        }
        scans[period] = scan
        return await scan.value
    }

    func historicalActivity(force: Bool = false) async -> TokenConsumptionSnapshot {
        if let activityTask { return await activityTask.value }
        if !force, let activitySnapshot, let activityRefreshedAt,
           activitySnapshot.window.contains(now()), now().timeIntervalSince(activityRefreshedAt) < Self.ttl {
            return activitySnapshot
        }
        activityProgress = NSLocalizedString("Reading local logs…", comment: "")
        let task = Task {
            let result = await LocalBillLoader.shared.load(period: .month, now: now(), timeZone: timeZone, activity: true) { [weak self] count, total in
                Task { @MainActor in
                    self?.activityProgress = String(format: NSLocalizedString("Reading Codex logs %d / %d", comment: ""), count, total)
                }
            }
            activitySnapshot = result
            activityRefreshedAt = now()
            activityTask = nil
            return result
        }
        activityTask = task
        return await task.value
    }

    func refresh(force: Bool) async {
        _ = await snapshot(for: .today, force: force)
    }

    /// All periods share one on-disk file cache. Serial reads prevent a small
    /// Today scan from overwriting a concurrently completed historical cache.
    private actor LocalBillLoader {
        static let shared = LocalBillLoader()
        private var cache = TokenLogDayCache()
        private var loadedCache = false

        func load(period: TokenConsumptionPeriod, now: Date, timeZone: TimeZone, activity: Bool = false, progress: @escaping @Sendable (Int, Int) -> Void) -> TokenConsumptionSnapshot {
            var deps = LocalTokenLogReader.Deps.live(now: now)
            deps.timeZone = timeZone
            deps.progress = progress
            return autoreleasepool {
                if !loadedCache {
                    cache = TokenLogDayCache.load(from: deps.cacheURL)
                    loadedCache = true
                }
                return LocalTokenLogReader.load(period: period, deps: deps, cache: &cache, window: activity ? TokenConsumptionClock.activityWindow(now: now, timeZone: timeZone) : nil)
            }
        }
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
