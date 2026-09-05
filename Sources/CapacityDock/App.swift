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
        static let width: CGFloat = 360
        static let height: CGFloat = 640
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        seedFirstLaunchIfNeeded()
        controller = CapacityDockController(store: store)
        controller?.start()
        store.start()
        installStatusItem()
        NotificationCenter.default.addObserver(
            forName: .capacityDockOpenProviderSettings,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.openSettings()
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
        item.button?.title = "◉"
        item.button?.setAccessibilityTitle(NSLocalizedString("Capacity Dock", comment: ""))
        item.button?.toolTip = NSLocalizedString("Usage details. Right-click for settings.", comment: "")
        item.button?.target = self
        item.button?.action = #selector(statusItemActivated(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
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
        let window = ensureSettingsWindow()
        NSApp.setActivationPolicy(.regular)
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
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("Capacity Dock Settings", comment: "")
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.contentViewController = hosting
        window.delegate = self
        window.center()
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
            rootView: ConsumptionSettingsTab(compactLayout: true)
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
