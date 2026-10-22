# Cards: design notes

How the prototype in [CARDS-SPEC.md](CARDS-SPEC.md) is put together, and why.

## Problem

Up to 19 card windows and a stack window are all views of one tightly coupled state. Pop, "↩
Stack", delete and the stack's swipes and edge bands all move through one stack loop, and the
card the stack shows is editable in place. Clarity has a global
switch plus a per-card "last state". Summaries arrive later and must attach to the right version
of the right card. All of it persists to Markdown plus one sidecar. The header is both the first
line of editable text and the handle you drag the card by.

## Usage (caller's view)

All state is one value, `Desk`. To change anything, a view sends a `Command`. Nothing saves,
renders or requests a summary itself: after every command the controller derives all three from
the new desk.

```swift
// A view reports intent (StackWindow, a two-finger swipe or a click in the right edge band):
send(.flipStack(.next))

// A rule, tested with plain values: no AppKit, no disk.
var desk = Desk(notes: notes, saved: SavedDesk(stack: [d, a, b, c]))
let shown = desk.apply(.pop)           // d → slot 0

// The controller: the whole side-effect story.
func send(_ command: Command) {
    let focus = desk.apply(command)
    scheduleSave()                     // Library.save(desk): writes only what differs on disk
    summarizer.sync(deskCards, ...)    // wanted requests = f(desk)
    render()                           // windows = f(desk, grid)
}
```

## Shape

| File | What it owns |
| --- | --- |
| `Desk.swift` | the state, `Command`, every rule (pop, flip, swap, clarity, restore), and Hide all's `Visibility` |
| `Grid.swift` | slots, free positions, the snap rule, the overhang limit, frames and edge bands (pure) |
| `Note.swift` | a card's content, its Markdown format, and the typing rules for lists |
| `DeskController.swift` | the single owner of the desk and of every window |
| `Library.swift` | `~/Documents/Cards/*.md` and the hidden sidecar `.cards.json` |
| `Summarizer.swift` | summary requests and the one Anthropic call |
| `CardWindow.swift`, `CardEditor.swift` | the card window, press routing, and the text view |
| `StackWindow.swift`, `Swipe.swift` | the stack window; the rules that turn scroll events into flips (pure) |
| `Settings.swift`, `App.swift` | API key and settings; entry point, menu bar, hotkey, reopen |

- **Location is ownership.** A `Card` value lives inside its location: a desktop entry (with its
  `Place`) or a stack position. There is no id-to-card map to keep in step,
  so "one card, one place" holds by construction, and a moving card carries its collapsed state
  and summary with it.
- **A place is a slot or a free point.** `Place` is `.slot(Slot)` or `.free(GridPoint)`, the
  center as a fraction of the screen, so a display change rescales free cards with no model
  change. Cards and the stack both have one. `Place.dropped(at:)` is the whole snap rule (snap
  within 15 % of a cell), and the drag guide asks it the same question while the pointer moves,
  so the guide can never promise a snap the drop won't make.
- **Overhang is a rendering rule.** `Grid.clamped` is the one place that says how far a free
  place may leave the screen (40 points of the header strip and of the width stay inside
  `reachable`, the screen minus menu bar and Dock; the top never rises). Computing a frame and
  reading a drag both go through it, and the model never does: a saved point keeps its raw
  fraction, so a smaller display pulls a card back while a larger one gives it back its spot.
  Snapped places are cells of `area`, so they always fit.
- **The stack is a loop with one blank page.** `Desk.stack` is the stacked cards, top first,
  and `Desk.selection` is the loop position: an index into the stack, or `stack.count` for the
  blank page after the bottom card. Next and previous move the position and never reorder the
  cards, so they undo each other and work with any number of cards. Every insert and remove goes
  through two helpers that keep the position on the same item, which is how "Pop", delete and an
  outside file removal all end up showing the next card. Typing on the blank page appends a card
  at its position, so the new card stays selected and the blank page moves after it.
- **One card view, two homes.** The stack shows its selected card with the same `CardView` a
  popped card uses. On the stack it does not drag, has no "↩ Stack" button, and leaves its border
  to the stack. It shows the blank page when it has no card.
- **Hide all is presentation.** `Visibility` lives outside the desk and is never saved. While
  hidden, New and Pop reveal just the card they bring out, and the stack window shrinks to its
  ribbon instead of ordering out. The stack window gets the `Visibility` value itself: its
  ribbon-only shape, the count badge's place and the toggle button's icon all derive from it.
  The toggle calls `DeskController.toggleHidden`, the path ⌥⌘C takes, not a `Command`.
- **Derived, idempotent side effects.** `render()` compares the desk with the real windows,
  `Library.save` with the disk, and `Summarizer.sync` with the requests in flight. Each is safe
  to run any number of times.
- **Editor.** TextKit 1. The text storage holds exactly the note's text. A body line's list kind
  is a paragraph attribute and its marker is drawn in the indent, so a marker can never be
  half-deleted. Paragraph 0 is restyled as the header after every change.
- **Summaries.** A summary records the fingerprint of the note it describes; it is fresh only
  while that matches. Spinner, failure and "no key" are derived, not stored as flags.

## Synthesis decision

Three candidate sketches were drafted in parallel (Opus, Fable, Sonnet) and scored by a separate
Fable judge. The Opus candidate is the base: it is the only one where every spec sentence has an
owner behaving as worded, and the judge agreed independently.

- Rejected from the Fable candidate: its edge switch rotates the stack (outgoing card to the
  bottom), which contradicts "the spot the incoming one left".
- Rejected from the Sonnet candidate: its single-array loop puts the outgoing card at the stack
  bottom on wrap-around, and its drag relies on `performDrag`, which does not block.
- Grafted from Fable: on an edge switch the existing window is re-pointed at the incoming card
  instead of closing and reopening, so there is no flicker and keyboard focus stays.
- Grafted from Sonnet: the list typing rules are pure functions (`Typing` in `Note.swift`), and
  only cards on the desktop request summaries, so a large stack does not fire a burst of requests.

Later changes, after trying the app:

- Edge bands moved from popped cards to the stack window, to show the cards hidden under the
  stack. Each popped card's stack cursor and the window re-pointing graft went with them; the
  stack itself is now the loop.
- The stack moved to the top-left cell and looks like one card: a sky-blue ribbon (the control
  center) above the selected card, with no list of the cards underneath.
- The stack's ribbon has a menu button with the menu bar icon's menu (one builder,
  `AppDelegate.makeAppMenu`), because a crowded menu bar can hide the icon behind the notch.
  Later it got its own Hide all button, so the ribbon's variant of the menu dropped the
  visibility items and Open Stack.
- Hover follows the pointer's real position (one mouse-move monitor in `DeskController`) instead
  of per-view enter/exit events, which a fast pointer can skip.
- 2026-10-22 revision: the selected stacked card became editable, with its own clarity, refresh
  and trash buttons. The loop gained the blank page, and a flip moves a position instead of
  rotating the stack, so the stack's order no longer changes when you browse it. Two-finger
  swipes switch cards; the edge bands stay as the click alternative. Clarity and summaries now
  cover stacked cards too, which reverses the Sonnet graft above. Hide all keeps the ribbon.
- 2026-10-22, free placement: cards and the stack can be dropped anywhere, with a guide outlining
  the slot a drop would snap to. The grid became 20 equal slots and the stack one more movable
  item. Sidecar version 2 adds free points and the stack's place; version 1 files, whose slot
  numbers skipped the stack's cell, are shifted by one on load.
- 2026-10-22, overhang and the ribbon toggle: free cards and the stack may hang off the left,
  right and bottom edges, never the top, as long as 40 points of the header strip and the width
  stay reachable. The stack's home moved to the top-right so Pop fills from the top-left;
  version 1 sidecars keep it top-left. Hide all / Show all became a one-click button in the
  ribbon, and the count badge moved to the card area's bottom-right, into the ribbon only while
  Hide all has removed the card.

## Tradeoffs accepted

- We accept re-rendering every window after every command in exchange for one funnel with no
  "what changed" bookkeeping. Each setter compares before touching AppKit.
- We accept timestamp file names (`2026-10-21 153012.md`) in exchange for an identity that never
  changes.
- We accept rescanning the folder when the app becomes active, instead of live file watching.
- We accept that pressing on the header and moving drags the card instead of selecting text;
  double-click and shift-click still select.
- We accept a burst of summary requests at launch when many stacked cards have none cached, in
  exchange for every card having a summary under the same rules.
- We accept the Keychain for the API key, which may ask for access again after each rebuild of an
  unsigned debug build.

## Alternatives considered

- **Normalized store** (`[CardID: Card]` plus slot, stack, collapsed and summary maps): every
  transition must keep several keyed structures in agreement.
- **Literal marker characters** in the text: native-feeling copy/paste, but the user can edit a
  marker out of sync and every edit needs a renumbering pass that shifts the selection.

## Spec gaps resolved

- New on a full desktop beeps, shows "Desktop full", and shows the stack's blank page with the
  cursor in it. While hidden, that also brings back the stack's card area.
- "↩ Stack" shows the returned card on the stack, so you see where it went.
- Switching the stack to another card takes the cursor out of the editor, so typing never lands
  in a card you did not click.
- A file added outside the app while Clarity is ON joins the stack collapsed.
- While hidden, swipes and edge bands do nothing: there is no card area to switch.
- The menu bar menu adds "Settings…" so the API key has somewhere to go.
- With no API key, a collapsed card shows "Summary unavailable" with the reason on hover.
- A collapsed card whose body is empty or one line shows that line in the lighter style.
- The grid uses the menu-bar screen and does not subtract the Dock. Only the overhang limit
  does, so a header can't hide under it.
- The count badge sits at the bottom-right of the stack's card area: the hover buttons are at
  the top-right and the formatting bar's buttons at the left, so it covers neither. It takes no
  clicks, so a press on it still places the caret in the text under it. Under Hide all, in a
  ribbon too narrow for it beside the toolbar and the buttons, it is hidden, and "Desktop full"
  truncates first, so no button ever moves.
- Free cards piled into one slot leave other slots untaken, so Pop also stops at 19 cards on the
  desktop, keeping the old ceiling.
- The guide window sits above the dragged card and ignores the mouse; a swap target shows the
  same outline as an empty slot.
