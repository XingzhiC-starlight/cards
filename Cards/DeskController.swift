import AppKit

/// The single owner of state and of every window.
///
/// Views and background work never change anything themselves: they `send` a `Command`. The
/// controller applies it to the `Desk`, then derives everything else from the new desk: window
/// frames and contents (`render`), the folder (`Library.save`, debounced) and summary requests
/// (`Summarizer.sync`). None of those is told *what* changed. Each compares the desk with the
/// world and fixes the difference, so each is safe to run any number of times.
final class DeskController {
    private(set) var desk: Desk
    private var grid: Grid
    /// "Hide all" / ⌥⌘C. Presentation only: not part of the desk and not persisted.
    private var hidden = false
    /// One window per popped card, created on pop and closed when the card leaves the desktop.
    private var cardWindows: [CardID: CardWindow] = [:]
    private lazy var stackWindow = StackWindow(send: { [unowned self] in self.send($0) }, menu: appMenu)
    private lazy var summarizer = Summarizer(
        apiKey: { [unowned self] in self.keys.apiKey },
        deliver: { [unowned self] id, summary in self.send(.storeSummary(id, summary)) })
    private let library: Library
    private let keys: KeyStore
    /// The app's menu (Show all, Hide all, Settings…, Quit) for the stack's ribbon button.
    private let appMenu: () -> NSMenu
    private var pendingSave: Task<Void, Never>?
    private var pointerMonitors: [Any] = []

    init(library: Library, keys: KeyStore, appMenu: @escaping () -> NSMenu) {
        self.library = library
        self.keys = keys
        self.appMenu = appMenu
        desk = library.load()
        grid = Self.currentGrid() ?? Grid(area: CGRect(x: 0, y: 0, width: 1512, height: 949))
        summarizer.sync(desk.poppedCards, typing: nil)
        render()
        trackPointer()
    }

    // MARK: The one way state changes

    func send(_ command: Command) {
        let arrived = desk.apply(command)
        switch command {
        case .new, .pop:
            if arrived == nil, desk.firstFreeSlot == nil { NSSound.beep() }   // "Desktop full"
        default:
            break
        }
        scheduleSave()
        summarizer.sync(desk.poppedCards, typing: command.typedCard)
        render()
        if case .new = command, let arrived { cardWindows[arrived]?.focusEditor() }
    }

    // MARK: Menu bar, hotkey, app events

    func setHidden(_ hide: Bool) {
        hidden = hide
        render()
        if !hide {
            NSApp.activate()
            raiseGroup()
        }
    }

    /// ⌥⌘C.
    func toggleHidden() { setHidden(!hidden) }

    func openStack() {
        setHidden(false)
        stackWindow.makeKeyAndOrderFront(nil)
    }

    /// `applicationDidBecomeActive`: the user clicked a card (or used the hotkey or menu).
    /// Raises the whole group, then picks up outside changes to the folder.
    func appDidBecomeActive() {
        raiseGroup()
        flush()
        if let notes = library.rescan() { send(.syncFiles(notes)) }
    }

    /// `applicationDidChangeScreenParameters`: new geometry, same slots. Every card re-snaps.
    func screensChanged() {
        grid = Self.currentGrid() ?? grid
        render()
    }

    /// Settings saved or removed the key.
    func apiKeyChanged() {
        summarizer.sync(desk.poppedCards, typing: nil)
        render()
    }

    /// Save now: on deactivate, quit, and before a rescan.
    func flush() {
        pendingSave?.cancel()
        library.save(desk)
    }

    // MARK: Derived side effects

    /// Reconciles every window with the desk. Compares against the windows' real state, not
    /// against the previous desk, so it also undoes UI drift: a card dropped back near its own
    /// slot (no model change) still snaps home.
    private func render() {
        let faces = desk.cardFaces(hasKey: keys.apiKey != nil)
        let live = Set(faces.map(\.id))
        for (id, window) in cardWindows where !live.contains(id) {
            window.orderOut(nil)
            window.close()
            cardWindows[id] = nil
        }
        for face in faces {
            let window = cardWindows[face.id] ?? makeCardWindow(face.id)
            window.apply(face, frame: grid.frame(of: face.slot))
            show(window)
        }
        stackWindow.apply(desk.stackFace, frame: grid.stackFrame)
        show(stackWindow)
    }

    private func show(_ window: NSWindow) {
        if hidden {
            window.orderOut(nil)
        } else if !window.isVisible {
            window.orderFront(nil)   // only newly shown windows: never reshuffle the z-order
        }
    }

    private func makeCardWindow(_ id: CardID) -> CardWindow {
        let window = CardWindow(id: id,
                                send: { [unowned self] in self.send($0) },
                                slotNear: { [unowned self] in self.grid.nearestSlot(to: $0) })
        cardWindows[id] = window
        return window
    }

    /// macOS brings forward only the clicked window when an app activates. Cards are one group,
    /// so order the stack and every card front, then the key window last so it stays on top.
    /// Another app's click needs no code: its window simply comes in front of ours.
    private func raiseGroup() {
        guard !hidden else { return }
        stackWindow.orderFront(nil)
        for window in cardWindows.values { window.orderFront(nil) }
        NSApp.keyWindow?.orderFront(nil)
    }

    /// Hover follows the pointer's real position, not per-view enter/exit events: a fast pointer
    /// can skip a window's exit event, which would leave its hover buttons showing. A global
    /// monitor sees moves while another app is active, a local one while Cards is; watching the
    /// mouse needs no special permission.
    private func trackPointer() {
        let moved: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: moved) {
            pointerMonitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { moved($0); return $0 }) {
            pointerMonitors.append(monitor)
        }
    }

    private func pointerMoved() {
        let location = NSEvent.mouseLocation
        for window in cardWindows.values { window.pointerMoved(to: location) }
        stackWindow.pointerMoved(to: location)
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled else { return }
            self.library.save(self.desk)
        }
    }

    /// The menu-bar screen.
    private static func currentGrid() -> Grid? {
        Grid(screen: NSScreen.screens.first)
    }
}
