import AppKit

/// The stack: its own card-sized window, the app's control center. Same window behaviour as a
/// card (borderless, normal layer, all Spaces), dragged by its ribbon instead of a header, and it
/// never hides: under Hide all it shrinks to its ribbon. Its selected card is edited in place.
final class StackWindow: NSWindow {
    private let stackView: StackView
    private let send: (Command) -> Void
    private var swipes = SwipeTracker()
    /// The full card frame from the last `apply`, which the window is only the top of under Hide all.
    private var cardFrame = CGRect.zero

    init(send: @escaping (Command) -> Void, menu: @escaping () -> NSMenu, toggleHidden: @escaping () -> Void,
         drag: WindowDrag) {
        self.send = send
        stackView = StackView(send: send, menu: menu, toggleHidden: toggleHidden)
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        configureAsCard(self)
        contentView = stackView
        // A drag always reports the whole card, whose top edge is the ribbon's.
        stackView.onRibbonPress = { [unowned self] event in
            func card(_ frame: CGRect) -> CGRect {
                CGRect(x: frame.minX, y: frame.maxY - self.cardFrame.height,
                       width: self.cardFrame.width, height: self.cardFrame.height)
            }
            guard let frame = trackWindowDrag(from: event, in: self, moved: { drag.moved(card($0)) }) else { return false }
            drag.dropped(card(frame))
            return true
        }
    }

    override var canBecomeKey: Bool { true }

    /// A two-finger horizontal swipe flips the stack; a vertical one scrolls the card's text.
    override func sendEvent(_ event: NSEvent) {
        guard event.type == .scrollWheel, stackView.showsCard else {
            super.sendEvent(event)
            return
        }
        switch swipes.feed(phase: event.phase, momentumPhase: event.momentumPhase,
                           deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY, at: event.timestamp) {
        case .pass: super.sendEvent(event)
        case .consume: break
        case .flip(let direction): send(.flipStack(direction))
        }
    }

    override func becomeKey() {
        super.becomeKey()
        stackView.editingStateChanged()
    }

    override func resignKey() {
        super.resignKey()
        stackView.editingStateChanged()
    }

    /// Under Hide all (`visibility`) the window shrinks to the top of `cell` and the card area
    /// goes; the ribbon's button then offers Show all.
    func apply(_ face: StackFace, cell: CGRect, visibility: Visibility) {
        cardFrame = cell
        stackView.apply(face, visibility: visibility)
        let frame = visibility.showsStackCard ? cell : Self.ribbonOnlyFrame(in: cell)
        guard self.frame != frame else { return }
        if isVisible && self.frame.size == frame.size {
            animator().setFrame(frame, display: true)   // snapping or sliding back on screen
        } else {
            setFrame(frame, display: true)
        }
    }

    /// The ribbon and the gap around it, at the top of the stack's cell.
    static func ribbonOnlyFrame(in cell: CGRect) -> CGRect {
        let height = StackView.ribbonHeight + 2 * CardShape.gap
        return CGRect(x: cell.minX, y: cell.maxY - height, width: cell.width, height: height)
    }

    /// Makes this window key with the cursor in the shown card (the blank page after New refused).
    func focusEditor() {
        makeKeyAndOrderFront(nil)
        stackView.focusEditor()
    }

    /// The shown card's selection while it is being edited, for Pop to carry to the popped card.
    var editingSelection: NSRange? { stackView.editingSelection }

    /// The pointer moved; `location` is in screen coordinates.
    func pointerMoved(to location: NSPoint) {
        stackView.hover(at: isVisible && frame.contains(location) ? convertPoint(fromScreen: location) : nil)
    }
}

/// Looks like one card: a sky-blue ribbon with the toolbar (New, Pop, Clarity), "Desktop full",
/// the Hide all / Show all button and the app menu button, above the selected stacked card, which
/// is a full `CardView`. The count badge sits in that card's bottom-right corner, and in the
/// ribbon beside the Show all button while Hide all has removed the card. The window's margin is
/// four invisible edge bands that select another stacked card: left/top the previous,
/// right/bottom the next. Pop takes the selected card.
/// The stack draws the card shape and the editing border; the `CardView` inside draws nothing.
private final class StackView: NSView {
    /// A press on the ribbon's empty space: true when it moved and dragged the window, false for a click.
    var onRibbonPress: (NSEvent) -> Bool = { _ in false }
    private let send: (Command) -> Void
    private let toolbar = NSStackView()
    private let popButton: ActionButton
    private let clarityButton: ActionButton
    private let toggleButton: ActionButton
    private let menuButton = ActionButton(symbol: "ellipsis.circle", help: "Settings and quit")
    private let cardView: CardView
    /// False under Hide all: the window is only the ribbon, and the edge bands do nothing.
    private(set) var showsCard = true
    /// Hide all is on, so the toggle offers Show all.
    private var allHidden = false {
        didSet {
            guard allHidden != oldValue else { return }
            let help = allHidden ? "Show all" : "Hide all"
            toggleButton.image = NSImage(systemSymbolName: allHidden ? "eye" : "eye.slash", accessibilityDescription: help)
            toggleButton.toolTip = help
        }
    }
    private let badge = PassiveLabel(labelWithString: "0")
    private let fullLabel = NSTextField(labelWithString: "Desktop full")
    private var hoveredEdge: Edge? {
        didSet { if hoveredEdge != oldValue { needsDisplay = true } }
    }
    private var cardEditing = false {
        didSet { if cardEditing != oldValue { needsDisplay = true } }
    }

    static let ribbonHeight: CGFloat = 40
    static let ribbon = NSColor(srgbRed: 0.56, green: 0.80, blue: 0.98, alpha: 1)
    static let ribbonText = NSColor(srgbRed: 0.04, green: 0.21, blue: 0.37, alpha: 1)

    init(send: @escaping (Command) -> Void, menu: @escaping () -> NSMenu, toggleHidden: @escaping () -> Void) {
        self.send = send
        cardView = CardView(home: .stack, send: send)
        popButton = ActionButton(title: "Pop", help: "Bring the selected card out") { send(.pop) }
        clarityButton = ActionButton(title: "Clarity: Off", help: "Collapse or expand every card") { send(.toggleClarity) }
        toggleButton = ActionButton(symbol: "eye.slash", help: "Hide all") { toggleHidden() }
        super.init(frame: .zero)

        let newButton = ActionButton(title: "New", help: "Create a card") { send(.new(at: Date())) }
        for button in [newButton, popButton, clarityButton] {
            button.font = .systemFont(ofSize: 12, weight: .semibold)
            button.contentTintColor = Self.ribbonText
            toolbar.addArrangedSubview(button)
        }
        toolbar.spacing = 14
        addSubview(toolbar)

        toggleButton.contentTintColor = Self.ribbonText
        addSubview(toggleButton)

        menuButton.contentTintColor = Self.ribbonText
        menuButton.handler = { [unowned menuButton] in
            // Drops down from the button, like a menu bar menu (the button view is flipped).
            menu().popUp(positioning: nil, at: NSPoint(x: 0, y: menuButton.bounds.maxY + 4), in: menuButton)
        }
        addSubview(menuButton)

        cardView.onEditingChange = { [unowned self] editing in self.cardEditing = editing }
        addSubview(cardView)

        badge.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        badge.textColor = Self.ribbonText
        badge.alignment = .center
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 8
        badge.toolTip = "Cards in the stack"
        addSubview(badge)

        fullLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        fullLabel.textColor = NSColor(srgbRed: 0.70, green: 0.07, blue: 0.07, alpha: 1)
        fullLabel.lineBreakMode = .byTruncatingTail
        fullLabel.toolTip = "Desktop full: no free slot for Pop or New"   // truncated, it may read only "…"
        fullLabel.isHidden = true
        addSubview(fullLabel)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func apply(_ face: StackFace, visibility: Visibility) {
        let showsCard = visibility.showsStackCard
        if self.showsCard != showsCard {
            self.showsCard = showsCard
            cardView.isHidden = !showsCard
            if !showsCard {
                cardView.dropFocus()
                hoveredEdge = nil
            }
        }
        allHidden = visibility.isHidden
        cardView.apply(face.selected)
        badge.stringValue = "\(face.count)"
        fullLabel.isHidden = !face.desktopFull
        popButton.isEnabled = face.selected != nil && !face.desktopFull
        clarityButton.title = face.clarity ? "Clarity: On" : "Clarity: Off"
        clarityButton.contentTintColor = face.clarity ? .white : Self.ribbonText
        needsLayout = true
        needsDisplay = true
    }

    /// The pointer is at `point` (view coordinates), or outside the window.
    func hover(at point: NSPoint?) {
        hoveredEdge = point.flatMap(edge(at:))
        cardView.setHovering(showsCard && point.map { cardView.frame.contains($0) } ?? false)
    }

    func editingStateChanged() { cardView.editingStateChanged() }

    func focusEditor() { cardView.focusEditor() }

    var editingSelection: NSRange? { cardView.editingSelection }

    // MARK: Layout

    /// Everything but the edge bands lives inside this.
    private var content: NSRect {
        bounds.insetBy(dx: bounds.width * EdgeBands.fraction, dy: bounds.height * EdgeBands.fraction)
    }

    /// The ribbon across the top of the card.
    private var ribbonRect: NSRect {
        NSRect(x: bounds.minX, y: bounds.maxY - CardShape.gap - Self.ribbonHeight,
               width: bounds.width, height: Self.ribbonHeight + CardShape.gap)
    }

    /// Right to left, the ribbon holds the menu button, the Hide all / Show all button, the badge
    /// (only under Hide all, since the card area that normally has it is gone) and "Desktop
    /// full". The toolbar and the buttons never move: "Desktop full" takes what room is left
    /// and truncates, and the badge hides once there is no room for it.
    override func layout() {
        super.layout()
        let inner = content
        let ribbonMid = ribbonRect.minY + Self.ribbonHeight / 2
        // The card's own margin reaches into the edge bands; its text stays inside them.
        let left = max(inner.minX - CardView.margin.width, bounds.minX)
        let right = min(inner.maxX + CardView.margin.width, bounds.maxX)
        let bottom = max(inner.minY - CardView.margin.height, bounds.minY)
        let card = NSRect(x: left, y: bottom, width: right - left, height: ribbonRect.minY - bottom)
        if showsCard { cardView.frame = card }

        toolbar.frame = NSRect(x: inner.minX, y: ribbonMid - 11, width: toolbar.fittingSize.width, height: 20)
        menuButton.frame = NSRect(x: inner.maxX - 18, y: ribbonMid - 10, width: 18, height: 18)
        toggleButton.frame = NSRect(x: menuButton.frame.minX - 8 - 18, y: ribbonMid - 10, width: 18, height: 18)
        let badgeWidth = max(22, badge.fittingSize.width + 10)
        var trailing = toggleButton.frame.minX
        if showsCard {
            // In the card's bottom-right at its content inset: clear of the hover buttons at the
            // top and of the formatting bar's buttons, which are at the left of its row.
            let text = card.insetBy(dx: CardView.margin.width, dy: CardView.margin.height)
            badge.frame = NSRect(x: text.maxX - badgeWidth, y: text.minY + (CardView.formatBarHeight - 17) / 2,
                                 width: badgeWidth, height: 17)
            badge.layer?.backgroundColor = Self.ribbon.withAlphaComponent(0.4).cgColor
            badge.isHidden = false
        } else {
            badge.frame = NSRect(x: trailing - 8 - badgeWidth, y: ribbonMid - 9.5, width: badgeWidth, height: 17)
            badge.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.75).cgColor
            badge.isHidden = badge.frame.minX < toolbar.frame.maxX + 8
            if !badge.isHidden { trailing = badge.frame.minX }
        }
        let room = max(trailing - toolbar.frame.maxX - 2 * 8, 0)
        let fullWidth = min(fullLabel.fittingSize.width, room)
        fullLabel.frame = NSRect(x: trailing - 8 - fullWidth, y: ribbonMid - 9, width: fullWidth, height: 15)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let lineWidth: CGFloat = cardEditing ? 2 : 1
        let shape = CardShape.path(in: bounds, lineWidth: lineWidth)
        CardShape.fill.setFill()
        shape.fill()
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        Self.ribbon.setFill()
        ribbonRect.fill()
        if let edge = hoveredEdge {
            NSColor(white: 0, alpha: 0.06).setFill()
            EdgeBands.rect(of: edge, in: bounds).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        if let edge = hoveredEdge {
            let band = EdgeBands.rect(of: edge, in: bounds)
            let chevron = NSAttributedString(string: edge.direction == .previous ? "‹" : "›", attributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: NSColor(white: 0, alpha: 0.45),
            ])
            let size = chevron.size()
            chevron.draw(at: NSPoint(x: band.midX - size.width / 2, y: band.midY - size.height / 2))
        }
        (cardEditing ? NSColor.controlAccentColor.withAlphaComponent(0.85) : CardShape.border).setStroke()
        shape.lineWidth = lineWidth
        shape.stroke()
        window?.invalidateShadow()
    }

    // MARK: Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The ribbon's labels (badge, "Desktop full") and the toolbar's gaps are part of its
    /// draggable empty space; only its buttons stay buttons.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if let hit, !(hit is NSButton), ribbonRect.contains(convert(point, from: superview)) { return self }
        return hit
    }

    /// The ribbon drags the window. A press anywhere that does not move is a click, which the
    /// edge band under it, if any, turns into a flip.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if ribbonRect.contains(point), onRibbonPress(event) { return }
        if let edge = edge(at: point) {
            send(.flipStack(edge.direction))
        }
    }

    private func edge(at point: CGPoint) -> Edge? {
        guard showsCard, !content.contains(point) else { return nil }
        return EdgeBands.edge(at: point, in: bounds)
    }
}

/// A label that takes no click, so a press on it reaches whatever is under it.
private final class PassiveLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
