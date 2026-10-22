import XCTest
@testable import Cards

final class LibraryTests: XCTestCase {
    private var folder: URL!
    private var cardFile: URL { folder.appending(path: "card.md") }

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appending(path: "CardsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        try? FileManager.default.removeItem(at: folder)
    }

    func testSaveRecreatesADeletedFolderWithEveryFile() async throws {
        let original = "# Groceries\n\n- eggs\n- milk\n"
        try Data(original.utf8).write(to: cardFile)
        let library = Library(folder: folder)
        var desk = library.load()
        desk.apply(.pop(nil))
        library.save(desk)
        try FileManager.default.removeItem(at: folder)

        library.save(desk)

        XCTAssertEqual(try? String(contentsOf: cardFile, encoding: .utf8), original,
                       "the card file is back, byte for byte")
        XCTAssertEqual(Library(folder: folder).load(), desk,
                       "the sidecar is back too: a fresh load puts the card in the same slot")
    }
}
