import Foundation

struct CapacityDockProviderCredential: Codable, Equatable, Sendable {
    var sourceMode: String = ProviderReferenceSourceMode.automatic.rawValue
    var apiKey: String = ""

    var resolvedSourceMode: ProviderReferenceSourceMode {
        ProviderReferenceSourceMode(rawValue: sourceMode) ?? .automatic
    }

    var isEmpty: Bool {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && resolvedSourceMode == .automatic
    }
}
