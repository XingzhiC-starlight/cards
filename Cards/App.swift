import AppKit
import Carbon.HIToolbox

// Entry point and app-level wiring: menu bar item, global hotkey, app events.
// The build settings set LSUIElement = YES (menu bar app, no Dock icon).

@main
enum CardsApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let keys = KeyStore()
    private var controller: DeskController?
    private var statusItem: NSStatusItem?
    private var hotKey: HotKey?
    private var settingsWindow: SettingsWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        // `-CardsFolder <path>` on the command line points the app at another folder (for trying
        // things out without touching ~/Documents/Cards).
        let folder = UserDefaults.standard.string(forKey: "CardsFolder").map { URL(filePath: $0, directoryHint: .isDirectory) }
        let controller = DeskController(library: Library(folder: folder ?? Library.defaultFolder), keys: keys,
                                        appMenu: { [unowned self] in self.makeAppMenu(includingOpenStack: false) })
        self.controller = controller
        statusItem = makeStatusItem()
        hotKey = HotKey(keyCode: kVK_ANSI_C, modifiers: optionKey | cmdKey) { controller.toggleHidden() }
        NSApp.activate()
    }

    func applicationDidBecomeActive(_ notification: Notification) { controller?.appDidBecomeActive() }
    func applicationDidResignActive(_ notification: Notification) { controller?.flush() }
    func applicationWillTerminate(_ notification: Notification) { controller?.flush() }
    func applicationDidChangeScreenParameters(_ notification: Notification) { controller?.screensChanged() }

    /// Menu bar icon. A crowded menu bar can hide it behind the notch, so the stack's ribbon
    /// offers the same menu.
    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "Cards")
        item.menu = makeAppMenu(includingOpenStack: true)
        return item
    }

    /// The app's menu: Show all / Hide all / Open stack / Settings… / Quit. The one list for both
    /// the menu bar icon and the stack's ribbon button, which leaves out Open stack.
    private func makeAppMenu(includingOpenStack: Bool) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Show All", action: #selector(showAll), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Hide All", action: #selector(hideAll), keyEquivalent: "").target = self
        if includingOpenStack {
            menu.addItem(withTitle: "Open Stack", action: #selector(openStack), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Cards", action: #selector(quit), keyEquivalent: "").target = self
        return menu
    }

    /// Never shown (accessory apps have no menu bar), but key equivalents still route through it:
    /// Edit (Undo, Redo, Cut, Copy, Paste, Select All) and Format (Bold ⌘B, Italic ⌘I), all
    /// targeting the first responder.
    private func installMainMenu() {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        app.addItem(withTitle: "Quit Cards", action: #selector(quit), keyEquivalent: "q").target = self

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let format = NSMenu(title: "Format")
        format.addItem(withTitle: "Bold", action: #selector(CardTextView.cardsToggleBold(_:)), keyEquivalent: "b")
        format.addItem(withTitle: "Italic", action: #selector(CardTextView.cardsToggleItalic(_:)), keyEquivalent: "i")

        for submenu in [app, edit, format] {
            let item = NSMenuItem()
            item.submenu = submenu
            main.addItem(item)
        }
        NSApp.mainMenu = main
    }

    @objc private func showAll() { controller?.setHidden(false) }
    @objc private func hideAll() { controller?.setHidden(true) }
    @objc private func openStack() { controller?.openStack() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func openSettings() {
        let window = settingsWindow ?? SettingsWindow(keys: keys) { [weak self] in self?.controller?.apiKeyChanged() }
        settingsWindow = window
        NSApp.activate()
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}

/// One system-wide hotkey through Carbon's RegisterEventHotKey: no Accessibility permission.
final class HotKey {
    private let action: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            // A C callback, delivered on the main thread.
            guard let userData else { return noErr }
            MainActor.assumeIsolated { Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().action() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers),
                            EventHotKeyID(signature: OSType(0x4352_4453) /* "CRDS" */, id: 1),
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}
