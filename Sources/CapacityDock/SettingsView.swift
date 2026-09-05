import AppKit
import SwiftUI

struct CapacityDockSettingsView: View {
    var store: CapacityDockStore
    @State private var searchText = ""
    @State private var snapshot = CapacityDockPreferences.load()

    private static let mainPaneIDs: Set<String> = ["general", "about", "usage"]
    private static let windowWidth: CGFloat = 880
    private static let windowHeight: CGFloat = 620
    private static let sidebarWidth: CGFloat = 260

    private var providers: [ProviderPane] {
        CapacityDockPreferences.supportedProviders
            .filter { $0.catalogEntry.hasLiveCodeBurnQuotaAdapter }
            .map { provider in
                ProviderPane(
                    id: provider.id,
                    name: provider.displayName,
                    icon: provider.iconName,
                    isConnected: isConnected(provider)
                )
            }
    }

    private var filteredProviders: [ProviderPane] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return providers }
        return providers.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var selection: Binding<String> {
        Binding(
            get: {
                let tab = store.settingsTab
                return Self.mainPaneIDs.contains(tab) || providers.contains { $0.id == tab } ? tab : "general"
            },
            set: { store.settingsTab = $0 }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: Self.sidebarWidth)
                .background {
                    SettingsSidebarMaterial()
                        .ignoresSafeArea()
                }

            Divider()
                .ignoresSafeArea()

            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: Self.windowWidth, minHeight: Self.windowHeight)
        .background {
            SettingsWindowStyleAccessor(title: currentPaneTitle)
                .allowsHitTesting(false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .capacityDockPreferencesDidChange)) { _ in
            snapshot = CapacityDockPreferences.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .capacityDockQuotaDidChange)) { _ in
            snapshot = CapacityDockPreferences.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .capacityDockOpenProviderSettings)) { note in
            if let id = note.object as? String {
                store.settingsTab = id
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            SettingsSidebarSearchField(searchText: $searchText)
                .padding(.horizontal, 8)
                .padding(.top, 16)
                .padding(.bottom, 8)

            List(selection: selection) {
                Section {
                    SettingsSidebarPaneRow(
                        pane: "general",
                        title: NSLocalizedString("General", comment: ""),
                        systemImage: "gearshape.fill",
                        color: .gray
                    )
                    SettingsSidebarPaneRow(
                        pane: "about",
                        title: NSLocalizedString("About", comment: ""),
                        systemImage: "info.circle.fill",
                        color: .gray
                    )
                    SettingsSidebarPaneRow(
                        pane: "usage",
                        title: NSLocalizedString("Usage", comment: ""),
                        systemImage: "list.bullet.rectangle.fill",
                        color: .gray
                    )
                }
                Section {
                    ForEach(filteredProviders) { provider in
                        SettingsSidebarProviderRow(provider: provider)
                            .tag(provider.id)
                    }
                } header: {
                    HStack(spacing: 4) {
                        Text("Providers")
                        Spacer()
                        Text("\(providers.filter(\.isConnected).count) on")
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                            .padding(.trailing, 10)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .padding(.horizontal, 8)
    }

    private var currentPaneTitle: String {
        switch selection.wrappedValue {
        case "general": return NSLocalizedString("General", comment: "")
        case "about": return NSLocalizedString("About", comment: "")
        case "usage": return NSLocalizedString("Usage", comment: "")
        default:
            return providers.first { $0.id == selection.wrappedValue }?.name
                ?? NSLocalizedString("Capacity Dock Settings", comment: "")
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection.wrappedValue {
        case "about":
            AboutSettingsTab(store: store)
        case "usage":
            ConsumptionSettingsTab()
        case "general":
            GeneralSettingsTab(store: store, snapshot: $snapshot)
        default:
            if let provider = CapacityDockProvider(rawValue: selection.wrappedValue) {
                ProviderSettingsTab(store: store, provider: provider)
            } else {
                GeneralSettingsTab(store: store, snapshot: $snapshot)
            }
        }
    }

    private func isConnected(_ provider: CapacityDockProvider) -> Bool {
        store.capacityDockQuotaSummary(for: provider)?.isEstablishedSession == true
    }

    struct ProviderPane: Identifiable {
        let id: String
        let name: String
        let icon: String
        let isConnected: Bool
    }
}

private struct SettingsIconChip: View {
    static let side: CGFloat = 20
    let systemImage: String
    let color: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: Self.side, height: Self.side)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(LinearGradient(
                        colors: [color.opacity(0.85), color],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
            )
            .accessibilityHidden(true)
    }
}

private struct SettingsSidebarPaneRow: View {
    let pane: String
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            SettingsIconChip(systemImage: systemImage, color: color)
            Text(title)
        }
        .tag(pane)
    }
}

private struct SettingsSidebarProviderRow: View {
    let provider: CapacityDockSettingsView.ProviderPane

    var body: some View {
        HStack(spacing: 8) {
            SettingsSidebarBrandIcon(icon: provider.icon, isConnected: provider.isConnected)
            Text(provider.name)
                .foregroundStyle(provider.isConnected ? .primary : .secondary)
            Spacer(minLength: 4)
            if provider.isConnected {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
                    .accessibilityLabel(NSLocalizedString("Connected", comment: ""))
            }
        }
        .opacity(provider.isConnected ? 1 : 0.62)
        .accessibilityAddTraits(provider.isConnected ? [.isSelected] : [])
    }
}

private struct SettingsSidebarBrandIcon: View {
    let icon: String
    let isConnected: Bool

    var body: some View {
        Group {
            if let image = ProviderIconCache.image(named: icon) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "circle.dotted")
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: 16, height: 16)
        .foregroundStyle(isConnected ? .primary : .secondary)
        .accessibilityHidden(true)
    }
}

private struct SettingsSidebarSearchField: View {
    @Binding var searchText: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(NSLocalizedString("Search providers", comment: ""), text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(NSLocalizedString("Clear", comment: ""))
                }
                .buttonStyle(.plain)
            }
        }
        .font(.callout)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1)
        )
    }
}

private struct SettingsSidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: NSVisualEffectView) {
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
    }
}

private struct SettingsWindowStyleAccessor: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> SettingsWindowStyleView {
        SettingsWindowStyleView()
    }

    func updateNSView(_ nsView: SettingsWindowStyleView, context: Context) {
        nsView.paneTitle = title
        nsView.applyStyle()
    }
}

private final class SettingsWindowStyleView: NSView {
    var paneTitle = "Settings"
    private var didPlaceWindow = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyStyle()
    }

    func applyStyle() {
        guard let window else { return }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
        window.styleMask.insert(.resizable)
        window.title = paneTitle
        window.collectionBehavior.insert(.fullScreenPrimary)
        if !didPlaceWindow {
            didPlaceWindow = true
            if let screen = window.screen ?? NSScreen.main,
               !screen.visibleFrame.contains(window.frame) {
                window.center()
            }
        }
    }
}

private struct GeneralSettingsTab: View {
    var store: CapacityDockStore
    @Binding var snapshot: CapacityDockPreferences.Snapshot

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
                ForEach(CapacityDockPreferences.supportedProviders.filter { $0.catalogEntry.hasLiveCodeBurnQuotaAdapter }) { provider in
                    Toggle(isOn: providerBinding(provider)) {
                        HStack(spacing: 7) {
                            if let image = ProviderIconCache.image(named: provider.iconName) {
                                Image(nsImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 15, height: 15)
                            }
                            Text(provider.displayName)
                        }
                    }
                    .disabled(!CapacityDockProviderSelection.canDeselect(
                        provider,
                        selected: snapshot.selectedProviders,
                        isConnected: { store.capacityDockQuotaSummary(for: $0)?.isEstablishedSession == true }
                    ))
                }
                Picker("Preferred provider", selection: preferredBinding) {
                    ForEach(snapshot.selectedProviders) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
            }

            Section("Display") {
                HStack(spacing: 10) {
                    Text("Size")
                    Slider(value: scaleBinding, in: CapacityDockPreferences.scaleRange, step: 0.05)
                        .accessibilityLabel("Capacity Dock size")
                    Text("\(Int((snapshot.scale * 100).rounded()))%")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
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
                Button("Refresh live quotas") {
                    Task { await store.refreshLiveProviders(userInitiated: true) }
                }
                Button("Reload quota.json") {
                    store.reloadOverlay()
                    snapshot = CapacityDockPreferences.load()
                }
            } header: {
                Text("Data")
            } footer: {
                Text("Claude, Codex, Grok, Cursor, Gemini, Copilot, Antigravity, and Kimi are read from logins already on this Mac. ClinePass and Z.ai use an API key saved from this page. Optional quota.json still wins if present.")
            }
        }
        .formStyle(.grouped)
        .padding()
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

private struct AboutSettingsTab: View {
    var store: CapacityDockStore
    @State private var updateResult: UpdateCheckResult?
    @State private var isCheckingUpdate = false

    var body: some View {
        Form {
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
                Text(String(format: NSLocalizedString("You’re up to date (%@).", comment: ""), latest))
                    .foregroundStyle(.secondary)
            case .available(let release):
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(format: NSLocalizedString("%@ is available", comment: ""), release.version))
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
}

private struct ProviderSettingsTab: View {
    var store: CapacityDockStore
    let provider: CapacityDockProvider

    var body: some View {
        Form {
            ProviderConnectionSections(store: store, provider: provider)
                .id(provider.id)
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct ProviderSettingsEditorState: Equatable {
    var providerID: String
    var credential: CapacityDockProviderCredential
    var savedCredential: CapacityDockProviderCredential
    var localError: String?

    static func load(
        providerID: String,
        stored: CapacityDockProviderCredential
    ) -> ProviderSettingsEditorState {
        ProviderSettingsEditorState(
            providerID: providerID,
            credential: stored,
            savedCredential: stored,
            localError: nil
        )
    }

    mutating func beginLoading(providerID: String) {
        guard self.providerID != providerID else { return }
        self = .load(providerID: providerID, stored: CapacityDockProviderCredential())
    }

    mutating func applyLoadedCredential(
        _ stored: CapacityDockProviderCredential,
        for providerID: String
    ) {
        guard self.providerID == providerID else { return }
        self = .load(providerID: providerID, stored: stored)
    }
}

private struct ProviderConnectionSections: View {
    var store: CapacityDockStore
    let provider: CapacityDockProvider
    @State private var editor = ProviderSettingsEditorState.load(
        providerID: "",
        stored: CapacityDockProviderCredential()
    )
    @State private var credentialIsLoading = false

    private var summary: QuotaSummary? {
        store.capacityDockQuotaSummary(for: provider)
    }

    private var isLoading: Bool {
        store.loading.contains(provider.id)
    }

    private var isConnected: Bool {
        summary?.isEstablishedSession == true
    }

    private var hasLiveAdapter: Bool {
        CapacityDockStore.liveProviderIDs.contains(provider.id)
    }

    private var sourceModes: [ProviderReferenceSourceMode] {
        ProviderReferenceSourceMode.allCases.filter(provider.catalogEntry.sourceModes.contains)
    }

    private var authMethods: [ProviderAuthMethod] {
        ProviderAuthMethod.allCases.filter(provider.catalogEntry.authMethods.contains)
    }

    private var supportsAPIKey: Bool {
        provider.catalogEntry.authMethods.contains(.apiTokenOrCloudCredentials)
    }

    var body: some View {
        Group {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: connectionIcon)
                        .font(.system(size: 18))
                        .foregroundStyle(connectionTint)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(connectionTitle)
                            .font(.system(size: 12, weight: .semibold))
                        Text(connectionDetail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if isLoading {
                        ProgressView().controlSize(.small)
                    } else if isConnected {
                        Button("Disconnect", role: .destructive) {
                            Task {
                                do {
                                    try await store.disconnectCapacityDockProvider(provider)
                                    editor = .load(
                                        providerID: provider.id,
                                        stored: CapacityDockProviderCredential()
                                    )
                                } catch {
                                    editor.localError = error.localizedDescription
                                }
                            }
                        }
                    } else {
                        Button(primaryConnectionButtonTitle, action: connect)
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Connection")
            } footer: {
                Text("Automatic connection uses the provider's existing app, CLI, OAuth, or environment credentials first. Capacity Dock does not copy those source credentials into its Keychain.")
                    .font(.system(size: 11))
            }

            Section("Authentication methods") {
                ForEach(authMethods, id: \.self) { method in
                    Label(method.title, systemImage: authIcon(method))
                        .font(.system(size: 11.5))
                }
            }

            if hasLiveAdapter {
                Section {
                    Picker("Source", selection: $editor.credential.sourceMode) {
                        ForEach(sourceModes, id: \.self) { source in
                            Text(sourceTitle(source)).tag(source.rawValue)
                        }
                    }
                    .pickerStyle(.menu)

                    if supportsAPIKey {
                        SecureField("API key or token", text: $editor.credential.apiKey)
                    }

                    HStack {
                        Button("Save & Connect") { saveAndConnect() }
                            .buttonStyle(.borderedProminent)
                        Button("Clear Override") {
                            Task {
                                do {
                                    try await store.disconnectCapacityDockProvider(provider)
                                    editor = .load(
                                        providerID: provider.id,
                                        stored: CapacityDockProviderCredential()
                                    )
                                } catch {
                                    editor.localError = error.localizedDescription
                                }
                            }
                        }
                        .disabled(editor.savedCredential.isEmpty || credentialIsLoading)
                    }

                    if let localError = editor.localError {
                        Text(localError)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Connection override")
                } footer: {
                    Text("Overrides are optional and are saved only when you press Save & Connect.")
                        .font(.system(size: 11))
                }
                .disabled(credentialIsLoading)
            }
        }
        .task(id: provider.id) {
            await reloadEditor()
        }
    }

    private var connectionTitle: String {
        if isLoading { return NSLocalizedString("Connecting…", comment: "") }
        guard let summary else { return NSLocalizedString("Not connected", comment: "") }
        switch summary.connection {
        case .connected: return NSLocalizedString("Connected", comment: "")
        case .loading: return NSLocalizedString("Connecting…", comment: "")
        case .stale: return NSLocalizedString("Refreshing…", comment: "")
        case .transientFailure: return NSLocalizedString("Retrying", comment: "")
        case .terminalFailure: return NSLocalizedString("Reconnect required", comment: "")
        case .disconnected: return NSLocalizedString("Not connected", comment: "")
        }
    }

    private var connectionDetail: String {
        if let line = summary?.footerLines.first, !line.isEmpty {
            return line
        }
        if case let .terminalFailure(reason) = summary?.connection, let reason, !reason.isEmpty {
            return "\(reason) \(ProviderConnectionGuidance.instruction(for: provider))"
        }
        return isConnected
            ? NSLocalizedString("Live quota is available to Capacity Dock.", comment: "")
            : ProviderConnectionGuidance.instruction(for: provider)
    }

    private var connectionIcon: String {
        if isLoading { return "ellipsis.circle" }
        return isConnected ? "checkmark.circle.fill" : "link.circle"
    }

    private var connectionTint: Color {
        if isConnected { return .green }
        if case .terminalFailure = summary?.connection { return .red }
        return .secondary
    }

    private var requiresExplicitCredential: Bool {
        provider.catalogEntry.authMethods == [.apiTokenOrCloudCredentials]
    }

    private var submissionAction: ProviderConnectionSubmissionPolicy.Action {
        ProviderConnectionSubmissionPolicy.resolve(
            credential: editor.credential,
            savedCredential: editor.savedCredential,
            requiresExplicitCredential: requiresExplicitCredential
        )
    }

    private var primaryConnectionButtonTitle: String {
        switch submissionAction {
        case .saveAndConnect: return NSLocalizedString("Save & Connect", comment: "")
        case .connect, .requiresCredential:
            return summary == nil
                ? NSLocalizedString("Connect", comment: "")
                : NSLocalizedString("Retry", comment: "")
        }
    }

    private func authIcon(_ method: ProviderAuthMethod) -> String {
        switch method {
        case .localAppOrCLI: "terminal"
        case .oauth: "person.badge.key"
        case .apiTokenOrCloudCredentials: "key"
        case .cookieOrWebSession: "globe"
        case .localhost: "network"
        case .none: "checkmark.seal"
        }
    }

    private func sourceTitle(_ source: ProviderReferenceSourceMode) -> String {
        switch source {
        case .automatic: NSLocalizedString("Automatic", comment: "")
        case .web: NSLocalizedString("Browser session", comment: "")
        case .cli: "CLI"
        case .oauth: "OAuth"
        case .api: "API"
        }
    }

    private func saveAndConnect() {
        if requiresExplicitCredential,
           editor.credential.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            editor.localError = ProviderConnectionGuidance.instruction(for: provider)
            return
        }
        let credential = editor.credential
        Task {
            do {
                try await store.saveCapacityDockCredential(credential, for: provider)
                editor.savedCredential = credential
                editor.localError = nil
                await store.connectCapacityDockProvider(provider)
            } catch {
                editor.localError = error.localizedDescription
            }
        }
    }

    private func connect() {
        switch submissionAction {
        case .requiresCredential:
            editor.localError = ProviderConnectionGuidance.instruction(for: provider)
        case .saveAndConnect:
            saveAndConnect()
        case .connect:
            editor.localError = nil
            Task { await store.connectCapacityDockProvider(provider) }
        }
    }

    private func reloadEditor() async {
        let providerID = provider.id
        editor.beginLoading(providerID: providerID)
        credentialIsLoading = true
        defer {
            if editor.providerID == providerID {
                credentialIsLoading = false
            }
        }
        do {
            let stored = try await CapacityDockProviderCredentialStore.loadAsync(for: providerID)
            guard !Task.isCancelled else { return }
            editor.applyLoadedCredential(stored, for: providerID)
        } catch {
            guard !Task.isCancelled, editor.providerID == providerID else { return }
            editor.localError = error.localizedDescription
        }
    }
}
