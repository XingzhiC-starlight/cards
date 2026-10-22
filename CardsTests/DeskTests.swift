import XCTest
@testable import Cards

final class DeskTests: XCTestCase {
    private func id(_ name: String) -> CardID { CardID(rawValue: name) }

    private func note(_ header: String) -> Note { Note(header: header, body: []) }

    private func notes(_ names: [String]) -> [CardID: Note] {
        Dictionary(uniqueKeysWithValues: names.map { (id($0), note($0)) })
    }

    private func deskWithStack(_ names: String...) -> Desk {
        Desk(notes: notes(names), saved: SavedDesk(stack: names.map(id)))
    }

    private func stackOrder(_ desk: Desk) -> [String] { desk.stack.map(\.id.rawValue) }

    func testFlippingNextThenPreviousRestoresTheStack() {
        var desk = deskWithStack("a", "b", "c")
        desk.apply(.flipStack(.next))
        XCTAssertEqual(stackOrder(desk), ["b", "c", "a"], "next sends the top card to the bottom")
        desk.apply(.flipStack(.previous))
        XCTAssertEqual(stackOrder(desk), ["a", "b", "c"], "previous brings it back")
    }

    func testPopTakesTheCardTheStackShows() {
        var desk = deskWithStack("a", "b", "c")
        desk.apply(.flipStack(.next))
        let popped = desk.apply(.pop(nil))
        XCTAssertEqual(popped, id("b"), "after one flip the second card is the one shown, and it pops")
        XCTAssertEqual(popped.flatMap { desk.slot(of: $0) }?.index, 0, "it lands in the first slot")
        XCTAssertEqual(stackOrder(desk), ["c", "a"], "the rest keep their order")
    }

    func testClarityCollapsesPoppedCardsOnly() {
        var desk = deskWithStack("a", "b")
        desk.apply(.pop(nil))
        desk.apply(.toggleClarity)
        XCTAssertTrue(desk.clarity, "the global flag is on")
        XCTAssertEqual(desk.poppedCards.count, 1, "one card is on the desktop")
        XCTAssertTrue(desk.poppedCards.allSatisfy(\.collapsed), "popped cards collapse")
        XCTAssertTrue(desk.stack.allSatisfy { !$0.collapsed }, "stacked cards do not")
    }

    func testExpandingOneCardLeavesClarityOn() {
        var desk = deskWithStack("a", "b")
        let popped = desk.apply(.pop(nil))
        desk.apply(.toggleClarity)
        desk.apply(.setCollapsed(popped!, false))
        XCTAssertTrue(desk.clarity, "the global flag stays on")
        XCTAssertFalse(desk.poppedCards[0].collapsed, "the card itself is expanded")
    }

    func testNewIsRefusedOnceAllNineteenSlotsAreFull() {
        var desk = Desk(notes: [:], saved: SavedDesk())
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        for n in 1...19 {
            let arrived = desk.apply(.new(at: now))
            XCTAssertNotNil(arrived, "card \(n) of 19 gets a slot")
        }
        XCTAssertNil(desk.apply(.new(at: now)), "the 20th card is refused")
        XCTAssertEqual(desk.allCards.count, 19, "and is not created")
    }

    func testRebuildDropsMissingFilesAndAppendsUnknownFilesInIdOrder() {
        let saved = SavedDesk(
            placements: [SavedPlacement(slot: 0, card: id("ghost")), SavedPlacement(slot: 1, card: id("a"))],
            stack: [id("gone"), id("c")])
        let desk = Desk(notes: notes(["a", "b", "c", "d"]), saved: saved)
        XCTAssertNil(desk.slot(of: id("ghost")), "a placement whose file is missing is dropped")
        XCTAssertEqual(desk.slot(of: id("a"))?.index, 1, "a placement whose file exists is kept")
        XCTAssertEqual(stackOrder(desk), ["c", "b", "d"],
                       "a stack entry whose file is missing is dropped; files the sidecar never heard of go last, by id")
    }

    func testSummaryForAnEditedNoteIsDropped() {
        var desk = deskWithStack("a")
        let before = note("a")
        let after = Note(header: "a", body: [Line(runs: [Run(text: "more")])])
        desk.apply(.edit(id("a"), after))
        desk.apply(.storeSummary(id("a"), Summary(source: before.digest, outcome: .text("old"))))
        XCTAssertNil(desk.allCards[0].summary, "a summary of the note as it was before the edit is dropped")
        desk.apply(.storeSummary(id("a"), Summary(source: after.digest, outcome: .text("new"))))
        XCTAssertEqual(desk.allCards[0].summary?.outcome, .text("new"), "a summary of the current note is kept")
    }
}
