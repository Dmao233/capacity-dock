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

    var sanitizedOverride: CapacityDockProviderCredentialOverride {
        CapacityDockProviderCredentialOverride(
            sourceMode: resolvedSourceMode,
            apiKey: cleaned(apiKey)
        )
    }

    private func cleaned(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct CapacityDockProviderCredentialOverride: Equatable, Sendable {
    var sourceMode: ProviderReferenceSourceMode
    var apiKey: String?
}

enum CapacityDockProviderCredentialStoreError: LocalizedError, Equatable {
    case timedOut

    var errorDescription: String? {
        "Keychain did not respond. Unlock your login keychain, then reopen this provider or re-enter its credential."
    }
}

enum CapacityDockProviderCredentialStore {
    static let service = "com.dmao233.capacity-dock.provider.v1"
    nonisolated(unsafe) static var keychainCache: any KeychainCredentialCaching = LiveKeychainCredentialCache()
    nonisolated(unsafe) static var userDefaults = UserDefaults.standard

    static func load(for providerID: String) throws -> CapacityDockProviderCredential {
        guard let data = try keychainCache.read(service: service, account: providerID) else {
            CapacityDockProviderCredentialPresence.set(false, for: providerID, defaults: userDefaults)
            return CapacityDockProviderCredential()
        }
        let credential = try JSONDecoder().decode(CapacityDockProviderCredential.self, from: data)
        CapacityDockProviderCredentialPresence.set(
            !credential.isEmpty,
            for: providerID,
            defaults: userDefaults
        )
        return credential
    }

    static func save(_ credential: CapacityDockProviderCredential, for providerID: String) throws {
        if credential.isEmpty {
            try keychainCache.delete(service: service, account: providerID)
            CapacityDockProviderCredentialPresence.set(false, for: providerID, defaults: userDefaults)
            return
        }
        let data = try JSONEncoder().encode(credential)
        try keychainCache.upsert(service: service, account: providerID, data: data)
        CapacityDockProviderCredentialPresence.set(true, for: providerID, defaults: userDefaults)
    }

    static func remove(for providerID: String) throws {
        try keychainCache.delete(service: service, account: providerID)
        CapacityDockProviderCredentialPresence.set(false, for: providerID, defaults: userDefaults)
    }

    static func loadAsync(for providerID: String) async throws -> CapacityDockProviderCredential {
        try await performBlocking { try load(for: providerID) }
    }

    static func saveAsync(
        _ credential: CapacityDockProviderCredential,
        for providerID: String
    ) async throws {
        try await performBlocking { try save(credential, for: providerID) }
    }

    static func removeAsync(for providerID: String) async throws {
        try await performBlocking { try remove(for: providerID) }
    }

    static func performBlocking<Value: Sendable>(
        operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try operation() })
            }
        }
    }
}

enum CapacityDockProviderCredentialPresence {
    static let key = "CapacityDockCredentialProviderIDs"
    private static let lock = NSLock()

    static func contains(_ providerID: String, defaults: UserDefaults = .standard) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let known = Set(CapacityDockPreferences.supportedProviders.map(\.id))
        return Set(defaults.stringArray(forKey: key) ?? []).intersection(known).contains(providerID)
    }

    static func set(
        _ present: Bool,
        for providerID: String,
        defaults: UserDefaults = .standard
    ) {
        guard CapacityDockProvider(rawValue: providerID) != nil else { return }
        let update = {
            let ordered = lock.withLock {
                let known = Set(CapacityDockPreferences.supportedProviders.map(\.id))
                var identifiers = Set(defaults.stringArray(forKey: key) ?? []).intersection(known)
                if present {
                    identifiers.insert(providerID)
                } else {
                    identifiers.remove(providerID)
                }
                return CapacityDockPreferences.supportedProviders
                    .map(\.id)
                    .filter(identifiers.contains)
            }
            defaults.set(ordered, forKey: key)
            NotificationCenter.default.post(
                name: .capacityDockCredentialPresenceDidChange,
                object: nil
            )
        }
        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.sync(execute: update)
        }
    }
}
