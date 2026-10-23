// cards-clip: the general pasteboard for copy and paste checks, so a run can set what a paste
// reads, show what a copy wrote, and leave the owner's clipboard exactly as it found it.
// Built by `cards-verify build`; `cards-verify clip` calls it.
//
//   cards-clip save FILE          every item and type on the clipboard, into FILE (mode 600)
//   cards-clip restore FILE       put FILE back on the clipboard, then delete FILE
//   cards-clip set TEXT [HTML]    the clipboard holds TEXT as plain text, and HTML as public.html
//   cards-clip show               the clipboard's types, then its plain text and HTML
import AppKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("cards-clip: \(message)\n".utf8))
    exit(1)
}

let args = Array(CommandLine.arguments.dropFirst())
let board = NSPasteboard.general

switch args.first {
case "save":
    guard args.count == 2 else { fail("save FILE") }
    // Each item is its types in order, so a restore writes them back in the same order.
    let items: [[[String: Any]]] = (board.pasteboardItems ?? []).map { item in
        item.types.compactMap { type in item.data(forType: type).map { ["type": type.rawValue, "data": $0] } }
    }
    do {
        let data = try PropertyListSerialization.data(fromPropertyList: items, format: .binary, options: 0)
        FileManager.default.createFile(atPath: args[1], contents: data, attributes: [.posixPermissions: 0o600])
    } catch {
        fail("could not save the clipboard: \(error)")
    }
    print("saved \(items.count) clipboard item(s)")

case "restore":
    guard args.count == 2 else { fail("restore FILE") }
    guard let data = FileManager.default.contents(atPath: args[1]),
          let items = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [[[String: Any]]]
    else { fail("no saved clipboard at \(args[1])") }
    board.clearContents()
    let restored = items.map { entries in
        let item = NSPasteboardItem()
        for entry in entries {
            guard let type = entry["type"] as? String, let value = entry["data"] as? Data else { continue }
            item.setData(value, forType: NSPasteboard.PasteboardType(type))
        }
        return item
    }
    if !restored.isEmpty, !board.writeObjects(restored) { fail("could not write the saved clipboard back; it is still in \(args[1])") }
    try? FileManager.default.removeItem(atPath: args[1])
    print("restored \(items.count) clipboard item(s)")

case "set":
    guard args.count == 2 || args.count == 3 else { fail("set TEXT [HTML]") }
    board.clearContents()
    board.declareTypes(args.count == 3 ? [.html, .string] : [.string], owner: nil)
    if args.count == 3 { board.setString(args[2], forType: .html) }
    board.setString(args[1], forType: .string)

case "show":
    print("types: " + (board.types ?? []).map(\.rawValue).joined(separator: " "))
    for type in [NSPasteboard.PasteboardType.string, .html] {
        guard let text = board.string(forType: type) else { continue }
        print("--- \(type.rawValue)")
        print(text)
    }

default:
    fail("usage: cards-clip save FILE | restore FILE | set TEXT [HTML] | show")
}
