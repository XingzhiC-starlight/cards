import AppKit

/// One popped card: a borderless window on the normal layer that follows the user across Spaces
/// and over full-screen apps. It displays one `CardFace` and owns only transient UI state
/// (hover, editing, a drag in progress); everything else it reports as a `Command`.
final class CardWindow: NSWindow {
    let cardID: CardID
    private let cardView: CardView

    init(id: CardID, send: @escaping (Command) -> Void, slotNear: @escaping (CGPoint) -> Slot) {
        cardID = id
        cardView = CardView(id: id, send: send, slotNear: slotNear)
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        configureAsCard(self)
        contentView = cardView
    }

    /// Borderless windows refuse key status by default; a card must take keyboard focus.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func becomeKey() {
        super.becomeKey()
        cardView.editingStateChanged()
    }

    override func resignKey() {
        super.resignKey()
        cardView.editingStateChanged()
    }

    func apply(_ face: CardFace, frame: CGRect) {
        if self.frame != frame {
            if isVisible {
                animator().setFrame(frame, display: true)
            } else {
                setFrame(frame, display: false)
            }
        }
        cardView.apply(face)
    }

    func focusEditor() {
        makeKeyAndOrderFront(nil)
        cardView.focusEditor()
    }

    /// The pointer moved; `location` is in screen coordinates. The hover buttons show while it is
    /// over this card.
    func pointerMoved(to location: NSPoint) {
        cardView.setHovering(isVisible && frame.contains(location))
    }
}

/// The window settings cards and the stack share: borderless, transparent corners, normal level,
/// on every Space and over full-screen apps, always the light look.
func configureAsCard(_ window: NSWindow) {
    window.isReleasedWhenClosed = false
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = true
    window.level = .normal
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    window.acceptsMouseMovedEvents = true
    window.appearance = NSAppearance(named: .aqua)   // "neutral light cards", also in Dark Mode
}

/// Card geometry shared by the card and the stack: the gap between neighbours and the corner radius.
enum CardShape {
    static let gap: CGFloat = 3
    static let radius: CGFloat = 9
    static let fill = NSColor(white: 0.985, alpha: 1)
    static let border = NSColor(white: 0, alpha: 0.16)

    static func path(in bounds: NSRect, lineWidth: CGFloat) -> NSBezierPath {
        let rect = bounds.insetBy(dx: gap + lineWidth / 2, dy: gap + lineWidth / 2)
        return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    }
}

/// Root view of a card. It owns the one decision about what a press means, in this order:
/// 1. a hover button;
/// 2. the header or the card's margin: a press that moves drags the window, a press on the header
///    that doesn't is a normal text click (`trackWindowDrag`, called from `CardTextView.mouseDown`
///    and from here);
/// 3. the body: text editing, or "expand this card" when collapsed.
final class CardView: NSView {
    let id: CardID
    private let send: (Command) -> Void
    private let slotNear: (CGPoint) -> Slot
    private let editor = CardTextView()
    private let scrollView = NSScrollView()
    private let collapsedHeader = NSTextField(labelWithString: "")
    private let summaryView = SummaryView()
    private let formatBar: FormatBar
    private let hoverButtons = NSStackView()
    private let clarityButton = ActionButton(symbol: "rectangle.compress.vertical", help: "Collapse this card")
    private let refreshButton = ActionButton(symbol: "arrow.clockwise", help: "Refresh summary")
    private var face: CardFace?
    private var hovering = false
    /// Derived from AppKit (key window + editor is first responder), never set from outside.
    private var isEditing = false {
        didSet {
            guard isEditing != oldValue else { return }
            formatBar.isHidden = !isEditing
            needsLayout = true
            needsDisplay = true
        }
    }

    static let formatBarHeight: CGFloat = 24
    /// The card's margin around its content; pressing in it drags the card.
    static let margin = NSSize(width: 16, height: 12)

    init(id: CardID, send: @escaping (Command) -> Void, slotNear: @escaping (CGPoint) -> Slot) {
        self.id = id
        self.send = send
        self.slotNear = slotNear
        formatBar = FormatBar(editor: editor)
        super.init(frame: .zero)

        editor.onChange = { [unowned self] note in self.send(.edit(self.id, note)) }
        editor.onHeaderPress = { [unowned self] event in self.dragIfMoved(event) }
        editor.onFocusChange = { [unowned self] in self.editingStateChanged() }

        scrollView.documentView = editor
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        addSubview(scrollView)

        collapsedHeader.font = EditorStyle.header
        collapsedHeader.textColor = EditorStyle.textColor
        collapsedHeader.lineBreakMode = .byTruncatingTail
        collapsedHeader.maximumNumberOfLines = 1
        addSubview(collapsedHeader)
        addSubview(summaryView)

        formatBar.isHidden = true
        addSubview(formatBar)

        clarityButton.handler = { [unowned self] in
            guard let face = self.face else { return }
            self.send(.setCollapsed(self.id, !face.collapsed))
        }
        refreshButton.handler = { [unowned self] in self.send(.refreshSummary(self.id)) }
        let stackButton = ActionButton(title: "↩ Stack", help: "Return this card to the top of the stack") { [unowned self] in
            self.send(.returnToStack(self.id))
        }
        let trashButton = ActionButton(symbol: "trash", help: "Delete this card") { [unowned self] in
            self.confirmDelete()
        }
        for button in [refreshButton, clarityButton, stackButton, trashButton] {
            hoverButtons.addArrangedSubview(button)
        }
        hoverButtons.spacing = 6
        hoverButtons.alphaValue = 0
        addSubview(hoverButtons)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func apply(_ face: CardFace) {
        let previous = self.face
        self.face = face
        editor.show(face.note)
        collapsedHeader.stringValue = face.note.title
        summaryView.show(face.summary)
        if previous?.collapsed != face.collapsed {
            scrollView.isHidden = face.collapsed
            collapsedHeader.isHidden = !face.collapsed
            summaryView.isHidden = !face.collapsed
            if face.collapsed, window?.firstResponder === editor { window?.makeFirstResponder(nil) }
            let help = face.collapsed ? "Expand this card" : "Collapse this card"
            clarityButton.image = NSImage(systemSymbolName: face.collapsed ? "rectangle.expand.vertical"
                                                                         : "rectangle.compress.vertical",
                                          accessibilityDescription: help)
            clarityButton.toolTip = help
            needsLayout = true
        }
        let canRefresh: Bool = switch face.summary {
        case .body: false
        default: face.collapsed
        }
        refreshButton.isHidden = !canRefresh
        needsDisplay = true
    }

    func focusEditor() {
        window?.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: 0, length: 0))   // New: cursor on the header line
    }

    func editingStateChanged() {
        isEditing = window?.isKeyWindow == true && window?.firstResponder === editor
    }

    // MARK: Layout

    /// The area inside the margin. Everything lives here.
    private var content: NSRect {
        bounds.insetBy(dx: Self.margin.width, dy: Self.margin.height)
    }

    override func layout() {
        super.layout()
        let content = self.content
        let bar = isEditing ? Self.formatBarHeight : 0
        scrollView.frame = NSRect(x: content.minX, y: content.minY + bar,
                                  width: content.width, height: content.height - bar)
        formatBar.frame = NSRect(x: content.minX, y: content.minY, width: content.width, height: Self.formatBarHeight)
        let buttons = hoverButtons.fittingSize
        hoverButtons.frame = NSRect(x: content.maxX - buttons.width, y: content.maxY - buttons.height,
                                    width: buttons.width, height: buttons.height)
        let headerHeight = ceil(EditorStyle.header.boundingRectForFont.height) + 2
        collapsedHeader.frame = NSRect(x: content.minX + 7, y: content.maxY - headerHeight - 2,
                                       width: content.width - 7 - EditorStyle.headerTrailingSpace, height: headerHeight)
        summaryView.frame = NSRect(x: content.minX + 7, y: content.minY,
                                   width: content.width - 14, height: collapsedHeader.frame.minY - content.minY - 4)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let lineWidth: CGFloat = isEditing ? 2 : 1
        let shape = CardShape.path(in: bounds, lineWidth: lineWidth)
        CardShape.fill.setFill()
        shape.fill()
        (isEditing ? NSColor.controlAccentColor.withAlphaComponent(0.85) : CardShape.border).setStroke()
        shape.lineWidth = lineWidth
        shape.stroke()
        window?.invalidateShadow()
    }

    // MARK: Mouse

    /// The first click on an inactive card already acts (places the caret, drags), as well as
    /// activating the app.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        // A collapsed card's header and body are ours to handle; its buttons stay buttons.
        if face?.collapsed == true, let hit, hit !== self, !(hit is NSButton) { return self }
        return hit
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if face?.collapsed == true, content.contains(point), point.y < collapsedHeader.frame.minY {
            send(.setCollapsed(id, false))      // collapsed body: expand just this card
            return
        }
        _ = dragIfMoved(event)                  // collapsed header or the margin: drag
    }

    func setHovering(_ on: Bool) {
        guard on != hovering else { return }
        hovering = on
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            hoverButtons.animator().alphaValue = on ? 1 : 0
        }
    }

    /// Header press: drag and snap if the pointer moves; report a plain click otherwise.
    private func dragIfMoved(_ event: NSEvent) -> Bool {
        guard let window, let center = trackWindowDrag(from: event, in: window) else { return false }
        send(.move(id, to: slotNear(center)))   // same slot → no model change; render snaps it back
        return true
    }

    private func confirmDelete() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Delete this card?"
        alert.informativeText = "Its Markdown file moves to the Trash."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        let id = self.id
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn { self?.send(.delete(id)) }
        }
    }
}

/// Click or drag? Decided without stealing the click.
///
/// Peeks at the next mouse event *without dequeuing it*. If the button comes up before the
/// pointer has moved `threshold` points, this returns nil and the mouse-up is still in the
/// queue, so the caller can pass the original mouse-down to `NSTextView`, whose own tracking
/// loop then sees that mouse-up and places the caret. Once the pointer passes the threshold the
/// press is a window drag: the window follows the pointer until mouse-up and the function returns
/// the window's final center (screen coordinates) for snapping. Multi-clicks are never drags,
/// so double-click still selects a word in the header.
func trackWindowDrag(from mouseDown: NSEvent, in window: NSWindow, threshold: CGFloat = 4) -> CGPoint? {
    guard mouseDown.clickCount == 1 else { return nil }
    let start = screenLocation(of: mouseDown)
    let origin = window.frame.origin
    func follow(_ event: NSEvent) {
        let now = screenLocation(of: event)
        window.setFrameOrigin(NSPoint(x: origin.x + now.x - start.x, y: origin.y + now.y - start.y))
    }
    var dragging = false
    while let event = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp],
                                       until: .distantFuture, inMode: .eventTracking, dequeue: false) {
        if event.type == .leftMouseUp {
            guard dragging else { return nil }                 // a click: leave the mouse-up queued
            _ = window.nextEvent(matching: .leftMouseUp)       // consume it: the drag is over
            follow(event)                                      // a quick flick can release further on
            return CGPoint(x: window.frame.midX, y: window.frame.midY)
        }
        _ = window.nextEvent(matching: .leftMouseDragged)      // consume the drag we peeked at
        let now = screenLocation(of: event)
        if !dragging && hypot(now.x - start.x, now.y - start.y) < threshold { continue }
        if !dragging { window.orderFront(nil) }
        dragging = true
        follow(event)
    }
    return nil
}

/// Where a mouse event happened, in screen coordinates. Taken from the event itself rather than
/// the live cursor, and independent of the window, which moves during a drag.
private func screenLocation(of event: NSEvent) -> CGPoint {
    guard let location = event.cgEvent?.location, let primary = NSScreen.screens.first else {
        return NSEvent.mouseLocation
    }
    return CGPoint(x: location.x, y: primary.frame.maxY - location.y)   // CG's origin is top-left
}

/// A collapsed card's body: two lines of lighter summary text, a small spinner, or
/// "Summary unavailable" with the reason as its tooltip.
final class SummaryView: NSView {
    private let label = NSTextField(wrappingLabelWithString: "")
    private let spinner = NSProgressIndicator()

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 12)
        label.textColor = NSColor(white: 0.45, alpha: 1)
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        label.cell?.truncatesLastVisibleLine = true
        addSubview(label)
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        addSubview(spinner)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        let height = min(bounds.height, ceil(label.font!.boundingRectForFont.height * 2) + 4)
        label.frame = NSRect(x: 0, y: bounds.maxY - height, width: bounds.width, height: height)
        spinner.frame = NSRect(x: 0, y: bounds.maxY - 18, width: 16, height: 16)
    }

    func show(_ face: SummaryFace) {
        label.toolTip = nil
        switch face {
        case .body(let text):
            label.stringValue = text
            spinner.stopAnimation(nil)
        case .loading:
            label.stringValue = ""
            spinner.startAnimation(nil)
        case .text(let text):
            label.stringValue = text
            spinner.stopAnimation(nil)
        case .unavailable(let reason):
            label.stringValue = "Summary unavailable"
            label.toolTip = reason
            spinner.stopAnimation(nil)
        }
    }
}

/// The five-button bar along the bottom of the card being edited.
final class FormatBar: NSStackView {
    init(editor: CardTextView) {
        super.init(frame: .zero)
        let buttons = [
            ActionButton(symbol: "bold", help: "Bold (⌘B)") { editor.toggle(.bold) },
            ActionButton(symbol: "italic", help: "Italic (⌘I)") { editor.toggle(.italic) },
            ActionButton(symbol: "list.bullet", help: "Bulleted list") { editor.toggleLineKind(.bullet) },
            ActionButton(symbol: "list.number", help: "Numbered list") { editor.toggleLineKind(.numbered) },
            ActionButton(symbol: "checklist", help: "Checklist") { editor.toggleLineKind(.todo(done: false)) },
        ]
        for button in buttons { addArrangedSubview(button) }
        spacing = 14
        edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)
    }

    required init?(coder: NSCoder) { fatalError("not used") }
}

/// NSButton with a closure instead of target/action. Acts on the first click even when the app
/// is inactive, and never takes keyboard focus away from the editor.
final class ActionButton: NSButton {
    var handler: () -> Void = {}

    convenience init(symbol: String, help: String, handler: @escaping () -> Void = {}) {
        self.init(frame: .zero)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: help)
        imagePosition = .imageOnly
        setUp(help: help, handler: handler)
    }

    convenience init(title: String, help: String, handler: @escaping () -> Void = {}) {
        self.init(frame: .zero)
        self.title = title
        font = .systemFont(ofSize: 11)
        setUp(help: help, handler: handler)
    }

    private func setUp(help: String, handler: @escaping () -> Void) {
        self.handler = handler
        toolTip = help
        isBordered = false
        refusesFirstResponder = true
        contentTintColor = NSColor(white: 0.35, alpha: 1)
        target = self
        action = #selector(fire)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @objc private func fire() { handler() }
}
