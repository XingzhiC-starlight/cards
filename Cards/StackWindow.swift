import AppKit

/// The stack: its own card-sized window in the bottom-right grid cell. Same window behaviour as
/// a card (borderless, normal layer, all Spaces), but it never moves and has no editor.
final class StackWindow: NSWindow {
    private let stackView: StackView

    init(send: @escaping (Command) -> Void) {
        stackView = StackView(send: send)
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        configureAsCard(self)
        contentView = stackView
    }

    override var canBecomeKey: Bool { true }

    func apply(_ face: StackFace, frame: CGRect) {
        if self.frame != frame { setFrame(frame, display: true) }
        stackView.apply(face)
    }
}

/// Toolbar (New, Pop, Clarity), a preview of the top card with a count badge, "Desktop full"
/// while no slot is free, and a scrollable list of every stacked header (click one → pop that
/// card). The window's margin is four invisible edge bands that flip through the stack:
/// left/top shows the previous card, right/bottom the next.
private final class StackView: NSView {
    private let send: (Command) -> Void
    private let toolbar = NSStackView()
    private let popButton: ActionButton
    private let clarityButton: ActionButton
    private let preview = CardTextView()
    private let previewClip = PassThroughView()
    private let emptyLabel = NSTextField(labelWithString: "Stack is empty")
    private let badge = NSTextField(labelWithString: "0")
    private let fullLabel = NSTextField(labelWithString: "Desktop full")
    private let listScroll = NSScrollView()
    private let list = FlippedView()
    private var face: StackFace?
    private var hoveredEdge: Edge? {
        didSet { if hoveredEdge != oldValue { needsDisplay = true } }
    }

    init(send: @escaping (Command) -> Void) {
        self.send = send
        popButton = ActionButton(title: "Pop", help: "Bring the top card out") { send(.pop(nil)) }
        clarityButton = ActionButton(title: "Clarity: Off", help: "Collapse or expand every card") { send(.toggleClarity) }
        super.init(frame: .zero)

        let newButton = ActionButton(title: "New", help: "Create a card") { send(.new(at: Date())) }
        for button in [newButton, popButton, clarityButton] {
            button.font = .systemFont(ofSize: 12, weight: .medium)
            toolbar.addArrangedSubview(button)
        }
        toolbar.spacing = 14
        addSubview(toolbar)

        preview.isEditable = false
        preview.isSelectable = false
        previewClip.clipsToBounds = true
        previewClip.addSubview(preview)
        addSubview(previewClip)

        emptyLabel.font = EditorStyle.header
        emptyLabel.textColor = .tertiaryLabelColor
        addSubview(emptyLabel)

        badge.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        badge.textColor = .white
        badge.alignment = .center
        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor(white: 0.45, alpha: 1).cgColor
        badge.layer?.cornerRadius = 8
        addSubview(badge)

        fullLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        fullLabel.textColor = .systemRed
        fullLabel.isHidden = true
        addSubview(fullLabel)

        listScroll.documentView = list
        listScroll.drawsBackground = false
        listScroll.hasVerticalScroller = true
        listScroll.autohidesScrollers = true
        listScroll.scrollerStyle = .overlay
        addSubview(listScroll)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func apply(_ face: StackFace) {
        let previous = self.face
        self.face = face
        if let note = face.topNote { preview.show(note) }
        previewClip.isHidden = face.topNote == nil
        emptyLabel.isHidden = face.topNote != nil
        badge.stringValue = "\(face.count)"
        fullLabel.isHidden = !face.desktopFull
        popButton.isEnabled = face.count > 0 && !face.desktopFull
        clarityButton.title = face.clarity ? "Clarity: On" : "Clarity: Off"
        clarityButton.contentTintColor = face.clarity ? .controlAccentColor : NSColor(white: 0.35, alpha: 1)
        if previous?.entries != face.entries { rebuildList(face.entries) }
        if !face.canFlip { hoveredEdge = nil }
        needsLayout = true
        needsDisplay = true
    }

    private func rebuildList(_ entries: [StackEntry]) {
        list.subviews.forEach { $0.removeFromSuperview() }
        for entry in entries {
            let row = ActionButton(title: entry.title, help: "Pop this card") { [send] in send(.pop(entry.id)) }
            row.font = .systemFont(ofSize: 12)
            row.alignment = .left
            row.lineBreakMode = .byTruncatingTail
            row.contentTintColor = EditorStyle.textColor
            list.addSubview(row)
        }
    }

    // MARK: Layout

    /// Everything but the edge bands lives inside this.
    private var content: NSRect {
        bounds.insetBy(dx: bounds.width * EdgeBands.fraction, dy: bounds.height * EdgeBands.fraction)
    }

    override func layout() {
        super.layout()
        let inner = content
        toolbar.frame = NSRect(x: inner.minX, y: inner.maxY - 20, width: inner.width, height: 20)
        let previewTop = toolbar.frame.minY - 6
        let badgeWidth = max(22, badge.fittingSize.width + 10)
        badge.frame = NSRect(x: inner.maxX - badgeWidth, y: previewTop - 22, width: badgeWidth, height: 17)
        previewClip.frame = NSRect(x: inner.minX - 4, y: previewTop - 100, width: inner.width + 4, height: 100)
        preview.frame = NSRect(x: 0, y: 0, width: previewClip.bounds.width, height: previewClip.bounds.height)
        emptyLabel.frame = NSRect(x: inner.minX, y: previewTop - 26, width: badge.frame.minX - inner.minX - 8, height: 22)
        fullLabel.frame = NSRect(x: inner.minX, y: previewClip.frame.minY - 17, width: inner.width, height: 15)
        let listTop = (fullLabel.isHidden ? previewClip.frame.minY : fullLabel.frame.minY) - 6
        listScroll.frame = NSRect(x: inner.minX - 4, y: inner.minY, width: inner.width + 8, height: max(0, listTop - inner.minY))
        let rowHeight: CGFloat = 20
        list.frame = NSRect(x: 0, y: 0, width: listScroll.contentSize.width,
                            height: max(listScroll.contentSize.height, CGFloat(list.subviews.count) * rowHeight))
        for (i, row) in list.subviews.enumerated() {
            row.frame = NSRect(x: 4, y: CGFloat(i) * rowHeight, width: list.bounds.width - 8, height: rowHeight)
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        // A second sheet peeking out underneath says "stack".
        let under = CardShape.path(in: bounds.offsetBy(dx: 2, dy: -2), lineWidth: 1)
        NSColor(white: 0.93, alpha: 1).setFill()
        under.fill()
        CardShape.border.setStroke()
        under.stroke()
        let shape = CardShape.path(in: bounds.offsetBy(dx: -1, dy: 1), lineWidth: 1)
        CardShape.fill.setFill()
        shape.fill()
        if let edge = hoveredEdge {
            let band = EdgeBands.rect(of: edge, in: bounds)
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            NSColor(white: 0, alpha: 0.05).setFill()
            band.fill()
            NSGraphicsContext.restoreGraphicsState()
            let chevron = NSAttributedString(string: edge.direction == .previous ? "‹" : "›", attributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: NSColor(white: 0, alpha: 0.4),
            ])
            let size = chevron.size()
            chevron.draw(at: NSPoint(x: band.midX - size.width / 2, y: band.midY - size.height / 2))
        }
        shape.stroke()
        for y in [toolbar.frame.minY - 3, previewClip.frame.minY - (fullLabel.isHidden ? 3 : 20)] {
            let separator = NSBezierPath()
            separator.move(to: NSPoint(x: content.minX, y: y))
            separator.line(to: NSPoint(x: content.maxX, y: y))
            NSColor(white: 0, alpha: 0.08).setStroke()
            separator.stroke()
        }
        window?.invalidateShadow()
    }

    // MARK: Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if let edge = edge(at: convert(event.locationInWindow, from: nil)) {
            send(.flipStack(edge.direction))
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        hoveredEdge = edge(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        hoveredEdge = nil
    }

    /// The bands are live only when there is a card under the top one to flip to.
    private func edge(at point: CGPoint) -> Edge? {
        guard face?.canFlip == true, !content.contains(point) else { return nil }
        return EdgeBands.edge(at: point, in: bounds)
    }
}

/// A document view that lays its rows out top-down.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Holds the read-only preview; clicks go through it to the stack.
private final class PassThroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
