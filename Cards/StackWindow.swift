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

/// Toolbar (New, Pop, Clarity), the top card's header with a count badge, "Desktop full" while
/// no slot is free, and a scrollable list of every stacked header (click one → pop that card).
private final class StackView: NSView {
    private let send: (Command) -> Void
    private let toolbar = NSStackView()
    private let popButton: ActionButton
    private let clarityButton: ActionButton
    private let topHeader = NSTextField(labelWithString: "")
    private let badge = NSTextField(labelWithString: "0")
    private let fullLabel = NSTextField(labelWithString: "Desktop full")
    private let listScroll = NSScrollView()
    private let list = FlippedView()
    private var face: StackFace?

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

        topHeader.font = .boldSystemFont(ofSize: 15)
        topHeader.textColor = EditorStyle.textColor
        topHeader.lineBreakMode = .byTruncatingTail
        addSubview(topHeader)

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
        topHeader.stringValue = face.top?.title ?? "Stack is empty"
        topHeader.textColor = face.top == nil ? .tertiaryLabelColor : EditorStyle.textColor
        badge.stringValue = "\(face.count)"
        fullLabel.isHidden = !face.desktopFull
        popButton.isEnabled = face.count > 0 && !face.desktopFull
        clarityButton.title = face.clarity ? "Clarity: On" : "Clarity: Off"
        clarityButton.contentTintColor = face.clarity ? .controlAccentColor : NSColor(white: 0.35, alpha: 1)
        if previous?.entries != face.entries { rebuildList(face.entries) }
        needsLayout = true
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
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let inner = bounds.insetBy(dx: 16, dy: 12)
        toolbar.frame = NSRect(x: inner.minX, y: inner.maxY - 20, width: inner.width, height: 20)
        let badgeWidth = max(22, badge.fittingSize.width + 10)
        badge.frame = NSRect(x: inner.maxX - badgeWidth, y: toolbar.frame.minY - 30, width: badgeWidth, height: 17)
        topHeader.frame = NSRect(x: inner.minX, y: toolbar.frame.minY - 33,
                                 width: badge.frame.minX - inner.minX - 8, height: 21)
        fullLabel.frame = NSRect(x: inner.minX, y: topHeader.frame.minY - 18, width: inner.width, height: 15)
        let listTop = (fullLabel.isHidden ? topHeader.frame.minY : fullLabel.frame.minY) - 6
        listScroll.frame = NSRect(x: inner.minX - 4, y: inner.minY, width: inner.width + 8, height: listTop - inner.minY)
        let rowHeight: CGFloat = 20
        list.frame = NSRect(x: 0, y: 0, width: listScroll.contentSize.width,
                            height: max(listScroll.contentSize.height, CGFloat(list.subviews.count) * rowHeight))
        for (i, row) in list.subviews.enumerated() {
            row.frame = NSRect(x: 4, y: CGFloat(i) * rowHeight, width: list.bounds.width - 8, height: rowHeight)
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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
        shape.stroke()
        let separator = NSBezierPath()
        let y = toolbar.frame.minY - 6
        separator.move(to: NSPoint(x: bounds.minX + 16, y: y))
        separator.line(to: NSPoint(x: bounds.maxX - 16, y: y))
        NSColor(white: 0, alpha: 0.08).setStroke()
        separator.stroke()
        window?.invalidateShadow()
    }
}

/// A document view that lays its rows out top-down.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
