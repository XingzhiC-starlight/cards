import Foundation

// The whole app state, as one pure value, and every rule that changes it.
// No AppKit, no files, no network: everything here is unit-testable with plain values.

// MARK: - Identity and per-card state

/// A card's identity: its Markdown file name without ".md" (for example "2026-10-21 153012").
/// Chosen once at creation and never changed, so it can key the sidecar for the card's whole
/// life. Files added by hand keep whatever name they have; the name is the identity.
struct CardID: RawRepresentable, Hashable, Comparable, Codable {
    let rawValue: String
    static func < (a: CardID, b: CardID) -> Bool { a.rawValue < b.rawValue }
}

/// Everything about one card. A `Card` value lives in exactly one place, a desktop slot or the
/// stack, and moves between them whole. Its clarity state and summary therefore travel with it
/// and can never be orphaned or attached to the wrong card.
struct Card: Equatable {
    let id: CardID
    var note: Note { didSet { digest = note.digest } }
    /// Fingerprint of `note`. Kept in step by `note`'s observer, never assigned anywhere else.
    private(set) var digest: Digest
    /// The card's own clarity state. It travels with the card, so a popped card keeps it.
    var collapsed: Bool
    /// The latest summary attempt. It describes the current note only while
    /// `summary.source == digest`; a stale one is simply ignored, never cleared.
    var summary: Summary?

    init(id: CardID, note: Note, collapsed: Bool = false, summary: Summary? = nil) {
        self.id = id
        self.note = note
        self.digest = note.digest
        self.collapsed = collapsed
        self.summary = summary
    }
}

/// One summary attempt for one version of a note. A failure is kept like a success, so the card
/// shows "Summary unavailable" until the note changes or the user presses refresh. Only `.text`
/// outcomes are persisted (see `SavedSummary`), so a relaunch retries failures.
struct Summary: Equatable {
    let source: Digest
    let outcome: Outcome

    enum Outcome: Equatable {
        case text(String)
        case failed(reason: String)
    }
}

enum Direction: Equatable {
    case previous, next
}

// MARK: - Commands

/// Every way the state can change. Views, the summarizer and the folder rescan all send these to
/// `DeskController.send`; nothing else mutates a `Desk`.
enum Command {
    /// Stack toolbar "New": a blank card, popped straight out, expanded, focused. On a full
    /// desktop it creates nothing and the stack shows its blank page instead.
    case new(at: Date)
    /// Stack toolbar "Pop": the selected stacked card. Nothing while the blank page shows.
    case pop
    /// Per-card "↩ Stack" button: the card goes to the top of the stack, and the stack shows it.
    case returnToStack(CardID)
    /// Click in one of the stack's edge bands or a two-finger swipe: move around the stack's loop.
    case flipStack(Direction)
    /// The first character typed on the stack's blank page. Only meaningful while it shows.
    case writeBlank(Note, at: Date)
    /// Header drag released over `Slot`; swaps with the occupant, if any.
    case move(CardID, to: Slot)
    /// Trash button, after the user confirmed "Delete this card?".
    case delete(CardID)
    /// Every text change in a card's editor.
    case edit(CardID, Note)
    /// Per-card clarity button, or a click on a collapsed card's body (`false`).
    case setCollapsed(CardID, Bool)
    /// The stack's global Clarity button.
    case toggleClarity
    /// Per-card refresh button: forget the summary so a new one is requested now.
    case refreshSummary(CardID)
    /// A summary request finished. Dropped if the note changed while it was in flight.
    case storeSummary(CardID, Summary)
    /// A rescan of the folder found this set of notes (files added, removed or edited outside).
    case syncFiles([CardID: Note])

    /// The card being typed into, for the summarizer's quiet period.
    var typedCard: CardID? {
        if case .edit(let id, _) = self { id } else { nil }
    }
}

// MARK: - Desk

/// The single source of truth: which card is in which slot, the stack order, which stack page
/// shows, global clarity, and (inside each `Card`) content, collapsed state and summary.
///
/// Invariants, all kept by construction in this file:
/// - every card is in exactly one place (one slot cell or one stack position);
/// - `slots.count == Slot.count`, so the stack's top-left cell can never hold a card;
/// - `selection` is in `0...stack.count`.
struct Desk: Equatable {
    /// Indexed by `Slot.index`.
    private(set) var slots: [Card?]
    /// Top card first. Its order changes only when a card enters or leaves, never on a flip.
    private(set) var stack: [Card]
    /// The stack's loop position: the stacked card that shows, or `stack.count` for the blank
    /// page that closes the loop. Not persisted: a launch shows the top card (the blank page
    /// when the stack is empty). Every insert into or removal from `stack` goes through
    /// `insertCard` / `removeCard`, which keep it on the same page.
    private(set) var selection: Int
    /// Global clarity (the stack's Clarity button). Per-card state is `Card.collapsed`.
    private(set) var clarity: Bool

    /// Rebuilds the desk from disk. `notes` decides which cards exist; `saved` only places them.
    /// Total over any input: unknown ids, invalid or doubly-used slots and duplicates are dropped,
    /// and cards the sidecar never heard of join the bottom of the stack in id (that is, creation)
    /// order. A missing sidecar (`SavedDesk()`) puts every card in the stack.
    init(notes: [CardID: Note], saved: SavedDesk) {
        let collapsed = Set(saved.collapsed)
        var summaries: [CardID: Summary] = [:]
        for s in saved.summaries { summaries[s.card] = Summary(source: s.source, outcome: .text(s.text)) }
        func card(_ id: CardID) -> Card? {
            notes[id].map { Card(id: id, note: $0, collapsed: collapsed.contains(id), summary: summaries[id]) }
        }

        var placed = Set<CardID>()
        var slots = [Card?](repeating: nil, count: Slot.count)
        for p in saved.placements {
            guard let slot = Slot(index: p.slot), slots[slot.index] == nil,
                  !placed.contains(p.card), let c = card(p.card) else { continue }
            slots[slot.index] = c
            placed.insert(p.card)
        }
        var stack: [Card] = []
        for id in saved.stack + notes.keys.sorted() where !placed.contains(id) {
            guard let c = card(id) else { continue }
            stack.append(c)
            placed.insert(id)
        }
        self.slots = slots
        self.stack = stack
        self.selection = 0
        self.clarity = saved.clarity
    }

    // MARK: Queries

    /// Pop order: the first slot (left → right, top → bottom) with no card. Nil = "Desktop full".
    var firstFreeSlot: Slot? { Slot.all.first { slots[$0.index] == nil } }

    var allCards: [Card] { poppedCards + stack }

    /// The stacked card that shows. Nil while the blank page shows.
    var selectedCard: Card? { stack.indices.contains(selection) ? stack[selection] : nil }

    /// The cards on the desktop, in slot order.
    var poppedCards: [Card] { slots.compactMap { $0 } }

    func slot(of id: CardID) -> Slot? { Slot.all.first { slots[$0.index]?.id == id } }

    /// A file stem for a new card: "yyyy-MM-dd HHmmss", with " 2", " 3"… if already taken.
    func freshID(at date: Date) -> CardID {
        let base = Desk.idFormat.string(from: date)
        let taken = Set(allCards.map(\.id.rawValue))
        var candidate = base
        var n = 2
        while taken.contains(candidate) {
            candidate = "\(base) \(n)"
            n += 1
        }
        return CardID(rawValue: candidate)
    }

    // MARK: The one mutation entry point

    /// Applies `command` and returns the card that just arrived on the desktop (the new card or
    /// the popped card), if any.
    /// Every branch is total: a command naming a card that no longer exists is a no-op.
    @discardableResult
    mutating func apply(_ command: Command) -> CardID? {
        switch command {
        case .new(let date): return newCard(at: date)
        case .pop: return pop()
        case .returnToStack(let id): returnToStack(id)
        case .flipStack(let direction): flipStack(direction)
        case .writeBlank(let note, let date): writeBlank(note, at: date)
        case .move(let id, let slot): move(id, to: slot)
        case .delete(let id): delete(id)
        case .edit(let id, let note): update(id) { $0.note = note }
        case .setCollapsed(let id, let collapsed): update(id) { $0.collapsed = collapsed }
        case .toggleClarity: toggleClarity()
        case .refreshSummary(let id): update(id) { $0.summary = nil }
        case .storeSummary(let id, let summary):
            update(id) { card in if summary.source == card.digest { card.summary = summary } }
        case .syncFiles(let notes): syncFiles(notes)
        }
        return nil
    }

    // MARK: Transitions (private: `apply` is the only way in)

    private mutating func newCard(at date: Date) -> CardID? {
        guard let slot = firstFreeSlot else {
            selection = stack.count   // New refuses when the desktop is full; the blank page takes over
            return nil
        }
        let card = Card(id: freshID(at: date), note: .blank, collapsed: false)   // always expanded
        slots[slot.index] = card
        return card.id
    }

    /// Pops the selected card into the first free slot, state intact. The page under it shows next.
    private mutating func pop() -> CardID? {
        guard let slot = firstFreeSlot, selection < stack.count else { return nil }
        let card = removeCard(at: selection)
        slots[slot.index] = card
        return card.id
    }

    private mutating func returnToStack(_ id: CardID) {
        guard let slot = slot(of: id), let card = slots[slot.index] else { return }
        slots[slot.index] = nil
        insertCard(card, at: 0)
        selection = 0
    }

    /// The stack is a loop of its cards and one blank page after the last: `.next` moves down it
    /// and wraps from the blank page to the top card, `.previous` is the reverse. Each undoes the
    /// other, and `stack.count + 1` flips in one direction come back to the start.
    private mutating func flipStack(_ direction: Direction) {
        let pages = stack.count + 1
        selection = switch direction {
        case .next: (selection + 1) % pages
        case .previous: (selection + pages - 1) % pages
        }
    }

    /// The first character typed on the blank page: it becomes a card at the bottom, in the same
    /// place in the loop, so the selection stays on it and a fresh blank page follows.
    private mutating func writeBlank(_ note: Note, at date: Date) {
        guard selection == stack.count, note != .blank else { return }
        insertCard(Card(id: freshID(at: date), note: note), at: selection)
        selection -= 1
    }

    /// Header drag released: move to `target`, swapping with its occupant.
    private mutating func move(_ id: CardID, to target: Slot) {
        guard let from = slot(of: id), from != target else { return }
        slots.swapAt(from.index, target.index)
    }

    /// Deleting the selected stacked card shows the one under it (the blank page after the last).
    private mutating func delete(_ id: CardID) {
        if let slot = slot(of: id) {
            slots[slot.index] = nil
        } else if let i = stack.firstIndex(where: { $0.id == id }) {
            removeCard(at: i)
        }
    }

    /// Sets every card, popped and stacked, to `clarity`. A per-card change afterwards never
    /// touches `clarity`.
    private mutating func toggleClarity() {
        clarity.toggle()
        for i in slots.indices where slots[i] != nil { slots[i]?.collapsed = clarity }
        for i in stack.indices { stack[i].collapsed = clarity }
    }

    /// Makes the card set equal a fresh read of the folder. Gone files remove their card (and
    /// its window), edited files replace the note, new files join the bottom of the stack in id
    /// order. Running it twice with the same input changes nothing the second time.
    private mutating func syncFiles(_ notes: [CardID: Note]) {
        for card in allCards where notes[card.id] == nil { delete(card.id) }
        for (id, note) in notes { update(id) { if $0.note != note { $0.note = note } } }
        let known = Set(allCards.map(\.id))
        for (id, note) in notes.sorted(by: { $0.key < $1.key }) where !known.contains(id) {
            insertCard(Card(id: id, note: note, collapsed: clarity), at: stack.count)
        }
    }

    /// The only way a card enters `stack`. `selection` keeps pointing at the page it pointed at.
    private mutating func insertCard(_ card: Card, at i: Int) {
        stack.insert(card, at: i)
        if i <= selection { selection += 1 }
    }

    /// The only way a card leaves `stack`. Removing the selected page leaves `selection` where it
    /// is, which is now the page that was under it.
    @discardableResult
    private mutating func removeCard(at i: Int) -> Card {
        if i < selection { selection -= 1 }
        return stack.remove(at: i)
    }

    private mutating func update(_ id: CardID, _ change: (inout Card) -> Void) {
        if let slot = slot(of: id), var card = slots[slot.index] {
            change(&card)
            slots[slot.index] = card
        } else if let i = stack.firstIndex(where: { $0.id == id }) {
            change(&stack[i])
        }
    }

    private static let idFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HHmmss"
        return f
    }()
}

// MARK: - What the windows show (pure derivations)

/// Everything one card view displays. Derived; never stored.
struct CardFace: Equatable {
    let id: CardID
    let note: Note
    let collapsed: Bool
    let summary: SummaryFace
}

/// What a collapsed card shows in place of its body.
enum SummaryFace: Equatable {
    /// Empty or one-line body: no summary is ever requested; show the body itself, lighter.
    case body(String)
    /// Waiting for the quiet period to pass, or a request is in flight: spinner.
    case loading
    case text(String)
    /// "Summary unavailable"; the reason is the hover tooltip.
    case unavailable(reason: String)
}

struct StackFace: Equatable {
    /// Real cards only, never the blank page.
    let count: Int
    /// The card the stack shows; nil is the blank page.
    let selected: CardFace?
    let clarity: Bool
    /// Derived from `firstFreeSlot`, so there is no "full" flag to set or clear.
    let desktopFull: Bool
}

extension Desk {
    /// The popped cards, in slot order.
    func cardFaces(hasKey: Bool) -> [(slot: Slot, face: CardFace)] {
        Slot.all.compactMap { slot in
            slots[slot.index].map { (slot, Desk.face(of: $0, hasKey: hasKey)) }
        }
    }

    func stackFace(hasKey: Bool) -> StackFace {
        StackFace(count: stack.count, selected: selectedCard.map { Desk.face(of: $0, hasKey: hasKey) },
                  clarity: clarity, desktopFull: firstFreeSlot == nil)
    }

    private static func face(of card: Card, hasKey: Bool) -> CardFace {
        CardFace(id: card.id, note: card.note, collapsed: card.collapsed,
                 summary: summaryFace(of: card, hasKey: hasKey))
    }

    /// The whole summary lifecycle as seen by the UI, from two facts: the card's latest attempt
    /// and whether a key exists. "Loading" needs no flag: a stale or missing summary always has a
    /// request waiting or in flight (see `Summarizer.sync`).
    static func summaryFace(of card: Card, hasKey: Bool) -> SummaryFace {
        guard card.note.wantsSummary else { return .body(card.note.shortBody) }
        guard let summary = card.summary, summary.source == card.digest else {
            return hasKey ? .loading : .unavailable(reason: "No Anthropic API key. Add one in Settings.")
        }
        switch summary.outcome {
        case .text(let text): return .text(text)
        case .failed(let reason): return .unavailable(reason: reason)
        }
    }
}

// MARK: - Hide all

/// What "Hide all" has hidden. Presentation only: not part of the desk and never persisted, so
/// every launch starts with `.all`.
enum Visibility: Equatable {
    case all
    /// Hide all. `revealed`: popped cards that New or Pop has shown since; `stackCard`: New on a
    /// full desktop showed the stack's blank page.
    case hidden(revealed: Set<CardID>, stackCard: Bool)

    /// Hide all: every popped card and the stack's card area go; the stack's ribbon stays.
    static let hideAll = Visibility.hidden(revealed: [], stackCard: false)

    var isHidden: Bool { self != .all }

    func shows(_ id: CardID) -> Bool {
        switch self {
        case .all: true
        case .hidden(let revealed, _): revealed.contains(id)
        }
    }

    var showsStackCard: Bool {
        switch self {
        case .all: true
        case .hidden(_, let stackCard): stackCard
        }
    }

    mutating func reveal(_ id: CardID) {
        guard case .hidden(var revealed, let stackCard) = self else { return }
        revealed.insert(id)
        self = .hidden(revealed: revealed, stackCard: stackCard)
    }

    mutating func revealStackCard() {
        guard case .hidden(let revealed, _) = self else { return }
        self = .hidden(revealed: revealed, stackCard: true)
    }
}

// MARK: - What the sidecar remembers

/// The part of the desk that is not in the Markdown files. `Library` stores it as JSON in the
/// hidden sidecar; `Desk.init(notes:saved:)` is the only reader and validates everything.
struct SavedDesk: Codable, Equatable {
    var version = 1
    var clarity = false
    var placements: [SavedPlacement] = []
    var stack: [CardID] = []
    var collapsed: [CardID] = []
    /// Successful summaries only: a failure has no `text`, so it cannot be written here.
    var summaries: [SavedSummary] = []
}

struct SavedPlacement: Codable, Equatable {
    /// `Slot.index`; validated on load, since the file is outside the type system.
    var slot: Int
    var card: CardID
}

struct SavedSummary: Codable, Equatable {
    var card: CardID
    var source: Digest
    var text: String
}

extension Desk {
    /// Derived on every save; never kept in sync by hand.
    var saved: SavedDesk {
        let cards = allCards
        return SavedDesk(
            clarity: clarity,
            placements: Slot.all.compactMap { slot in
                slots[slot.index].map { SavedPlacement(slot: slot.index, card: $0.id) }
            },
            stack: stack.map(\.id),
            collapsed: cards.filter(\.collapsed).map(\.id).sorted(),
            summaries: cards.compactMap { card in
                guard let summary = card.summary, case .text(let text) = summary.outcome else { return nil }
                return SavedSummary(card: card.id, source: summary.source, text: text)
            }
        )
    }
}
