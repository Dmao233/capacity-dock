import SwiftUI

struct CapacityDockSettingsView: View {
    var store: CapacityDockStore
    @State private var snapshot = CapacityDockPreferences.load()

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
                Text("Optional overlay: ~/Library/Application Support/CapacityDock/quota.json")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Reload quota.json") {
                    store.reloadOverlay()
                    snapshot = CapacityDockPreferences.load()
                }
            } header: {
                Text("Data")
            }
        }
        .formStyle(.grouped)
        .padding()
        .onReceive(NotificationCenter.default.publisher(for: .capacityDockPreferencesDidChange)) { _ in
            snapshot = CapacityDockPreferences.load()
        }
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
