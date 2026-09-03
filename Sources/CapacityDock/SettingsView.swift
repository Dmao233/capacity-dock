import AppKit
import SwiftUI

struct CapacityDockSettingsView: View {
    var store: CapacityDockStore
    @State private var snapshot = CapacityDockPreferences.load()
    @State private var updateResult: UpdateCheckResult?
    @State private var isCheckingUpdate = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: enabledBinding) {
                    Text("Show Capacity Dock")
                }
                Toggle(isOn: keepExpandedBinding) {
                    Text("Keep Expanded")
                }
                Picker("Dock to Edge", selection: edgeBinding) {
                    Text("Left").tag(CapacityDockEdge.left)
                    Text("Right").tag(CapacityDockEdge.right)
                    Text("Top").tag(CapacityDockEdge.top)
                    Text("Bottom").tag(CapacityDockEdge.bottom)
                }
            } header: {
                Text("Capacity Dock")
            } footer: {
                Text("Rest shows the preferred ring. Hover expands the rest; Keep Expanded keeps every selected ring visible while the detail card still follows the pointer.")
            }

            Section("Dock providers") {
                ForEach(CapacityDockPreferences.supportedProviders) { provider in
                    Toggle(isOn: providerBinding(provider)) {
                        HStack {
                            Text(provider.displayName)
                            Spacer()
                            Text(CapacityDockQuotaPresentation.ringPercentLabel(
                                quota: store.capacityDockQuotaSummary(for: provider)
                            ))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        }
                    }
                    .disabled(!CapacityDockProviderSelection.canDeselect(
                        provider,
                        selected: snapshot.selectedProviders,
                        isConnected: { store.capacityDockQuotaSummary(for: $0)?.connection == .connected }
                    ))
                }
                Picker("Preferred provider", selection: preferredBinding) {
                    ForEach(snapshot.selectedProviders) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
            }

            Section("Display") {
                Slider(
                    value: scaleBinding,
                    in: CapacityDockPreferences.scaleRange,
                    step: 0.05
                ) {
                    Text("Capacity Dock size")
                } minimumValueLabel: {
                    Text("60%")
                } maximumValueLabel: {
                    Text("120%")
                }
                Picker("Appearance", selection: themeBinding) {
                    ForEach(CapacityDockTheme.allCases, id: \.self) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                Picker("Gauge shape", selection: gaugeBinding) {
                    ForEach(CapacityDockGaugeShape.allCases, id: \.self) { shape in
                        Text(shape.displayName).tag(shape)
                    }
                }
            }

            Section {
                Text("Rings show “-” until you add ~/Library/Application Support/CapacityDock/quota.json. This app does not invent usage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Reload quota.json") {
                    store.reloadOverlay()
                    snapshot = CapacityDockPreferences.load()
                }
            } header: {
                Text("Data")
            }

            Section {
                LabeledContent("Version", value: AppVersion.current)
                Button("Check for Updates") {
                    Task { await checkForUpdates() }
                }
                .disabled(isCheckingUpdate)
                updateStatus
            } header: {
                Text("Updates")
            } footer: {
                Text("Checks the latest GitHub Release. New builds are ad-hoc signed, so replace the app from the zip rather than using a Sparkle feed.")
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            if updateResult == nil {
                Task { await checkForUpdates() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .capacityDockPreferencesDidChange)) { _ in
            snapshot = CapacityDockPreferences.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .capacityDockCheckForUpdates)) { _ in
            Task { await checkForUpdates() }
        }
    }

    @ViewBuilder
    private var updateStatus: some View {
        if isCheckingUpdate {
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Checking…")
                    .foregroundStyle(.secondary)
            }
        } else {
            switch updateResult {
            case .upToDate(_, let latest):
                Text(
                    String(
                        format: NSLocalizedString("You’re up to date (%@).", comment: ""),
                        latest
                    )
                )
                    .foregroundStyle(.secondary)
            case .available(let release):
                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        String(
                            format: NSLocalizedString("%@ is available", comment: ""),
                            release.version
                        )
                    )
                    Button("Open Release Page") {
                        if let url = URL(string: release.htmlURL) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            case .failed(let message):
                Text(message)
                    .foregroundStyle(.red)
            case .none:
                EmptyView()
            }
        }
    }

    private func checkForUpdates() async {
        isCheckingUpdate = true
        defer { isCheckingUpdate = false }
        updateResult = await UpdateChecker.check()
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { snapshot.isEnabled },
            set: { CapacityDockPreferences.setEnabled($0) }
        )
    }

    private var keepExpandedBinding: Binding<Bool> {
        Binding(
            get: { snapshot.keepExpanded },
            set: { CapacityDockPreferences.setKeepExpanded($0) }
        )
    }

    private var edgeBinding: Binding<CapacityDockEdge> {
        Binding(
            get: { snapshot.dockedEdge ?? snapshot.attachmentEdge },
            set: {
                CapacityDockPreferences.setPlacement(
                    dockedEdge: $0,
                    attachmentEdge: $0,
                    normalizedHorizontalOffset: snapshot.normalizedHorizontalOffset,
                    normalizedVerticalOffset: snapshot.normalizedVerticalOffset
                )
            }
        )
    }

    private var preferredBinding: Binding<CapacityDockProvider> {
        Binding(
            get: { snapshot.preferredProvider },
            set: { CapacityDockPreferences.setPreferredProvider($0) }
        )
    }

    private var scaleBinding: Binding<Double> {
        Binding(
            get: { snapshot.scale },
            set: { CapacityDockPreferences.setScale($0) }
        )
    }

    private var themeBinding: Binding<CapacityDockTheme> {
        Binding(
            get: { snapshot.theme },
            set: { CapacityDockPreferences.setTheme($0) }
        )
    }

    private var gaugeBinding: Binding<CapacityDockGaugeShape> {
        Binding(
            get: { snapshot.gaugeShape },
            set: { CapacityDockPreferences.setGaugeShape($0) }
        )
    }

    private func providerBinding(_ provider: CapacityDockProvider) -> Binding<Bool> {
        Binding(
            get: { snapshot.selectedProviders.contains(provider) },
            set: { selected in
                var providers = snapshot.selectedProviders
                if selected {
                    if !providers.contains(provider) { providers.append(provider) }
                } else {
                    providers.removeAll { $0 == provider }
                }
                CapacityDockPreferences.setSelectedProviders(providers)
            }
        )
    }
}
