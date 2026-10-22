import XCTest
@testable import Cards

final class PlacementTests: XCTestCase {
    private func id(_ name: String) -> CardID { CardID(rawValue: name) }

    private func slot(_ index: Int) -> Place { .slot(Slot(index: index)!) }

    /// The stack top-left and each name popped into the slot given.
    private func desk(_ popped: [String: Int], stack: [String] = []) -> Desk {
        let names = Array(popped.keys) + stack
        return Desk(notes: Dictionary(uniqueKeysWithValues: names.map { (id($0), Note(header: $0, body: [])) }),
                    saved: SavedDesk(placements: popped.sorted { $0.value < $1.value }
                                        .map { SavedPlacement(slot: $0.value, card: id($0.key)) },
                                     stack: stack.map(id)))
    }

    // MARK: The snap rule

    func testADropNearASlotsCenterSnapsAndOneFurtherAwayStaysFree() {
        let center = Slot(index: 7)!.center
        let near = GridPoint(x: center.x + 0.1 / 5, y: center.y)        // 10 % of a cell to the right
        let far = GridPoint(x: center.x + 0.2 / 5, y: center.y)         // 20 %
        XCTAssertEqual(Place.dropped(at: near), slot(7), "within 15 % of a cell it snaps")
        XCTAssertEqual(Place.dropped(at: far), .free(far), "beyond it, it stays exactly where it was dropped")
        XCTAssertEqual(Place.guide(at: near).snaps, true, "and the guide says so beforehand")
        XCTAssertEqual(Place.guide(at: far).slot, Slot(index: 7), "the guide outlines the nearest slot either way")
        XCTAssertEqual(Place.guide(at: far).snaps, false, "but promises no snap")
    }

    func testADropPastTheEdgeSlidesBackOnScreen() {
        let dropped = Place.dropped(at: GridPoint(x: 2, y: 0.3))
        XCTAssertEqual(dropped, .free(GridPoint(x: 0.9, y: 0.3)), "half a card from the right edge, same height")
        let grid = Grid(area: CGRect(x: 0, y: 0, width: 1500, height: 1000))
        XCTAssertTrue(grid.area.contains(grid.frame(of: dropped)), "so the whole card is on screen")
        XCTAssertEqual(GridPoint(x: -1, y: .nan), GridPoint(x: 0.1, y: 0.5), "any point is clamped, even nonsense")
    }

    func testAFreeCardsFrameIsACellCenteredOnItsPoint() {
        let grid = Grid(area: CGRect(x: 0, y: 0, width: 1500, height: 1000))
        let frame = grid.frame(of: .free(GridPoint(x: 0.5, y: 0.5)))
        XCTAssertEqual(frame, CGRect(x: 600, y: 375, width: 300, height: 250), "one cell in size, centered")
        XCTAssertEqual(grid.point(at: CGPoint(x: frame.midX, y: frame.midY)), GridPoint(x: 0.5, y: 0.5),
                       "and its center reads back as the same point")
        XCTAssertEqual(grid.frame(of: slot(0)).maxY, 1000, "slot 0 is the top-left cell")
    }

    // MARK: Moving

    func testAFreeCardTakesTheSlotItCoversMostForPop() {
        var desk = desk(["a": 1], stack: ["b"])
        desk.apply(.move(.card(id("a")), to: .free(GridPoint(x: 0.6, y: 0.4))))   // mostly over slot 8
        XCTAssertEqual(desk.firstFreeSlot, Slot(index: 1), "its old slot is free again")
        desk.apply(.move(.card(id("a")), to: .free(GridPoint(x: 0.33, y: 0.1))))  // mostly over slot 1, not snapped
        XCTAssertEqual(desk.apply(.pop), id("b"))
        XCTAssertEqual(desk.place(of: .card(id("b"))), slot(2), "pop skips the slot the free card covers")
    }

    func testSnappingOntoACardSendsItToTheMoversExactFreeSpot() {
        var desk = desk(["a": 1, "b": 2])
        let spot = GridPoint(x: 0.47, y: 0.71)
        desk.apply(.move(.card(id("a")), to: .free(spot)))
        desk.apply(.move(.card(id("a")), to: slot(2)))
        XCTAssertEqual(desk.place(of: .card(id("a"))), slot(2), "the dragged card takes the slot")
        XCTAssertEqual(desk.place(of: .card(id("b"))), .free(spot), "the occupant goes where it came from")
    }

    func testSnappingOntoACardSwapsSlots() {
        var desk = desk(["a": 1, "b": 2])
        desk.apply(.move(.card(id("a")), to: slot(2)))
        XCTAssertEqual(desk.place(of: .card(id("b"))), slot(1), "slot for slot, as before")
    }

    func testSnappingOntoASlotAFreeCardCoversLeavesTheFreeCardPut() {
        let spot = GridPoint(x: 0.75, y: 0.1)   // over slot 3
        var desk = desk(["a": 1, "b": 2])
        desk.apply(.move(.card(id("a")), to: .free(spot)))
        desk.apply(.move(.card(id("b")), to: slot(3)))
        XCTAssertEqual(desk.place(of: .card(id("b"))), slot(3), "the dragged card snaps")
        XCTAssertEqual(desk.place(of: .card(id("a"))), .free(spot), "and the free card overlapping it stays")
    }

    func testMovingTheStackFreesItsSlotForPop() {
        var desk = desk([:], stack: ["a"])
        desk.apply(.move(.stack, to: slot(7)))
        XCTAssertEqual(desk.stackPlace, slot(7), "the stack moved")
        desk.apply(.pop)
        XCTAssertEqual(desk.place(of: .card(id("a"))), slot(0), "and the top-left slot is a card slot now")
    }

    func testSnappingACardOntoTheStackSwapsThem() {
        var desk = desk(["a": 1])
        desk.apply(.move(.card(id("a")), to: slot(0)))
        XCTAssertEqual(desk.place(of: .card(id("a"))), slot(0), "the card takes the stack's slot")
        XCTAssertEqual(desk.stackPlace, slot(1), "and the stack takes the card's")
    }

    func testPilingFreeCardsStillStopsAtNineteen() {
        var desk = Desk(notes: [:], saved: SavedDesk())
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        for n in 0..<19 {
            let card = desk.apply(.new(at: now.addingTimeInterval(Double(n))))!
            desk.apply(.move(.card(card), to: .free(GridPoint(x: 0.5, y: 0.5))))
        }
        XCTAssertNil(desk.firstFreeSlot, "slots are left, but 19 cards are on the desktop")
        XCTAssertNil(desk.apply(.new(at: now)), "so New is refused")
    }

    func testReturningAFreeCardForgetsWhereItWas() {
        var desk = desk(["a": 1])
        desk.apply(.move(.card(id("a")), to: .free(GridPoint(x: 0.5, y: 0.5))))
        desk.apply(.returnToStack(id("a")))
        desk.apply(.pop)
        XCTAssertEqual(desk.place(of: .card(id("a"))), slot(1), "a later pop takes the first free slot")
    }

    // MARK: The sidecar

    func testFreePlacesAndTheStacksPlaceSurviveSavingAndLoading() throws {
        var desk = desk(["a": 1, "b": 2], stack: ["c"])
        desk.apply(.move(.card(id("a")), to: .free(GridPoint(x: 0.31, y: 0.62))))
        desk.apply(.move(.stack, to: .free(GridPoint(x: 0.8, y: 0.2))))
        let json = try JSONEncoder().encode(desk.saved)
        let saved = try JSONDecoder().decode(SavedDesk.self, from: json)
        let notes = Dictionary(uniqueKeysWithValues: desk.allCards.map { ($0.id, $0.note) })
        XCTAssertEqual(Desk(notes: notes, saved: saved), desk, "every place comes back exactly")
    }

    func testAVersionOneSidecarKeepsEveryCardInTheSameCell() throws {
        let json = #"{"version":1,"clarity":false,"placements":[{"slot":0,"card":"a"},{"slot":18,"card":"b"}],"stack":[],"collapsed":[],"summaries":[]}"#
        let saved = try JSONDecoder().decode(SavedDesk.self, from: Data(json.utf8))
        let desk = Desk(notes: [id("a"): Note(header: "a", body: []), id("b"): Note(header: "b", body: [])], saved: saved)
        XCTAssertEqual(desk.stackPlace, slot(0), "the stack stays top-left")
        XCTAssertEqual(desk.place(of: .card(id("a"))), slot(1), "old slot 0 was the cell right of the stack")
        XCTAssertEqual(desk.place(of: .card(id("b"))), slot(19), "old slot 18 was the bottom-right cell")
        XCTAssertEqual(desk.saved.version, 2, "and the next save writes the new version")
    }

    func testASidecarCardInTheStacksSlotJoinsTheStack() {
        let saved = SavedDesk(stackSlot: 4, placements: [SavedPlacement(slot: 4, card: id("a"))])
        let desk = Desk(notes: [id("a"): Note(header: "a", body: [])], saved: saved)
        XCTAssertEqual(desk.stackPlace, slot(4), "the stack keeps its slot")
        XCTAssertEqual(desk.stack.map(\.id), [id("a")], "the card that claimed it goes to the stack")
    }
}
