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
    private(set) var summaries: [String: QuotaSummary]
    var overlayURL: URL

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

    static func demo() -> CapacityDockStore {
        CapacityDockStore(summaries: DemoQuota.summaries)
    }

    func reloadOverlay() {
        applyOverlayIfPresent()
    }

    func capacityDockQuotaSummary(for provider: CapacityDockProvider) -> QuotaSummary? {
        summaries[provider.id]
    }

    func capacityDockCredential(for provider: CapacityDockProvider) async -> CapacityDockProviderCredential {
        CapacityDockProviderCredential()
    }

    func connectCapacityDockProvider(_ provider: CapacityDockProvider) async {
        NotificationCenter.default.post(
            name: .capacityDockOpenProviderSettings,
            object: provider.id
        )
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
