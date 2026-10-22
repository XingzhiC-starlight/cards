import XCTest
@testable import Cards

/// The stack's ribbon and count badge, laid out in a window that is never shown.
final class StackLayoutTests: XCTestCase {
    /// The cell width a 1512-point screen gives, and a 1366-point one.
    private let wide: CGFloat = 302.4
    private let narrow: CGFloat = 273

    private struct Stack {
        let window: StackWindow
        let toggled: () -> Int

        var view: NSView { window.contentView! }
        func control(_ tooltip: String) -> NSView {
            view.subviews.first { $0.toolTip == tooltip }!
        }
        var toggle: NSView { view.subviews.first { $0.toolTip == "Hide all" || $0.toolTip == "Show all" }! }
        var menu: NSView { control("Settings and quit") }
        var badge: NSView { control("Cards in the stack") }
        var toolbar: NSView { view.subviews.first { $0 is NSStackView }! }
        var desktopFull: NSView { view.subviews.first { ($0 as? NSTextField)?.stringValue == "Desktop full" }! }
    }

    private func stack(width: CGFloat, _ visibility: Visibility = .all, full: Bool = false) -> Stack {
        var toggles = 0
        let window = StackWindow(send: { _ in }, menu: { NSMenu() }, toggleHidden: { toggles += 1 },
                                 drag: WindowDrag(moved: { _ in }, dropped: { _ in }))
        let card = CardFace(id: CardID(rawValue: "a"), note: Note(header: "Title", body: []), collapsed: false,
                            summary: .body(""))
        let face = StackFace(count: 12, selected: card, clarity: false, desktopFull: full)
        window.apply(face, cell: CGRect(x: 0, y: 0, width: width, height: (width * 0.78).rounded()), visibility: visibility)
        window.contentView!.layoutSubtreeIfNeeded()
        return Stack(window: window, toggled: { toggles })
    }

    func testTheToggleOffersHideAllWhileCardsShowAndShowAllWhileHidden() throws {
        let shown = stack(width: wide)
        XCTAssertEqual(shown.toggle.toolTip, "Hide all", "with cards showing it hides them")
        let hidden = stack(width: wide, .hideAll)
        XCTAssertEqual(hidden.toggle.toolTip, "Show all", "under Hide all it shows them again")
        try XCTUnwrap(hidden.toggle as? NSButton).performClick(nil)
        XCTAssertEqual(hidden.toggled(), 1, "one click toggles")
    }

    func testTheBadgeIsInTheCardsBottomRightUnlessHideAllRemovedTheCard() {
        let shown = stack(width: wide)
        XCTAssertGreaterThan(shown.badge.frame.midX, shown.view.bounds.midX, "on the right")
        XCTAssertLessThan(shown.badge.frame.maxY, shown.toggle.frame.minY, "below the ribbon, in the card area")
        XCTAssertLessThan(shown.badge.frame.minY, shown.view.bounds.height * 0.2, "near the bottom")
        let hidden = stack(width: wide, .hideAll)
        XCTAssertEqual(hidden.badge.frame.midY, hidden.toggle.frame.midY, accuracy: 2, "in the ribbon")
        XCTAssertLessThanOrEqual(hidden.badge.frame.maxX, hidden.toggle.frame.minX, "left of the toggle")
    }

    func testTheBadgeLeavesAPressOnItToWhatIsUnderIt() {
        for visibility in [Visibility.all, .hideAll] {
            let stack = stack(width: wide, visibility)
            let center = stack.view.convert(CGPoint(x: stack.badge.frame.midX, y: stack.badge.frame.midY), to: stack.view.superview)
            let hit = stack.view.hitTest(center)
            XCTAssertFalse(hit is NSTextField, "the count never takes the click")
            if visibility == .hideAll {
                XCTAssertTrue(hit === stack.view, "in the ribbon the press drags the stack")
            }
        }
    }

    func testTheBadgeClearsTheFormattingBarsButtons() throws {
        for width in [wide, narrow] {
            let stack = stack(width: width)
            let cardView = try XCTUnwrap(stack.view.subviews.first { String(describing: type(of: $0)) == "CardView" })
            let bar = try XCTUnwrap(cardView.subviews.first { $0 is FormatBar } as? FormatBar)
            bar.layoutSubtreeIfNeeded()
            let buttonsEnd = bar.arrangedSubviews.map { stack.view.convert($0.frame, from: bar).maxX }.max()!
            XCTAssertLessThan(buttonsEnd, stack.badge.frame.minX, "at width \(width)")
        }
    }

    func testDesktopFullTruncatesBeforeAnyButtonMoves() {
        for visibility in [Visibility.all, .hideAll] {
            let without = stack(width: wide, visibility)
            let with = stack(width: wide, visibility, full: true)
            XCTAssertEqual(with.toggle.frame, without.toggle.frame, "the toggle stays put")
            XCTAssertEqual(with.menu.frame, without.menu.frame, "and so does the menu button")
            XCTAssertEqual(with.toolbar.frame, without.toolbar.frame, "and the toolbar")
            let label = with.desktopFull.frame
            let rightEdge = visibility == .all ? with.toggle.frame.minX : with.badge.frame.minX
            XCTAssertGreaterThanOrEqual(label.minX, with.toolbar.frame.maxX, "the label stays right of the toolbar")
            XCTAssertLessThanOrEqual(label.maxX, rightEdge, "and left of what is at its right")
        }
    }

    func testTheRibbonOnlyBadgeGivesWayRatherThanCoverTheToolbar() {
        let wideRibbon = stack(width: wide, .hideAll)
        XCTAssertFalse(wideRibbon.badge.isHidden, "with room the count shows beside the toggle")
        let narrowRibbon = stack(width: 256, .hideAll)
        XCTAssertTrue(narrowRibbon.badge.isHidden, "without room it goes instead of covering the Clarity button")
        XCTAssertGreaterThan(narrowRibbon.toggle.frame.minX, narrowRibbon.toolbar.frame.maxX, "and the buttons stay apart")
    }
}
