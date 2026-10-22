import XCTest
@testable import Cards

final class NoteTests: XCTestCase {
    func testBulletStartingLikeACheckboxStaysABullet() {
        for marker in ["[ ] ", "[x] ", "[X] "] {
            let note = Note(header: "Shopping", body: [Line(kind: .bullet, runs: [Run(text: marker + "milk")])])
            XCTAssertEqual(Note(markdown: note.markdown), note,
                           "a bullet whose text starts with \"\(marker)\" reads back as the same bullet")
        }
    }

    func testEditorNoteRoundTripsExactly() {
        let note = Note(header: "Groceries *not* a style", body: [
            Line(runs: [Run(text: "milk "), Run(text: "now", style: .bold), Run(text: " and "),
                        Run(text: "later", style: [.bold, .italic])]),
            Line(kind: .bullet, runs: [Run(text: "eggs")]),
            Line(kind: .numbered, runs: [Run(text: "first")]),
            Line(kind: .numbered, runs: [Run(text: "second")]),
            Line(kind: .todo(done: true), runs: [Run(text: "done *literal* stars")]),
            Line(runs: [Run(text: "- not a bullet")]),
            Line(runs: [Run(text: "3. not numbered")]),
            Line(runs: [Run(text: "")]),
            Line(runs: [Run(text: "back\\slash")]),
        ])
        XCTAssertEqual(Note(markdown: note.markdown), note, "every line kind, style and literal marker survives a save and load")
    }

    func testBlankNoteRoundTrips() {
        XCTAssertEqual(Note(markdown: Note.blank.markdown), Note.blank, "a new card reads back as a new card")
    }

    func testSummaryIsWantedFromTwoParagraphsOn() {
        let one = Note(header: "h", body: [Line(runs: [Run(text: String(repeating: "word ", count: 200))])])
        let two = Note(header: "h", body: [Line(runs: [Run(text: "first")]), Line(runs: [Run(text: "second")])])
        XCTAssertFalse(one.wantsSummary, "one long paragraph is a one-line body")
        XCTAssertTrue(two.wantsSummary, "two paragraphs are enough")
    }
}
