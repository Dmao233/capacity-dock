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
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = CapacityDockStore.live()
    private var controller: CapacityDockController?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

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
        guard notification.object as? NSWindow === settingsWindow else { return }
        NSApp.setActivationPolicy(.accessory)
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
        item.button?.toolTip = NSLocalizedString("Capacity Dock", comment: "")
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
        item.menu = menu
        statusItem = item
    }

    @objc func showDock() {
        CapacityDockPreferences.setEnabled(true)
    }

    @objc func openSettings() {
        let window = ensureSettingsWindow()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
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
}
