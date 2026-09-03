import Foundation
import Observation

/// Quota surface consumed by the rail and detail bubble.
@MainActor
protocol CapacityDockQuotaReading: AnyObject {
    func capacityDockQuotaSummary(for provider: CapacityDockProvider) -> QuotaSummary?
    func capacityDockCredential(for provider: CapacityDockProvider) async -> CapacityDockProviderCredential
    func connectCapacityDockProvider(_ provider: CapacityDockProvider) async
}

@MainActor
@Observable
final class CapacityDockStore: CapacityDockQuotaReading {
    static let liveProviderIDs: Set<String> = ["claude", "codex", "grok", "cursor"]

    private(set) var summaries: [String: QuotaSummary]
    private(set) var loading: Set<String> = []
    var overlayURL: URL
    private var refreshTimer: Timer?
    private var refreshGeneration: UInt64 = 0

    init(summaries: [String: QuotaSummary], overlayURL: URL? = nil) {
        self.summaries = summaries
        self.overlayURL = overlayURL ?? Self.defaultOverlayURL
        applyOverlayIfPresent()
    }

    static var defaultOverlayURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return root
            .appendingPathComponent("CapacityDock", isDirectory: true)
            .appendingPathComponent("quota.json")
    }

    /// Shipping default: no invented usage. Rings show `-` until `quota.json`
    /// is present. Set `CAPACITY_DOCK_DEMO=1` to load the canned snapshots.
    static func live() -> CapacityDockStore {
        if ProcessInfo.processInfo.environment["CAPACITY_DOCK_DEMO"] == "1" {
            return CapacityDockStore(summaries: DemoQuota.summaries)
        }
        return CapacityDockStore(summaries: [:])
    }

    func start() {
        Task { await refreshLiveProviders(userInitiated: false) }
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshLiveProviders(userInitiated: false)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func reloadOverlay() {
        applyOverlayIfPresent()
        notifyQuotaChanged()
    }

    func capacityDockQuotaSummary(for provider: CapacityDockProvider) -> QuotaSummary? {
        summaries[provider.id]
    }

    func capacityDockCredential(for provider: CapacityDockProvider) async -> CapacityDockProviderCredential {
        CapacityDockProviderCredential()
    }

    func connectCapacityDockProvider(_ provider: CapacityDockProvider) async {
        guard Self.liveProviderIDs.contains(provider.id) else {
            NotificationCenter.default.post(
                name: .capacityDockOpenProviderSettings,
                object: provider.id
            )
            return
        }
        await refresh(provider, userInitiated: true)
    }

    func refreshLiveProviders(userInitiated: Bool) async {
        let generation = refreshGeneration
        for id in ["grok", "claude", "codex", "cursor"] {
            guard let provider = CapacityDockProvider(rawValue: id) else { continue }
            await refresh(provider, userInitiated: userInitiated)
            guard generation == refreshGeneration else { return }
        }
        applyOverlayIfPresent()
        notifyQuotaChanged()
    }

    private func applyOverlayIfPresent() {
        guard let data = try? Data(contentsOf: overlayURL),
              let decoded = try? JSONDecoder().decode(QuotaOverlay.self, from: data) else { return }
        for (id, entry) in decoded.providers {
            let windows = entry.windows.map {
                QuotaSummary.Window(label: $0.label, percent: $0.percent, resetsAt: $0.resetsAt)
            }
            summaries[id] = QuotaSummary(
                providerFilter: ProviderFilter(rawValue: entry.displayName) ?? .all,
                connection: .connected,
                primary: windows.first,
                details: windows,
                planLabel: entry.plan,
                footerLines: entry.footer
            )
        }
    }

    private func refresh(_ provider: CapacityDockProvider, userInitiated: Bool) async {
        loading.insert(provider.id)
        defer { loading.remove(provider.id) }
        let previous = summaries[provider.id]
        do {
            switch provider.id {
            case "grok":
                summaries[provider.id] = try await GrokBuildSubscriptionService.refresh()
            case "cursor":
                summaries[provider.id] = try await CursorSubscriptionService.refresh()
            case "codex":
                summaries[provider.id] = try await refreshCodex(userInitiated: userInitiated)
            case "claude":
                summaries[provider.id] = try await refreshClaude(userInitiated: userInitiated)
            default:
                return
            }
        } catch {
            summaries[provider.id] = mapLiveError(
                error,
                provider: provider,
                previous: previous
            )
        }
        if userInitiated {
            applyOverlayIfPresent()
            notifyQuotaChanged()
        }
    }

    private func refreshCodex(userInitiated: Bool) async throws -> QuotaSummary {
        if userInitiated || CodexCredentialStore.hasCredentialSource {
            if !CodexCredentialStore.isBootstrapCompleted {
                let usage = try await CodexSubscriptionService.bootstrap()
                return LiveQuotaPresentation.codex(usage)
            }
            if let usage = try await CodexSubscriptionService.refreshIfBootstrapped() {
                return LiveQuotaPresentation.codex(usage)
            }
        }
        return summaries["codex"] ?? LiveQuotaPresentation.disconnected(.codex)
    }

    private func refreshClaude(userInitiated: Bool) async throws -> QuotaSummary {
        let fileURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        let hasFile = FileManager.default.fileExists(atPath: fileURL.path)
        if userInitiated || ClaudeCredentialStore.isBootstrapCompleted || hasFile {
            if userInitiated || (!ClaudeCredentialStore.isBootstrapCompleted && hasFile) {
                let usage = try await ClaudeSubscriptionService.bootstrap()
                return LiveQuotaPresentation.claude(usage)
            }
            if let usage = try await ClaudeSubscriptionService.refreshIfBootstrapped() {
                return LiveQuotaPresentation.claude(usage)
            }
        }
        return summaries["claude"] ?? LiveQuotaPresentation.disconnected(.claude)
    }

    private func mapLiveError(
        _ error: Error,
        provider: CapacityDockProvider,
        previous: QuotaSummary?
    ) -> QuotaSummary {
        if let error = error as? GrokBuildSubscriptionService.FetchError {
            if error == .noCredentials {
                return LiveQuotaPresentation.disconnected(.grok, reason: error.localizedDescription)
            }
            return LiveQuotaPresentation.failure(
                provider,
                message: error.localizedDescription,
                terminal: error.classification == .terminalAuth,
                previous: previous
            )
        }
        if let error = error as? CursorSubscriptionService.FetchError {
            if error == .noCredentials {
                return LiveQuotaPresentation.disconnected(.cursor, reason: error.localizedDescription)
            }
            return LiveQuotaPresentation.failure(
                provider,
                message: error.localizedDescription,
                terminal: error.classification == .terminalAuth,
                previous: previous
            )
        }
        if let error = error as? ClaudeSubscriptionService.FetchError {
            if case .notBootstrapped = error {
                return LiveQuotaPresentation.disconnected(.claude, reason: error.localizedDescription)
            }
            return LiveQuotaPresentation.failure(
                provider,
                message: error.localizedDescription,
                terminal: error.isTerminal,
                previous: previous
            )
        }
        if let error = error as? CodexSubscriptionService.FetchError {
            if case .notBootstrapped = error {
                return LiveQuotaPresentation.disconnected(.codex, reason: error.localizedDescription)
            }
            return LiveQuotaPresentation.failure(
                provider,
                message: error.localizedDescription,
                terminal: error.isTerminal,
                previous: previous
            )
        }
        return LiveQuotaPresentation.failure(
            provider,
            message: error.localizedDescription,
            terminal: false,
            previous: previous
        )
    }

    private func notifyQuotaChanged() {
        NotificationCenter.default.post(name: .capacityDockQuotaDidChange, object: nil)
    }
}

struct QuotaOverlay: Codable {
    var providers: [String: OverlayProvider]

    struct OverlayProvider: Codable {
        var displayName: String
        var plan: String?
        var footer: [String]
        var windows: [OverlayWindow]
    }

    struct OverlayWindow: Codable {
        var label: String
        var percent: Double
        var resetsAt: Date?
    }
}

enum DemoQuota {
    static var summaries: [String: QuotaSummary] {
        let week = Date().addingTimeInterval(5 * 24 * 3600 + 14 * 3600)
        let fiveHours = Date().addingTimeInterval(26 * 60)
        return [
            "grok": QuotaSummary(
                providerFilter: .grok,
                connection: .connected,
                primary: .init(label: "Weekly", percent: 0.23, resetsAt: week),
                details: [
                    .init(label: "Weekly", percent: 0.23, resetsAt: week)
                ],
                planLabel: "Heavy",
                footerLines: []
            ),
            "claude": QuotaSummary(
                providerFilter: .claude,
                connection: .connected,
                primary: .init(label: "Weekly", percent: 0.17, resetsAt: week),
                details: [
                    .init(label: "5-hour", percent: 0.06, resetsAt: fiveHours),
                    .init(label: "Weekly", percent: 0.17, resetsAt: week),
                    .init(label: "Weekly · Fable", percent: 0.15, resetsAt: week)
                ],
                planLabel: "Max 20x",
                footerLines: []
            ),
            "copilot": QuotaSummary(
                providerFilter: .copilot,
                connection: .connected,
                primary: .init(label: "Monthly", percent: 0.04, resetsAt: week),
                details: [
                    .init(label: "Monthly", percent: 0.04, resetsAt: week)
                ],
                planLabel: "Pro",
                footerLines: []
            ),
            "codex": QuotaSummary(
                providerFilter: .codex,
                connection: .connected,
                primary: .init(label: "Weekly", percent: 0.93, resetsAt: week),
                details: [
                    .init(label: "Weekly", percent: 0.93, resetsAt: week)
                ],
                planLabel: "Pro",
                footerLines: ["Credits remaining · 2,498"]
            ),
            "gemini": QuotaSummary(
                providerFilter: .gemini,
                connection: .connected,
                primary: .init(label: "Weekly", percent: 0.41, resetsAt: week),
                details: [
                    .init(label: "Weekly", percent: 0.41, resetsAt: week)
                ],
                planLabel: "Pro",
                footerLines: []
            ),
            "kimi": QuotaSummary(
                providerFilter: .kimiCode,
                connection: .disconnected,
                primary: nil,
                details: [],
                planLabel: nil,
                footerLines: []
            ),
            "cursor": QuotaSummary(
                providerFilter: .cursor,
                connection: .connected,
                primary: .init(label: "Monthly", percent: 0.62, resetsAt: week),
                details: [
                    .init(label: "Monthly", percent: 0.62, resetsAt: week)
                ],
                planLabel: "Pro",
                footerLines: []
            ),
            "antigravity": QuotaSummary(
                providerFilter: .antigravity,
                connection: .connected,
                primary: .init(label: "Weekly", percent: 0.11, resetsAt: week),
                details: [
                    .init(label: "Weekly", percent: 0.11, resetsAt: week)
                ],
                planLabel: nil,
                footerLines: []
            )
        ]
    }
}
