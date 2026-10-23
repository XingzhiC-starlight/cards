import AppKit

// The card editor: one NSTextView (TextKit 1) whose first paragraph is the header.
//
// Representation. The text storage holds exactly the note's text: the header paragraph, then one
// paragraph per body line, separated by "\n". List markers are not characters. A body
// paragraph's kind is the `.cardLine` attribute over its whole range, and `CardTextView` draws
// "•", "1." or a checkbox in the paragraph's indent. So the user can never half-delete a marker,
// numbering can't go stale, and `Note(attributedText:)` is a plain walk over paragraphs.
// Inline bold/italic are font traits. The header's look is re-imposed after every change.
//
// An empty last paragraph has no characters to hold an attribute, so while the caret is in it,
// its kind lives in the typing attributes.

extension NSAttributedString.Key {
    /// Paragraph-level `LineKind.attributeValue` of a body paragraph. Absent means plain text.
    static let cardLine = NSAttributedString.Key("cards.line")
}

extension LineKind {
    /// Plist-friendly value for `.cardLine`, so undo carries it.
    var attributeValue: String {
        switch self {
        case .text: "text"
        case .bullet: "bullet"
        case .numbered: "numbered"
        case .todo(let done): done ? "done" : "todo"
        }
    }

    init(attributeValue: Any?) {
        self = switch attributeValue as? String {
        case "bullet": .bullet
        case "numbered": .numbered
        case "todo": .todo(done: false)
        case "done": .todo(done: true)
        default: .text
        }
    }
}

/// Fonts and paragraph styles, in one place.
enum EditorStyle {
    static let header = NSFont.boldSystemFont(ofSize: 17)
    static let body = NSFont.systemFont(ofSize: 13)
    /// Left indent of list paragraphs; the marker is drawn inside it.
    static let listIndent: CGFloat = 20
    /// Keeps the header's text clear of the hover buttons in the card's top-right corner.
    static let headerTrailingSpace: CGFloat = 76

    static func font(for style: Style) -> NSFont {
        var traits: NSFontDescriptor.SymbolicTraits = []
        if style.contains(.bold) { traits.insert(.bold) }
        if style.contains(.italic) { traits.insert(.italic) }
        guard !traits.isEmpty else { return body }
        return NSFont(descriptor: body.fontDescriptor.withSymbolicTraits(traits), size: body.pointSize) ?? body
    }

    /// Bold/italic of a body font. A font of any other size (the header font carried into the
    /// body by Enter, or pasted text) counts as plain.
    static func style(of font: NSFont?) -> Style {
        guard let font, abs(font.pointSize - body.pointSize) < 0.5 else { return [] }
        let traits = font.fontDescriptor.symbolicTraits
        var style: Style = []
        if traits.contains(.bold) { style.insert(.bold) }
        if traits.contains(.italic) { style.insert(.italic) }
        return style
    }

    static let headerAttributes: [NSAttributedString.Key: Any] = {
        let paragraph = NSMutableParagraphStyle()
        paragraph.tailIndent = -headerTrailingSpace
        paragraph.paragraphSpacing = 6
        return [.font: header, .foregroundColor: Palette.ink, .paragraphStyle: paragraph]
    }()

    static func bodyAttributes(kind: LineKind, style: Style) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 3
        if kind.isList {
            paragraph.firstLineHeadIndent = listIndent
            paragraph.headIndent = listIndent
        }
        return [.font: font(for: style), .foregroundColor: Palette.ink, .paragraphStyle: paragraph,
                .cardLine: kind.attributeValue]
    }
}

extension Note {
    /// The editor's text: header paragraph, then one paragraph per body line. Each paragraph's
    /// terminating "\n" carries that paragraph's attributes.
    var attributedText: NSAttributedString {
        let text = NSMutableAttributedString(string: header, attributes: EditorStyle.headerAttributes)
        var previous = EditorStyle.headerAttributes
        for line in body {
            text.append(NSAttributedString(string: "\n", attributes: previous))
            for run in line.runs {
                text.append(NSAttributedString(string: run.text,
                                               attributes: EditorStyle.bodyAttributes(kind: line.kind, style: run.style)))
            }
            previous = EditorStyle.bodyAttributes(kind: line.kind, style: [])
        }
        return text
    }

    /// Inverse of `attributedText`. Paragraph 0 → `header` (plain string, attributes ignored).
    /// Paragraph i > 0 → a line whose kind is the `.cardLine` at its start and whose runs follow
    /// the fonts. `trailingKind` is the kind of an empty last paragraph, which has no characters.
    init(attributedText text: NSAttributedString, trailingKind: LineKind = .text) {
        let string = text.string as NSString
        var ranges: [NSRange] = []
        var start = 0
        while true {
            let newline = string.range(of: "\n", range: NSRange(location: start, length: string.length - start))
            guard newline.location != NSNotFound else {
                ranges.append(NSRange(location: start, length: string.length - start))
                break
            }
            ranges.append(NSRange(location: start, length: newline.location - start))
            start = newline.location + 1
        }
        let header = string.substring(with: ranges[0])
        let body = ranges.dropFirst().map { range -> Line in
            let kind = range.location < string.length
                ? LineKind(attributeValue: text.attribute(.cardLine, at: range.location, effectiveRange: nil))
                : trailingKind
            var runs: [Run] = []
            if range.length > 0 {
                text.enumerateAttribute(.font, in: range) { value, sub, _ in
                    runs.append(Run(text: string.substring(with: sub), style: EditorStyle.style(of: value as? NSFont)))
                }
            }
            return Line(kind: kind, runs: runs)
        }
        self.init(header: header, body: body)
    }
}

final class CardTextView: NSTextView {
    /// Every content change, already as a `Note`.
    var onChange: (Note) -> Void = { _ in }
    /// A single press in the header area. Returns true when it became a window drag; false means
    /// "it was a click", and normal text handling proceeds (see `trackWindowDrag`).
    var onHeaderPress: (NSEvent) -> Bool = { _ in false }
    var onFocusChange: () -> Void = {}

    /// The note currently shown, derived from the storage after every change. `show` compares
    /// against it so a re-render caused by our own `onChange` never resets the caret.
    private(set) var note = Note.blank

    init() {
        // TextKit 1, built by hand: the marker drawing and the header hit area need
        // line-fragment geometry from an NSLayoutManager.
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        allowsUndo = true
        isRichText = true
        importsGraphics = false
        usesFontPanel = false
        usesRuler = false
        drawsBackground = false
        insertionPointColor = Palette.ink
        selectedTextAttributes = [.backgroundColor: Palette.highlight]
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticTextReplacementEnabled = false
        textContainerInset = NSSize(width: 2, height: 2)
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        typingAttributes = EditorStyle.headerAttributes
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Replaces the content unless it already shows `note` (keeps caret and undo while typing).
    func show(_ note: Note) {
        guard note != self.note, let storage = textStorage else { return }
        self.note = note
        storage.setAttributedString(note.attributedText)
        undoManager?.removeAllActions()
        setSelectedRange(NSRange(location: min(selectedRange().location, storage.length), length: 0))
        fixTypingAttributes()
        needsDisplay = true
    }

    /// Bottom of the header paragraph, in this (flipped) view's coordinates. Everything above it,
    /// including the top inset, is the header's press area.
    var headerBottom: CGFloat {
        guard let layoutManager, let textContainer else { return 0 }
        let string = self.string as NSString
        guard string.length > 0 else {
            let extra = layoutManager.extraLineFragmentRect
            return textContainerOrigin.y + (extra.isEmpty ? EditorStyle.header.boundingRectForFont.height : extra.maxY)
        }
        let header = string.paragraphRange(for: NSRange(location: 0, length: 0))
        let glyphs = layoutManager.glyphRange(forCharacterRange: header, actualCharacterRange: nil)
        return textContainerOrigin.y + layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer).maxY
    }

    // MARK: Formatting commands

    /// ⌘B / ⌘I and the bar's first two buttons. Body only: in the header it does nothing.
    /// Empty selection → toggles the typing attributes; otherwise removes the trait if the whole
    /// selection has it, else adds it. Undoable.
    func toggle(_ style: Style) {
        guard let storage = textStorage else { return }
        let string = self.string as NSString
        let headerEnd = NSMaxRange(string.paragraphRange(for: NSRange(location: 0, length: 0)))
        let selection = selectedRange()
        if selection.length == 0 {
            guard currentParagraph().location > 0 else { return }
            var current = EditorStyle.style(of: typingAttributes[.font] as? NSFont)
            current.formSymmetricDifference(style)
            typingAttributes[.font] = EditorStyle.font(for: current)
            return
        }
        let body = NSIntersectionRange(selection, NSRange(location: headerEnd, length: string.length - headerEnd))
        guard body.length > 0 else { return }
        var everyRunHasIt = true
        storage.enumerateAttribute(.font, in: body) { value, _, _ in
            if !EditorStyle.style(of: value as? NSFont).isSuperset(of: style) { everyRunHasIt = false }
        }
        guard shouldChangeText(in: body, replacementString: nil) else { return }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: body) { value, sub, _ in
            var runStyle = EditorStyle.style(of: value as? NSFont)
            if everyRunHasIt { runStyle.subtract(style) } else { runStyle.formUnion(style) }
            storage.addAttribute(.font, value: EditorStyle.font(for: runStyle), range: sub)
        }
        storage.endEditing()
        didChangeText()
    }

    /// The bar's list buttons: every body paragraph touched by the selection becomes `kind`,
    /// or plain text if they all already are `kind`. Undoable.
    func toggleLineKind(_ kind: LineKind) {
        let paragraphs = bodyParagraphs(in: selectedRange())
        guard !paragraphs.isEmpty else { return }
        let allAlready = paragraphs.allSatisfy { self.kind(ofParagraph: $0).sameList(as: kind) }
        setKind(allAlready ? .text : kind, paragraphs: paragraphs)
    }

    /// Targets of the hidden Format menu's ⌘B / ⌘I items (see `AppDelegate.installMainMenu`).
    @objc func cardsToggleBold(_ sender: Any?) { toggle(.bold) }
    @objc func cardsToggleItalic(_ sender: Any?) { toggle(.italic) }

    // MARK: Typing rules

    /// Enter continues a list (a new checkbox starts unchecked) and ends it on an empty item.
    override func insertNewline(_ sender: Any?) {
        guard !hasMarkedText(), selectedRange().length == 0 else {
            super.insertNewline(sender)
            return
        }
        let paragraph = currentParagraph()
        let content = contentLength(of: paragraph)
        let body = allParagraphs().dropFirst()
        let line = paragraph.location == 0 ? nil : body.firstIndex(of: paragraph).map { $0 - 1 }
        switch Typing.onReturn(body.map { LineShape(kind: kind(ofParagraph: $0)) }, at: line, isEmpty: content == 0) {
        case .reshape(let shapes):
            setKind(shapes[line ?? 0].kind, paragraphs: [paragraph])
        case .splitLine(let shape):
            super.insertNewline(sender)
            setKind(shape.kind, paragraphs: [currentParagraph()])
        case .system, .nothing:
            super.insertNewline(sender)
        }
    }

    /// Auto-start: typing a space right after "-", "1." or "[]" at the very start of a plain body
    /// paragraph removes those characters and makes the paragraph a list item. One undo step
    /// gives back the literal characters.
    override func insertText(_ string: Any, replacementRange: NSRange) {
        let text = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
        if text == " ", !hasMarkedText(), selectedRange().length == 0, startList() { return }
        super.insertText(Self.plainNewlines(text), replacementRange: replacementRange)
    }

    /// Backspace at the start of a list item removes the marker instead of joining lines.
    override func deleteBackward(_ sender: Any?) {
        let selection = selectedRange()
        if selection.length == 0, !hasMarkedText() {
            let paragraph = currentParagraph()
            if paragraph.location > 0, selection.location == paragraph.location, kind(ofParagraph: paragraph).isList {
                setKind(.text, paragraphs: [paragraph])
                return
            }
        }
        super.deleteBackward(sender)
    }

    /// Pasting and dropping take plain text only; formatting comes from the card's own rules.
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }

    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard let text = pboard.string(forType: .string) else { return false }
        insertText(Self.plainNewlines(text), replacementRange: selectedRange())
        return true
    }

    // MARK: Change tracking

    /// After any change (typing, paste, undo): re-impose the header look on paragraph 0 and the
    /// body look on everything else, then publish the new note.
    override func didChangeText() {
        super.didChangeText()
        guard !hasMarkedText() else { return }
        restyle()
        fixTypingAttributes()
        publish()
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        if !stillSelecting, !hasMarkedText() {
            fixTypingAttributes()
            needsDisplay = true   // the empty last line's marker follows the caret
        }
    }

    override func becomeFirstResponder() -> Bool {
        defer { onFocusChange() }
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        defer { onFocusChange() }
        return super.resignFirstResponder()
    }

    // MARK: Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let paragraph = checkbox(at: point), case .todo(let done) = kind(ofParagraph: paragraph) {
            setKind(.todo(done: !done), paragraphs: [paragraph])
            return
        }
        if event.clickCount == 1, !event.modifierFlags.contains(.shift), point.y <= headerBottom,
           onHeaderPress(event) {
            return                                      // the press became a window drag
        }
        super.mouseDown(with: event)                    // a click: NSTextView places the caret
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty {
            let placeholder = NSAttributedString(string: "Title", attributes: [
                .font: EditorStyle.header, .foregroundColor: Palette.inkFaint,
            ])
            placeholder.draw(at: NSPoint(x: textContainerOrigin.x + (textContainer?.lineFragmentPadding ?? 0),
                                         y: textContainerOrigin.y))
        }
        for marker in markers() {
            switch marker.kind {
            case .todo(let done):
                let name = done ? "checkmark.square" : "square"
                guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: 12, weight: .regular)) else { continue }
                image.isTemplate = true
                let tinted = image.tinted(Palette.inkSoft)
                tinted.draw(in: marker.box)
            default:
                let attributes: [NSAttributedString.Key: Any] = [.font: EditorStyle.body, .foregroundColor: Palette.inkSoft]
                let label = NSAttributedString(string: marker.label, attributes: attributes)
                let size = label.size()
                label.draw(at: NSPoint(x: marker.box.maxX - size.width, y: marker.baseline - EditorStyle.body.ascender))
            }
        }
    }

    private struct Marker {
        let paragraph: NSRange
        let kind: LineKind
        let label: String
        /// Where the marker sits, in view coordinates: the box a checkbox fills, whose right edge
        /// a bullet or number aligns to.
        let box: NSRect
        let baseline: CGFloat
    }

    /// Every list paragraph's marker, with the same geometry for drawing and checkbox clicks.
    private func markers() -> [Marker] {
        guard let layoutManager, let textContainer else { return [] }
        let paragraphs = allParagraphs().dropFirst()
        let kinds = paragraphs.map(kind(ofParagraph:))
        let numbers = listNumbers(kinds.map { LineShape(kind: $0) })
        let left = textContainerOrigin.x + textContainer.lineFragmentPadding
        var result: [Marker] = []
        for ((paragraph, kind), number) in zip(zip(paragraphs, kinds), numbers) where kind.isList {
            let line: NSRect
            let baselineOffset: CGFloat
            if paragraph.location < (string as NSString).length {
                let glyph = layoutManager.glyphIndexForCharacter(at: paragraph.location)
                line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                baselineOffset = layoutManager.location(forGlyphAt: glyph).y
            } else {
                line = layoutManager.extraLineFragmentRect
                baselineOffset = layoutManager.defaultBaselineOffset(for: EditorStyle.body)
            }
            guard line.height > 0 else { continue }
            let baseline = textContainerOrigin.y + line.minY + baselineOffset
            let box = NSRect(x: left + 2, y: baseline - 11, width: 13, height: 13)
            let label = switch kind {
            case .bullet: "•"
            case .numbered: "\(number ?? 1)."
            default: ""
            }
            result.append(Marker(paragraph: paragraph, kind: kind, label: label,
                                 box: kind == .bullet ? box.offsetBy(dx: -3, dy: 0) : box, baseline: baseline))
        }
        return result
    }

    private func checkbox(at point: NSPoint) -> NSRange? {
        markers().first { marker in
            if case .todo = marker.kind { return marker.box.insetBy(dx: -4, dy: -3).contains(point) }
            return false
        }?.paragraph
    }

    // MARK: Paragraph helpers

    /// Every paragraph's full range (including its "\n"), header first. An empty last paragraph
    /// is included as a zero-length range at the end.
    private func allParagraphs() -> [NSRange] {
        let string = self.string as NSString
        var result: [NSRange] = []
        var location = 0
        repeat {
            let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
            result.append(paragraph)
            location = NSMaxRange(paragraph)
        } while location < string.length
        if string.length > 0, string.hasSuffix("\n") {
            result.append(NSRange(location: string.length, length: 0))
        }
        return result
    }

    /// The body paragraphs a selection touches (for a caret, the one it is in).
    private func bodyParagraphs(in range: NSRange) -> [NSRange] {
        let covered = (string as NSString).paragraphRange(for: range)
        return allParagraphs().dropFirst().filter { paragraph in
            paragraph.length == 0 ? paragraph.location == covered.location
                                  : NSIntersectionRange(paragraph, covered).length > 0
        }
    }

    private func currentParagraph() -> NSRange {
        let string = self.string as NSString
        let caret = min(selectedRange().location, string.length)
        return string.paragraphRange(for: NSRange(location: caret, length: 0))
    }

    private func contentLength(of paragraph: NSRange) -> Int {
        let string = self.string as NSString
        guard paragraph.length > 0 else { return 0 }
        return string.character(at: NSMaxRange(paragraph) - 1) == 10 ? paragraph.length - 1 : paragraph.length
    }

    /// The header (location 0) is never a list.
    private func kind(ofParagraph paragraph: NSRange) -> LineKind {
        guard paragraph.location > 0 else { return .text }
        if paragraph.length > 0, let storage = textStorage {
            return LineKind(attributeValue: storage.attribute(.cardLine, at: paragraph.location, effectiveRange: nil))
        }
        return selectedRange().location == paragraph.location ? LineKind(attributeValue: typingAttributes[.cardLine]) : .text
    }

    /// Sets `kind` on body paragraphs as one undoable change. An empty last paragraph has no
    /// characters, so its kind goes into the typing attributes.
    private func setKind(_ kind: LineKind, paragraphs: [NSRange]) {
        guard let storage = textStorage else { return }
        let filled = paragraphs.filter { $0.length > 0 && $0.location > 0 && self.kind(ofParagraph: $0) != kind }
        if let first = filled.first, let last = filled.last {
            let union = NSUnionRange(first, last)
            if shouldChangeText(in: union, replacementString: nil) {
                storage.beginEditing()
                for paragraph in filled { storage.addAttribute(.cardLine, value: kind.attributeValue, range: paragraph) }
                storage.endEditing()
                didChangeText()
            }
        }
        if paragraphs.contains(where: { $0.length == 0 && $0.location > 0 }) {
            typingAttributes[.cardLine] = kind.attributeValue
            fixTypingAttributes()
            publish()
            needsDisplay = true
        }
    }

    /// The space-after-prefix rule. Returns true when it started a list.
    private func startList() -> Bool {
        guard let storage = textStorage else { return false }
        let string = self.string as NSString
        let caret = selectedRange().location
        let paragraph = currentParagraph()
        guard paragraph.location > 0, kind(ofParagraph: paragraph) == .text else { return false }
        let prefixRange = NSRange(location: paragraph.location, length: caret - paragraph.location)
        guard let kind = Typing.listKind(forPrefix: string.substring(with: prefixRange)),
              shouldChangeText(in: prefixRange, replacementString: "") else { return false }
        storage.replaceCharacters(in: prefixRange, with: "")
        let remaining = (self.string as NSString).paragraphRange(for: NSRange(location: paragraph.location, length: 0))
        if remaining.length > 0 {
            storage.addAttribute(.cardLine, value: kind.attributeValue, range: remaining)
        }
        setSelectedRange(NSRange(location: paragraph.location, length: 0))
        typingAttributes[.cardLine] = kind.attributeValue
        didChangeText()
        return true
    }

    /// Paragraph 0: header font, no `.cardLine`, no inline traits ("regardless of formatting").
    /// Paragraph > 0: body font with the run's own bold/italic, one kind for the whole paragraph
    /// (the kind at its start), paragraph style from that kind. Attributes only, so it neither
    /// changes the note's text nor triggers another `didChangeText`.
    private func restyle() {
        guard let storage = textStorage else { return }
        storage.beginEditing()
        for (index, paragraph) in allParagraphs().enumerated() where paragraph.length > 0 {
            if index == 0 {
                storage.setAttributes(EditorStyle.headerAttributes, range: paragraph)
                continue
            }
            let kind = LineKind(attributeValue: storage.attribute(.cardLine, at: paragraph.location, effectiveRange: nil))
            var styles: [(NSRange, Style)] = []
            storage.enumerateAttribute(.font, in: paragraph) { value, sub, _ in
                styles.append((sub, EditorStyle.style(of: value as? NSFont)))
            }
            for (range, style) in styles {
                storage.setAttributes(EditorStyle.bodyAttributes(kind: kind, style: style), range: range)
            }
        }
        storage.endEditing()
    }

    /// Typing attributes follow the caret: header look in paragraph 0, otherwise the body look
    /// for the paragraph's kind, keeping the bold/italic the user has toggled.
    private func fixTypingAttributes() {
        let paragraph = currentParagraph()
        if paragraph.location == 0 {
            typingAttributes = EditorStyle.headerAttributes
            return
        }
        let style = EditorStyle.style(of: typingAttributes[.font] as? NSFont)
        typingAttributes = EditorStyle.bodyAttributes(kind: kind(ofParagraph: paragraph), style: style)
    }

    private func publish() {
        let string = self.string as NSString
        let caretInTrailing = string.length > 0 && string.hasSuffix("\n") && selectedRange().location == string.length
        let trailing = caretInTrailing ? LineKind(attributeValue: typingAttributes[.cardLine]) : .text
        let current = Note(attributedText: textStorage ?? NSTextStorage(), trailingKind: trailing)
        needsDisplay = true
        guard current != note else { return }
        note = current
        onChange(current)
    }

    /// Only "\n" separates paragraphs here; other line breaks from pasted text become "\n".
    private static func plainNewlines(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
    }
}

private extension NSImage {
    /// A copy of a template image filled with `color`.
    func tinted(_ color: NSColor) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            self.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}
