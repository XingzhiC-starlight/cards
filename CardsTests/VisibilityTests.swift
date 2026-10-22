import XCTest
@testable import Cards

final class VisibilityTests: XCTestCase {
    private func id(_ name: String) -> CardID { CardID(rawValue: name) }

    func testEverythingShowsUntilHideAll() {
        let visibility = Visibility.all
        XCTAssertTrue(visibility.shows(id("a")), "a popped card shows")
        XCTAssertTrue(visibility.showsStackCard, "and so does the stack's card area")
        XCTAssertFalse(visibility.isHidden, "nothing is hidden")
    }

    func testHideAllHidesEveryPoppedCardAndTheStackCardArea() {
        let visibility = Visibility.hideAll
        XCTAssertFalse(visibility.shows(id("a")), "a popped card is hidden")
        XCTAssertFalse(visibility.showsStackCard, "so is the stack's card area")
        XCTAssertTrue(visibility.isHidden, "the state says so")
    }

    func testRevealingACardShowsOnlyThatCard() {
        var visibility = Visibility.hideAll
        visibility.reveal(id("a"))
        XCTAssertTrue(visibility.shows(id("a")), "the revealed card shows")
        XCTAssertFalse(visibility.shows(id("b")), "the others stay hidden")
        XCTAssertFalse(visibility.showsStackCard, "and so does the stack's card area")
    }

    func testRevealingTheStackCardShowsOnlyIt() {
        var visibility = Visibility.hideAll
        visibility.revealStackCard()
        XCTAssertTrue(visibility.showsStackCard, "the stack's card area shows")
        XCTAssertFalse(visibility.shows(id("a")), "popped cards stay hidden")
    }

    func testHidingAllAgainForgetsWhatWasRevealed() {
        var visibility = Visibility.hideAll
        visibility.reveal(id("a"))
        visibility.revealStackCard()
        visibility = .hideAll
        XCTAssertFalse(visibility.shows(id("a")), "Hide all hides the revealed card again")
        XCTAssertFalse(visibility.showsStackCard, "and the stack's card area")
    }

    func testRevealingWhileEverythingShowsChangesNothing() {
        var visibility = Visibility.all
        visibility.reveal(id("a"))
        visibility.revealStackCard()
        XCTAssertEqual(visibility, .all, "there is nothing to reveal")
    }

    func testANewCardWhileHiddenTakesTheSlotItWouldHaveTakenWithEverythingShown() {
        var desk = Desk(notes: [:], saved: SavedDesk())
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let first = desk.apply(.new(at: now))!
        var visibility = Visibility.hideAll
        let second = desk.apply(.new(at: now.addingTimeInterval(1)))!
        visibility.reveal(second)
        XCTAssertEqual(desk.place(of: .card(second)), .slot(Slot(index: 2)!), "it goes after the hidden card's slot")
        XCTAssertTrue(visibility.shows(second), "the new card shows")
        XCTAssertFalse(visibility.shows(first), "the hidden one does not")
    }

    func testTheRibbonOnlyWindowIsTheTopOfTheStacksCell() {
        let cell = CGRect(x: 0, y: 700, width: 302, height: 237)
        let frame = StackWindow.ribbonOnlyFrame(in: cell)
        XCTAssertEqual(frame.minX, cell.minX, "same left edge")
        XCTAssertEqual(frame.width, cell.width, "same width")
        XCTAssertEqual(frame.maxY, cell.maxY, "same top edge")
        XCTAssertLessThan(frame.height, cell.height / 2, "much shorter than the cell")
        XCTAssertGreaterThan(frame.height, 40, "yet taller than the ribbon, for the gap around it")
    }
}
