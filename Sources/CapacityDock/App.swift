import AppKit
import SwiftUI

@main
struct CapacityDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Accessory apps still need a Scene. Real settings live in an owned
        // key window. An empty `Settings` scene is not safe: activating the
        // app (opening the menu-bar panel) could bring up its blank window.
        // A never-inserted menu bar extra owns no window at all.
        MenuBarExtra("Capacity Dock", isInserted: .constant(false)) {
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

    func applicationWillTerminate(_ notification: Notification) {
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            await MenubarBillStore.flushCache()
            done.signal()
        }
        _ = done.wait(timeout: .now() + 3)
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
        // A named slot keeps this item's saved visibility apart from the
        // auto-numbered "Item-0", which reinstalls and the placeholder scene
        // have left marked hidden. The menu-bar item is the app's only entry
        // point, so it is always shown at launch.
        item.autosaveName = "CapacityDockUsage"
        item.isVisible = true
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
        let apiBalances = APIBalanceStore.shared
        let spend = badge.menubarText(currency: currency).trimmingCharacters(in: .whitespaces)
        var segments: [StatusItemTitle.Segment] = []
        if let balance = apiBalances.menuAmounts {
            let icon: NSImage?
            if apiBalances.accounts.count == 1, apiBalances.accounts.first?.kind == .deepSeek {
                icon = ProviderIconCache.image(named: "deepseek")
            } else {
                icon = StatusItemTitle.symbol(apiBalances.accounts.count == 1 ? "server.rack" : "creditcard")
            }
            segments.append(.init(icon: icon, text: balance, dimmed: apiBalances.menuIsStale))
        }
        segments.append(.init(icon: StatusItemTitle.symbol("flame"), text: spend, dimmed: badge == .pending))
        button.attributedTitle = StatusItemTitle.make(segments)
        button.setAccessibilityTitle(
            NSLocalizedString("Capacity Dock", comment: "") + (apiBalances.menuText.map { " API 剩余 " + $0 + " 今日消耗 " } ?? "") + badge.menubarText(currency: currency)
        )
        button.toolTip = NSLocalizedString("Usage details. Right-click for settings.", comment: "") + (apiBalances.accounts.isEmpty ? "" : "\nAPI 余额与本地日志估算分别显示；数字变灰表示余额未及时刷新，详情查看更新时间。")
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
        window.backgroundColor = .windowBackgroundColor
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

/// Menu-bar title: monochrome icon + value pairs with even spacing, drawn
/// in the menu bar's own label colour so colourful provider marks and text
/// glyphs no longer mix with the system items around them.
@MainActor
enum StatusItemTitle {
    struct Segment {
        var icon: NSImage?
        var text: String
        var dimmed = false
    }

    static let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    private static let iconHeight: CGFloat = 14
    private static let iconTextGap: CGFloat = 4
    private static let segmentGap: CGFloat = 10

    static func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
    }

    static func make(_ segments: [Segment]) -> NSAttributedString {
        let title = NSMutableAttributedString()
        for (index, segment) in segments.enumerated() {
            if index > 0 { title.append(spacer(segmentGap)) }
            let color: NSColor = segment.dimmed ? .secondaryLabelColor : .labelColor
            if let icon = segment.icon {
                title.append(attachment(tinted(icon, color: color)))
                title.append(spacer(iconTextGap))
            }
            title.append(NSAttributedString(string: segment.text, attributes: [
                .font: font,
                .foregroundColor: color
            ]))
        }
        return title
    }

    /// Redrawn on every draw so the colour follows light / dark menu bars
    /// and the wallpaper-tinted appearance.
    static func tinted(_ image: NSImage, color: NSColor) -> NSImage {
        let aspect = image.size.height > 0 ? image.size.width / image.size.height : 1
        let size = NSSize(width: (iconHeight * aspect).rounded(), height: iconHeight)
        let ink = TintInk(image: image, color: color)
        let tinted = NSImage(size: size, flipped: false) { rect in
            ink.image.draw(in: rect)
            ink.color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.cacheMode = .never
        return tinted
    }

    private static func attachment(_ image: NSImage) -> NSAttributedString {
        let attachment = NSTextAttachment()
        attachment.image = image
        // Centre the icon on the digits' cap height rather than the baseline.
        let y = ((font.capHeight - image.size.height) / 2).rounded()
        attachment.bounds = NSRect(x: 0, y: y, width: image.size.width, height: image.size.height)
        return NSAttributedString(attachment: attachment)
    }

    private static func spacer(_ width: CGFloat) -> NSAttributedString {
        attachment(NSImage(size: NSSize(width: width, height: 1)))
    }
}

/// Read-only image and dynamic colour handed to the drawing handler.
private struct TintInk: @unchecked Sendable {
    let image: NSImage
    let color: NSColor
}
