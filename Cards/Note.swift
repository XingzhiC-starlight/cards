import CryptoKit
import Foundation

// A card's content in domain form, its Markdown file format, and the typing rules for lists.
// Markdown is parsed here, at the file boundary; the editor's NSAttributedString form is
// converted in CardEditor.swift, at the editor boundary. Nothing else knows either format.

/// A card's content: the header plus body lines.
struct Note: Equatable {
    /// The first paragraph. Always shown as the bold H1 header and stored as `# header`;
    /// it never carries inline styling or a list kind ("regardless of formatting").
    var header: String
    var body: [Line]

    static let blank = Note(header: "", body: [])
}

/// One body paragraph.
struct Line: Equatable {
    var kind: LineKind
    /// Normalized on construction: no empty runs, no two neighbouring runs with the same style,
    /// and spaces at the edges of a styled run are plain (Markdown can't style them).
    /// Normalization is what makes `Note(markdown: note.markdown) == note` hold.
    private(set) var runs: [Run]

    init(kind: LineKind = .text, runs: [Run]) {
        self.kind = kind
        var pieces: [Run] = []
        for run in runs {
            guard !run.style.isEmpty else {
                pieces.append(run)
                continue
            }
            let leading = run.text.prefix(while: \.isWhitespace)
            let trailing = run.text.dropFirst(leading.count).reversed().prefix(while: \.isWhitespace)
            pieces.append(Run(text: String(leading)))
            pieces.append(Run(text: String(run.text.dropFirst(leading.count).dropLast(trailing.count)), style: run.style))
            pieces.append(Run(text: String(trailing.reversed())))
        }
        var merged: [Run] = []
        for run in pieces where !run.text.isEmpty {
            if let last = merged.last, last.style == run.style {
                merged[merged.count - 1].text += run.text
            } else {
                merged.append(run)
            }
        }
        self.runs = merged
    }

    var text: String { runs.map(\.text).joined() }
    var isBlank: Bool { text.allSatisfy(\.isWhitespace) }
}

/// The body formats that exist. The spec's whole list: plain, bullet, numbered, checkbox.
enum LineKind: Equatable {
    case text, bullet, numbered
    case todo(done: Bool)

    var isList: Bool { self != .text }
}

/// A span of text with one inline style.
struct Run: Equatable {
    var text: String
    var style: Style = []
}

/// Inline styles: bold and italic, nothing else.
struct Style: OptionSet, Hashable {
    let rawValue: Int
    static let bold = Style(rawValue: 1 << 0)
    static let italic = Style(rawValue: 1 << 1)
}

/// SHA-256 of a note's Markdown, hex. Stable across launches (unlike `Hasher`), so the sidecar can
/// say which version of a note a cached summary describes.
struct Digest: RawRepresentable, Hashable, Codable {
    let rawValue: String
}

extension Note {
    /// What lists and stack rows show for this card.
    var title: String {
        let trimmed = header.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    var digest: Digest {
        let hash = SHA256.hash(data: Data(markdown.utf8))
        return Digest(rawValue: hash.map { String(format: "%02x", $0) }.joined())
    }

    /// Summaries exist only for bodies with at least two non-blank lines (spec: "no summary for
    /// empty or one-line bodies").
    var wantsSummary: Bool { body.filter { !$0.isBlank }.count >= 2 }

    /// The single non-blank body line, shown instead of a summary when `wantsSummary` is false.
    var shortBody: String { body.first { !$0.isBlank }?.text ?? "" }

    /// Header and body as plain text, for the summary prompt.
    var plainText: String {
        ([header] + body.map { line in
            switch line.kind {
            case .text: line.text
            case .bullet, .numbered: "- " + line.text
            case .todo(let done): (done ? "[x] " : "[ ] ") + line.text
            }
        }).joined(separator: "\n")
    }

    /// Reads a card file. Never fails: anything outside the supported subset stays literal text.
    ///
    /// - Line 0 is the header; leading `#`s and one space are stripped.
    /// - One blank line right after the header is the separator `markdown` writes; it is skipped.
    /// - Every other line is one body line:
    ///   `- [ ] x` / `- [x] x` → todo, `- x` or `* x` → bullet, `12. x` → numbered, else text.
    /// - Inline: `***x***` bold+italic, `**x**` bold, `*x*` italic, `\x` literal x.
    init(markdown: String) {
        // `isNewline` also splits "\r\n", which Swift treats as one character.
        var lines = markdown.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        if lines.count > 1, lines.last == "" { lines.removeLast() }   // the file's final newline

        var headerLine = Substring(lines.first ?? "")
        if headerLine.hasPrefix("#") {
            headerLine = headerLine.drop { $0 == "#" }
            if headerLine.hasPrefix(" ") { headerLine = headerLine.dropFirst() }
        }
        header = Note.parseInline(headerLine).map(\.text).joined()

        var rest = lines.dropFirst()
        if rest.first == "" { rest = rest.dropFirst() }
        body = rest.map { line in
            let (kind, content) = Note.lineKind(of: Substring(line))
            return Line(kind: kind, runs: Note.parseInline(content))
        }
    }

    /// Writes a card file: `# header`, a blank line, then one Markdown line per body line.
    /// Inverse of `init(markdown:)` for every note the editor can produce.
    var markdown: String {
        let numbers = listNumbers(body.map(\.kind))
        var out = ["# " + Note.escape(header)]
        if !body.isEmpty { out.append("") }
        for (line, number) in zip(body, numbers) {
            let content = line.runs.map { Note.renderInline($0) }.joined()
            switch line.kind {
            case .text: out.append(Note.escapeLineStart(content))
            case .bullet:
                let readsAsCheckbox = Note.checkboxes.contains { content.hasPrefix($0.marker) }
                out.append("- " + (readsAsCheckbox ? "\\" : "") + content)
            case .numbered: out.append("\(number ?? 1). " + content)
            case .todo(let done): out.append((done ? "- [x] " : "- [ ] ") + content)
            }
        }
        return out.joined(separator: "\n") + "\n"
    }

    // MARK: Line prefixes

    private static let checkboxes: [(marker: String, done: Bool)] = [("[ ] ", false), ("[x] ", true), ("[X] ", true)]

    private static func lineKind(of line: Substring) -> (LineKind, Substring) {
        let todos = checkboxes.map { ("- " + $0.marker, LineKind.todo(done: $0.done)) }
        for (prefix, kind) in todos + [("- ", .bullet), ("* ", .bullet)] where line.hasPrefix(prefix) {
            return (kind, line.dropFirst(prefix.count))
        }
        let digits = line.prefix { $0.isASCII && $0.isNumber }
        if !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". ") {
            return (.numbered, line.dropFirst(digits.count + 2))
        }
        return (.text, line)
    }

    /// A plain line that happens to start like Markdown syntax gets its first character escaped,
    /// so it reads back as plain text here and in other Markdown readers.
    private static func escapeLineStart(_ content: String) -> String {
        let (kind, _) = lineKind(of: Substring(content))
        if kind != .text || content.hasPrefix("#") || content.hasPrefix(">") {
            return "\\" + content
        }
        return content
    }

    // MARK: Inline

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "*", with: "\\*")
    }

    /// One run as Markdown. Spaces at the edges go outside the markers, where Markdown wants them.
    private static func renderInline(_ run: Run) -> String {
        let marker = switch (run.style.contains(.bold), run.style.contains(.italic)) {
        case (true, true): "***"
        case (true, false): "**"
        case (false, true): "*"
        case (false, false): ""
        }
        let text = escape(run.text)
        let leading = text.prefix(while: \.isWhitespace)
        guard !marker.isEmpty, leading.count < text.count else { return text }
        let trailing = text.reversed().prefix(while: \.isWhitespace)
        let core = text.dropFirst(leading.count).dropLast(trailing.count)
        return leading + marker + core + marker + String(trailing.reversed())
    }

    /// Scans one line. `\x` is a literal x. A run of asterisks first closes the styles that are
    /// open, then opens new ones, but only when a closing asterisk follows later on the line;
    /// otherwise the asterisks stay literal.
    static func parseInline(_ text: Substring) -> [Run] {
        let chars = Array(text)
        var runs: [Run] = []
        var current = ""
        var style: Style = []
        var i = 0

        func flush() {
            if !current.isEmpty { runs.append(Run(text: current, style: style)) }
            current = ""
        }
        func asterisksAhead(from index: Int) -> Int {
            var count = 0
            var j = index
            while j < chars.count {
                if chars[j] == "\\" { j += 2; continue }
                if chars[j] == "*" { count += 1 }
                j += 1
            }
            return count
        }

        while i < chars.count {
            let c = chars[i]
            if c == "\\", i + 1 < chars.count {
                current.append(chars[i + 1])
                i += 2
                continue
            }
            guard c == "*" else {
                current.append(c)
                i += 1
                continue
            }
            var n = 0
            while i + n < chars.count, chars[i + n] == "*" { n += 1 }
            let ahead = asterisksAhead(from: i + n)
            var next = style
            var left = n
            if next.contains(.bold), left >= 2 { next.remove(.bold); left -= 2 }
            if next.contains(.italic), left >= 1 { next.remove(.italic); left -= 1 }
            if !next.contains(.bold), left >= 2, ahead >= 2 { next.insert(.bold); left -= 2 }
            if !next.contains(.italic), left >= 1, ahead >= 1 { next.insert(.italic); left -= 1 }
            if next != style {
                flush()
                style = next
            }
            current += String(repeating: "*", count: left)
            i += n
        }
        flush()
        return Line(runs: runs).runs
    }
}

/// Display numbers for runs of `.numbered` lines: 1, 2, 3… restarting after any other kind.
/// The Markdown writer and the editor's marker drawing both use this, so the file and the
/// screen can't disagree.
func listNumbers(_ kinds: [LineKind]) -> [Int?] {
    var n = 0
    return kinds.map { kind in
        guard kind == .numbered else {
            n = 0
            return nil
        }
        n += 1
        return n
    }
}

/// The list rules the editor applies while typing, as pure decisions.
enum Typing {
    /// Typing a space after one of these at the very start of a body line starts a list:
    /// `-` bullet, `1.` (any number) numbered, `[]` or `[ ]` checkbox.
    static func listKind(forPrefix prefix: String) -> LineKind? {
        switch prefix {
        case "-", "*": return .bullet
        case "[]", "[ ]": return .todo(done: false)
        default:
            let digits = prefix.dropLast()
            if prefix.hasSuffix("."), !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) {
                return .numbered
            }
            return nil
        }
    }

    enum Return: Equatable {
        /// Insert a line break; the new line gets this kind.
        case newLine(LineKind)
        /// Insert nothing; the current (empty) item turns into plain text.
        case endList
    }

    /// Enter continues a list (a new checkbox starts unchecked) and ends it on an empty item.
    /// Enter in the header or a plain line starts a plain line.
    static func onReturn(kind: LineKind, isEmpty: Bool, isHeader: Bool) -> Return {
        if isHeader || !kind.isList { return .newLine(.text) }
        if isEmpty { return .endList }
        if case .todo = kind { return .newLine(.todo(done: false)) }
        return .newLine(kind)
    }
}
