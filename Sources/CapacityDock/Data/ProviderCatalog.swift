import Foundation

enum ProviderReferenceSourceMode: String, Codable, CaseIterable, Hashable, Sendable {
    case automatic = "auto"
    case web
    case cli
    case oauth
    case api
}

enum ProviderAuthMethod: String, Codable, CaseIterable, Hashable, Sendable {
    case localAppOrCLI
    case oauth
    case apiTokenOrCloudCredentials
    case cookieOrWebSession
    case localhost
    case none

    var title: String {
        switch self {
        case .localAppOrCLI: "Installed app or CLI"
        case .oauth: "OAuth"
        case .apiTokenOrCloudCredentials: "API or cloud credentials"
        case .cookieOrWebSession: "Browser session"
        case .localhost: "Localhost service"
        case .none: "No sign-in required"
        }
    }
}

struct ProviderConnectionCatalogEntry: Equatable, Sendable {
    let id: String
    let displayName: String
    let sourceModes: Set<ProviderReferenceSourceMode>
    let authMethods: Set<ProviderAuthMethod>
    let hasLiveCodeBurnQuotaAdapter: Bool
}

/// Curated catalog for the standalone dock. Live adapters in this package are
/// demo snapshots; drop a `quota.json` overlay to feed real numbers.
enum ProviderConnectionCatalog {
    static let providers: [ProviderConnectionCatalogEntry] = [
        entry("codex", "Codex", [.automatic, .cli, .oauth], [.localAppOrCLI, .oauth], live: true),
        entry("claude", "Claude", [.automatic, .cli, .oauth], [.localAppOrCLI, .oauth], live: true),
        entry("gemini", "Gemini", [.automatic, .cli, .oauth], [.localAppOrCLI, .oauth], live: true),
        entry("copilot", "Copilot", [.automatic, .oauth], [.oauth], live: true),
        entry("kimi", "Kimi Code", [.automatic, .api], [.apiTokenOrCloudCredentials], live: true),
        entry("grok", "Grok", [.automatic, .cli, .oauth], [.localAppOrCLI, .oauth], live: true),
        entry("cursor", "Cursor", [.automatic, .cli], [.localAppOrCLI], live: true),
        entry("antigravity", "Antigravity", [.automatic, .cli], [.localAppOrCLI], live: true),
        entry("clinepass", "ClinePass", [.automatic, .api], [.apiTokenOrCloudCredentials], live: true),
        entry("commandcode", "Command Code", [.automatic, .web], [.cookieOrWebSession]),
        entry("zai", "Z.ai", [.automatic, .api], [.apiTokenOrCloudCredentials], live: true),
        entry("openrouter", "OpenRouter", [.automatic, .api], [.apiTokenOrCloudCredentials]),
    ]

    private static func entry(
        _ id: String,
        _ displayName: String,
        _ sourceModes: Set<ProviderReferenceSourceMode>,
        _ authMethods: Set<ProviderAuthMethod>,
        live: Bool = false
    ) -> ProviderConnectionCatalogEntry {
        ProviderConnectionCatalogEntry(
            id: id,
            displayName: displayName,
            sourceModes: sourceModes,
            authMethods: authMethods,
            hasLiveCodeBurnQuotaAdapter: live
        )
    }

    static func entry(id: String) -> ProviderConnectionCatalogEntry? {
        providers.first { $0.id == id }
    }
}

enum ProviderConnectionGuidance {
    static func instruction(for provider: CapacityDockProvider) -> String {
        let methods = provider.catalogEntry.authMethods
        if methods == [.apiTokenOrCloudCredentials] {
            return "Enter an API key or token below, then press Save & Connect."
        }
        if methods == [.cookieOrWebSession] {
            return "Sign in to \(provider.displayName) in a supported browser, then click Retry."
        }
        if methods.contains(.localAppOrCLI) {
            return "Sign in with the \(provider.displayName) app or CLI, then click Retry."
        }
        if methods.contains(.oauth) {
            return "Complete \(provider.displayName) OAuth, then click Retry."
        }
        if methods.contains(.localhost) {
            return "Start the local \(provider.displayName) service, then click Retry."
        }
        if methods.contains(.apiTokenOrCloudCredentials) {
            return "Enter the required API or cloud credentials below, then press Save & Connect."
        }
        if methods.contains(.cookieOrWebSession) {
            return "Sign in to \(provider.displayName) in a supported browser, then click Retry."
        }
        return "No sign-in is required. Click Retry to refresh quota."
    }

    static func dockInstruction(for provider: CapacityDockProvider) -> String {
        let methods = provider.catalogEntry.authMethods
        if methods == [.apiTokenOrCloudCredentials] {
            return "Add an API key or token in Provider Settings."
        }
        if methods.contains(.apiTokenOrCloudCredentials),
           !methods.contains(.localAppOrCLI),
           !methods.contains(.cookieOrWebSession),
           !methods.contains(.oauth) {
            return "Add the required API or cloud credentials in Provider Settings."
        }
        return instruction(for: provider)
    }
}

enum ProviderConnectionSubmissionPolicy {
    enum Action: Equatable {
        case connect
        case saveAndConnect
        case requiresCredential
    }

    static func resolve(
        credential: CapacityDockProviderCredential,
        savedCredential: CapacityDockProviderCredential,
        requiresExplicitCredential: Bool
    ) -> Action {
        if requiresExplicitCredential,
           credential.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .requiresCredential
        }
        if credential != savedCredential { return .saveAndConnect }
        return .connect
    }
}

enum CapacityDockProviderRefreshInteraction {
    static func userInitiated<T>(
        operation: () async throws -> T
    ) async rethrows -> T {
        try await operation()
    }
}
