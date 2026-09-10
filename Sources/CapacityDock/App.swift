import AppKit
import SwiftUI

@main
struct CapacityDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Accessory apps still need a Scene. Real settings live in an owned
        // key window; SwiftUI's Settings scene does not present from a
        // nonactivating LSUIElement.
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { appDelegate.openSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .appInfo) {
                Button("Usage overview") { appDelegate.openUsageDetails() }
                    .keyboardShortcut("1", modifiers: .command)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate {
    let store = CapacityDockStore.live()
    private var controller: CapacityDockController?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var billPopover: NSPopover?

    private enum BillPopoverMetrics {
        static let width: CGFloat = 420
        static let height: CGFloat = 660
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        seedFirstLaunchIfNeeded()
        controller = CapacityDockController(store: store)
        controller?.start()
        store.start()
        installStatusItem()
        DisplayCurrencyState.shared.start()
        MenubarBillStore.shared.start()
        APIBalanceStore.shared.start()
        refreshStatusButton()
        NotificationCenter.default.addObserver(
            forName: .capacityDockOpenProviderSettings,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let pane = note.object as? String
            Task { @MainActor in
                if let pane { self?.store.settingsTab = pane }
                self?.openSettings()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .capacityDockMenubarBillDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatusButton()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .capacityDockCurrencyDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatusButton()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        guard window === settingsWindow else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    func popoverShouldDetach(_ popover: NSPopover) -> Bool {
        false
    }

    func popoverDidClose(_ notification: Notification) {
        statusItem?.length = NSStatusItem.variableLength
        refreshStatusButton()
    }

    private func seedFirstLaunchIfNeeded() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: CapacityDockPreferences.selectedProvidersKey) == nil {
            CapacityDockPreferences.setSelectedProviders([.grok, .claude, .codex, .cursor])
            CapacityDockPreferences.setPreferredProvider(.grok)
        }
        if defaults.object(forKey: CapacityDockPreferences.enabledKey) == nil {
            CapacityDockPreferences.setEnabled(true)
        }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(statusItemActivated(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        refreshStatusButton()
    }

    private func refreshStatusButton() {
        guard let button = statusItem?.button else { return }
        button.image = nil
        button.imagePosition = .noImage
        let badge = MenubarBillStore.shared.badge
        let currency = DisplayCurrencyState.shared.snapshot
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        let composed = NSMutableAttributedString(string: "")
        let apiBalances = APIBalanceStore.shared
        if let balance = apiBalances.menuText {
            let image: NSImage?
            if apiBalances.accounts.count == 1, apiBalances.accounts.first?.kind == .deepSeek {
                image = ProviderIconCache.image(named: "deepseek")
            } else {
                image = NSImage(systemSymbolName: apiBalances.accounts.count == 1 ? "server.rack" : "creditcard", accessibilityDescription: "API 余额")
            }
            if let image {
                let attachment = NSTextAttachment()
                attachment.image = image
                attachment.bounds = NSRect(x: 0, y: -2, width: 16, height: 13)
                composed.append(NSAttributedString(attachment: attachment))
            }
            composed.append(NSAttributedString(string: " \(balance) ｜ ", attributes: [.font: font]))
        }
        composed.append(NSAttributedString(string: "◉"))
        var textAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .baselineOffset: -1.0
        ]
        if badge == .pending {
            textAttrs[.foregroundColor] = NSColor.secondaryLabelColor
        }
        composed.append(NSAttributedString(string: badge.menubarText(currency: currency), attributes: textAttrs))
        button.attributedTitle = composed
        button.setAccessibilityTitle(
            NSLocalizedString("Capacity Dock", comment: "") + (apiBalances.menuText.map { " API 剩余 " + $0 + " 今日消耗 " } ?? "") + badge.menubarText(currency: currency)
        )
        button.toolTip = NSLocalizedString("Usage details. Right-click for settings.", comment: "") + (apiBalances.accounts.isEmpty ? "" : "\nAPI 余额与本地日志估算分别显示；↻ 表示上次余额，详情查看更新时间。")
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(
            title: NSLocalizedString("Show Capacity Dock", comment: ""),
            action: #selector(showDock),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(
            title: NSLocalizedString("Capacity Dock Settings…", comment: ""),
            action: #selector(openSettings),
            keyEquivalent: ","
        ))
        menu.addItem(NSMenuItem(
            title: NSLocalizedString("Usage…", comment: ""),
            action: #selector(openUsage),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(
            title: NSLocalizedString("Check for Updates", comment: ""),
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        ))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: NSLocalizedString("Quit Capacity Dock", comment: ""),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        menu.items.forEach { $0.target = $0.action == #selector(NSApplication.terminate(_:)) ? nil : self }
        return menu
    }

    @objc func statusItemActivated(_ sender: Any?) {
        let event = NSApp.currentEvent
        switch StatusItemActivation.route(
            eventType: event?.type ?? .leftMouseUp,
            modifierFlags: event?.modifierFlags ?? []
        ) {
        case .openUsageDetails:
            openUsageDetails()
        case .showSettingsMenu:
            showStatusMenu()
        }
    }

    private func showStatusMenu() {
        guard let button = statusItem?.button else { return }
        closeBillPopover()
        makeStatusMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: button)
    }

    private func closeBillPopover() {
        if billPopover?.isShown == true {
            billPopover?.performClose(nil)
        }
    }

    @objc func showDock() {
        CapacityDockPreferences.setEnabled(true)
    }

    @objc func openSettings() {
        closeBillPopover()
        NSApp.setActivationPolicy(.regular)
        let window = ensureSettingsWindow()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    @objc func openUsage() {
        store.settingsTab = "usage"
        openSettings()
    }

    @objc func openUsageDetails() {
        guard let button = statusItem?.button else { return }
        let popover = ensureBillPopover()
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        // Stay accessory. Activating .regular here hides the menu bar the way
        // the old titled bill window did. The popover takes key focus itself.
        refreshStatusButton()
        statusItem?.length = max(button.bounds.width, 1)
        // Give the accessory app focus before presenting its transient panel,
        // so the first control click is not consumed by application activation.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if let window = popover.contentViewController?.view.window {
            window.level = .statusBar
            window.collectionBehavior.insert(.fullScreenAuxiliary)
            window.collectionBehavior.insert(.canJoinAllSpaces)
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc func checkForUpdates() {
        openSettings()
        NotificationCenter.default.post(name: .capacityDockCheckForUpdates, object: nil)
    }

    private func ensureSettingsWindow() -> NSWindow {
        if let settingsWindow {
            return settingsWindow
        }
        let hosting = NSHostingController(
            rootView: CapacityDockSettingsView(store: store)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 620),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("Capacity Dock Settings", comment: "")
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        let appearance = UserDefaults.standard.string(forKey: "CapacityDockBillAppearance") ?? "dark"
        window.appearance = appearance == "system" ? nil : NSAppearance(named: appearance == "light" ? .aqua : .darkAqua)
        window.backgroundColor = NSColor(CapacityDockInterfacePalette.surface(appearance == "light" ? .light : .dark))
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.contentMinSize = NSSize(width: 880, height: 620)
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 880, height: 620))
        window.delegate = self
        // Place once, after content sizing, on the screen where settings was invoked.
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            window.setFrameOrigin(SettingsWindowPlacement.origin(size: window.frame.size, visibleFrame: screen.visibleFrame))
        }
        settingsWindow = window
        return window
    }

    private func ensureBillPopover() -> NSPopover {
        if let billPopover {
            return billPopover
        }
        let popover = NSPopover()
        popover.contentSize = NSSize(width: BillPopoverMetrics.width, height: BillPopoverMetrics.height)
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: BillPopoverView()
                .frame(width: BillPopoverMetrics.width, height: BillPopoverMetrics.height)
        )
        billPopover = popover
        return popover
    }
}

enum StatusItemActivation: Equatable {
    case openUsageDetails
    case showSettingsMenu

    static func route(
        eventType: NSEvent.EventType,
        modifierFlags: NSEvent.ModifierFlags = []
    ) -> StatusItemActivation {
        switch eventType {
        case .rightMouseDown, .rightMouseUp:
            return .showSettingsMenu
        case .leftMouseDown, .leftMouseUp:
            if modifierFlags.contains(.control) {
                return .showSettingsMenu
            }
            return .openUsageDetails
        default:
            return .openUsageDetails
        }
    }
}

/// Center in the usable screen area, including displays with nonzero origins.
enum SettingsWindowPlacement {
    static func origin(size: CGSize, visibleFrame: CGRect) -> CGPoint {
        CGPoint(x: visibleFrame.minX + max(0, (visibleFrame.width - size.width) / 2),
                y: visibleFrame.maxY - size.height - max(0, (visibleFrame.height - size.height) / 2))
    }
}
