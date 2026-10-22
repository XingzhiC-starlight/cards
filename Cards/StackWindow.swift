import AppKit

/// The stack: its own card-sized window in the top-left grid cell, the app's control center.
/// Same window behaviour as a card (borderless, normal layer, all Spaces), but it never moves
/// and has no editor.
final class StackWindow: NSWindow {
    private let stackView: StackView

    init(send: @escaping (Command) -> Void, menu: @escaping () -> NSMenu) {
        stackView = StackView(send: send, menu: menu)
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        configureAsCard(self)
        contentView = stackView
    }

    override var canBecomeKey: Bool { true }

    func apply(_ face: StackFace, frame: CGRect) {
        if self.frame != frame { setFrame(frame, display: true) }
        stackView.apply(face)
    }

    /// The pointer moved; `location` is in screen coordinates.
    func pointerMoved(to location: NSPoint) {
        stackView.hover(at: isVisible && frame.contains(location) ? convertPoint(fromScreen: location) : nil)
    }
}

/// Looks like one card: a sky-blue ribbon with the toolbar (New, Pop, Clarity), "Desktop full",
/// the count badge and the app menu button, above the selected stacked card. The window's margin is four invisible
/// edge bands that select another stacked card: left/top the previous, right/bottom the next.
/// Pop takes the selected card.
private final class StackView: NSView {
    private let send: (Command) -> Void
    private let toolbar = NSStackView()
    private let popButton: ActionButton
    private let clarityButton: ActionButton
    private let menuButton = ActionButton(symbol: "ellipsis.circle", help: "Show all, hide all, settings and quit")
    private let preview = CardTextView()
    private let previewClip = PassThroughView()
    private let emptyLabel = NSTextField(labelWithString: "Stack is empty")
    private let badge = NSTextField(labelWithString: "0")
    private let fullLabel = NSTextField(labelWithString: "Desktop full")
    private var face: StackFace?
    private var hoveredEdge: Edge? {
        didSet { if hoveredEdge != oldValue { needsDisplay = true } }
    }

    static let ribbonHeight: CGFloat = 40
    static let ribbon = NSColor(srgbRed: 0.56, green: 0.80, blue: 0.98, alpha: 1)
    static let ribbonText = NSColor(srgbRed: 0.04, green: 0.21, blue: 0.37, alpha: 1)

    init(send: @escaping (Command) -> Void, menu: @escaping () -> NSMenu) {
        self.send = send
        popButton = ActionButton(title: "Pop", help: "Bring the selected card out") { send(.pop(nil)) }
        clarityButton = ActionButton(title: "Clarity: Off", help: "Collapse or expand every card") { send(.toggleClarity) }
        super.init(frame: .zero)

        let newButton = ActionButton(title: "New", help: "Create a card") { send(.new(at: Date())) }
        for button in [newButton, popButton, clarityButton] {
            button.font = .systemFont(ofSize: 12, weight: .semibold)
            button.contentTintColor = Self.ribbonText
            toolbar.addArrangedSubview(button)
        }
        toolbar.spacing = 14
        addSubview(toolbar)

        menuButton.contentTintColor = Self.ribbonText
        menuButton.handler = { [unowned menuButton] in
            // Drops down from the button, like a menu bar menu (the button view is flipped).
            menu().popUp(positioning: nil, at: NSPoint(x: 0, y: menuButton.bounds.maxY + 4), in: menuButton)
        }
        addSubview(menuButton)

        preview.isEditable = false
        preview.isSelectable = false
        previewClip.clipsToBounds = true
        previewClip.addSubview(preview)
        addSubview(previewClip)

        emptyLabel.font = EditorStyle.header
        emptyLabel.textColor = .tertiaryLabelColor
        addSubview(emptyLabel)

        badge.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        badge.textColor = Self.ribbonText
        badge.alignment = .center
        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.75).cgColor
        badge.layer?.cornerRadius = 8
        badge.toolTip = "Cards in the stack"
        addSubview(badge)

        fullLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        fullLabel.textColor = NSColor(srgbRed: 0.70, green: 0.07, blue: 0.07, alpha: 1)
        fullLabel.isHidden = true
        addSubview(fullLabel)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func apply(_ face: StackFace) {
        self.face = face
        if let note = face.topNote { preview.show(note) }
        previewClip.isHidden = face.topNote == nil
        emptyLabel.isHidden = face.topNote != nil
        badge.stringValue = "\(face.count)"
        fullLabel.isHidden = !face.desktopFull
        popButton.isEnabled = face.count > 0 && !face.desktopFull
        clarityButton.title = face.clarity ? "Clarity: On" : "Clarity: Off"
        clarityButton.contentTintColor = face.clarity ? .white : Self.ribbonText
        if !face.canFlip { hoveredEdge = nil }
        needsLayout = true
        needsDisplay = true
    }

    /// The pointer is at `point` (view coordinates), or outside the window.
    func hover(at point: NSPoint?) {
        hoveredEdge = point.flatMap(edge(at:))
    }

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

    override func layout() {
        super.layout()
        let inner = content
        let ribbonMid = ribbonRect.minY + Self.ribbonHeight / 2
        toolbar.frame = NSRect(x: inner.minX, y: ribbonMid - 11, width: inner.width * 0.6, height: 20)
        menuButton.frame = NSRect(x: inner.maxX - 18, y: ribbonMid - 10, width: 18, height: 18)
        let badgeWidth = max(22, badge.fittingSize.width + 10)
        badge.frame = NSRect(x: menuButton.frame.minX - 8 - badgeWidth, y: ribbonMid - 9.5, width: badgeWidth, height: 17)
        let fullWidth = fullLabel.fittingSize.width
        fullLabel.frame = NSRect(x: badge.frame.minX - 8 - fullWidth, y: ribbonMid - 9, width: fullWidth, height: 15)
        let cardTop = ribbonRect.minY - 8
        previewClip.frame = NSRect(x: inner.minX - 4, y: inner.minY, width: inner.width + 4, height: cardTop - inner.minY)
        preview.frame = NSRect(x: 0, y: 0, width: previewClip.bounds.width, height: previewClip.bounds.height)
        emptyLabel.frame = NSRect(x: inner.minX, y: cardTop - 24, width: inner.width, height: 22)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let shape = CardShape.path(in: bounds, lineWidth: 1)
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
        CardShape.border.setStroke()
        shape.stroke()
        window?.invalidateShadow()
    }

    // MARK: Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if let edge = edge(at: convert(event.locationInWindow, from: nil)) {
            send(.flipStack(edge.direction))
        }
    }

    /// The bands are live only when there is a card under the selected one to flip to.
    private func edge(at point: CGPoint) -> Edge? {
        guard face?.canFlip == true, !content.contains(point) else { return nil }
        return EdgeBands.edge(at: point, in: bounds)
    }
}

/// Holds the read-only card; clicks go through it to the stack.
private final class PassThroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
