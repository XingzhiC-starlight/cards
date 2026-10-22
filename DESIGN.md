# Cards: design notes

How the prototype in [CARDS-SPEC.md](CARDS-SPEC.md) is put together, and why.

## Problem

Up to 19 card windows and a stack window are all views of one tightly coupled state. An edge
click on one card changes the stack that Pop and every other card rely on. Clarity has a global
switch plus a per-card "last state". Summaries arrive later and must attach to the right version
of the right card. All of it persists to Markdown plus one sidecar. Two spec rules make the shape
non-obvious:

- "The displayed card goes back into the stack in the spot the incoming one left (a loop)".
  Any fixed-index rule just toggles between two cards, so a real loop needs each popped card to
  remember where it sits in the stack.
- The header is both the first line of editable text and the handle you drag the card by.

## Usage (caller's view)

All state is one value, `Desk`. To change anything, a view sends a `Command`. Nothing saves,
renders or requests a summary itself: after every command the controller derives all three from
the new desk.

```swift
// A view reports intent (CardView, click in the right edge band):
send(.switchCard(id, .next))

// A rule, tested with plain values: no AppKit, no disk.
var desk = Desk(notes: notes, saved: SavedDesk(stack: [d, a, b, c]))
let shown = desk.apply(.pop(nil))      // d → slot 0

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
| `Desk.swift` | the state, `Command`, and every rule (pop, switch, swap, clarity, restore) |
| `Grid.swift` | slot, frame and edge-band geometry (pure) |
| `Note.swift` | a card's content, its Markdown format, and the typing rules for lists |
| `DeskController.swift` | the single owner of the desk and of every window |
| `Library.swift` | `~/Documents/Cards/*.md` and the hidden sidecar `.cards.json` |
| `Summarizer.swift` | summary requests and the one Anthropic call |
| `CardWindow.swift`, `CardEditor.swift` | the card window, press routing, and the text view |
| `StackWindow.swift`, `Settings.swift`, `App.swift` | stack UI; API key and settings; entry point, menu bar, hotkey |

- **Location is ownership.** A `Card` value lives inside its location: a slot entry
  (`Popped { card, cursor }`) or a stack position. There is no id-to-card map to keep in step,
  so "one card, one place" holds by construction, and a moving card carries its collapsed state
  and summary with it. The stack's bottom-right cell is not a `Slot`, so no card can land on it.
- **Edge switching.** A popped card D with cursor k sits in the ring
  `stack[0..<k] + [D] + stack[k...]`. Next brings in the card after D, previous the one before.
  D takes the incoming card's stack spot and the cursor moves so the ring is unchanged. Repeated
  clicks visit every card, and previous exactly undoes next.
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

## Tradeoffs accepted

- We accept re-rendering every window after every command in exchange for one funnel with no
  "what changed" bookkeeping. Each setter compares before touching AppKit.
- We accept timestamp file names (`2026-10-21 153012.md`) in exchange for an identity that never
  changes.
- We accept rescanning the folder when the app becomes active, instead of live file watching.
- We accept that pressing on the header and moving drags the card instead of selecting text;
  double-click and shift-click still select.
- We accept the Keychain for the API key, which may ask for access again after each rebuild of an
  unsigned debug build.

## Alternatives considered

- **Normalized store** (`[CardID: Card]` plus slot, stack, collapsed and summary maps): every
  transition must keep several keyed structures in agreement.
- **Rotation semantics** for edge switching: simpler, but breaks the spec's wording.
- **Literal marker characters** in the text: native-feeling copy/paste, but the user can edit a
  marker out of sync and every edit needs a renumbering pass that shifts the selection.

## Spec gaps resolved

- New is refused when the desktop is full, the same as Pop; the stack shows "Desktop full".
- The menu bar menu adds "Settings…" so the API key has somewhere to go.
- With no API key, a collapsed card shows "Summary unavailable" with the reason on hover.
- A collapsed card whose body is empty or one line shows that line in the lighter style.
- The grid uses the menu-bar screen and does not subtract the Dock.
