# Arrange the stack

The count badge is a button. Clicking it opens a popover under it that lists the stacked cards, top
of the stack first, with the card the stack shows highlighted. Each row has a grip (≡) at its right
edge. Dragging a grip, ⌥↑ and ⌥↓, or VoiceOver's Move up and Move down reorder the stack, and the
stack keeps showing the same card. A click on a row's name, Return or Space turns the stack to that
card. The order is saved in the sidecar on every move.

## Sub-features

- `arrange-open` The badge opens the popover, in the card's corner and in the ribbon under Hide all.
- `arrange-current` The shown card's row is `current card` and the keyboard's row; on the blank page
  the top row is the keyboard's and none is current.
- `arrange-keys` ⌥↑ and ⌥↓ move the selected card one place; at an end nothing moves.
- `arrange-vo` The row's VoiceOver label, its Move up and Move down actions, press, and the
  announcements. VoiceOver itself is not driven.
- `arrange-show` A click on a name, Return, Space or press turns the stack to that card.
- `arrange-drag` Only the grip starts a drag; the drop moves the card; Esc or a drop outside cancels.
- `arrange-live` Rows join, leave and re-mark in place while the popover is open; it closes at zero.
- `arrange-hide-all` Under Hide all, showing a card brings back the stack's card area; moving cards
  does not.
- `arrange-zero` At zero cards the badge is disabled and a click falls through.
- `arrange-saved` The sidecar's `stack` lists the new order.

## How to get to it (user POV)

- Click the count badge in the stack card's bottom-right corner.
- Click the count badge in the ribbon, beside the eye button, while Hide all is on.
- Tab to the badge and press Space, with keyboard navigation on (not driven).
- VoiceOver on the badge, then on a row's actions menu (not driven).

## Driving it with cards-verify

Preconditions:

- `cv launch --seed`; `cv doctor` prints `healthy`. Define `rows() { cv ax tree | sed -n '/AXPopover/,$p' | grep AXCell | sed -E 's/ \[focused\].*//; s/^ +//'; }`.
- For four rows, put two more cards on the stack. Click the right band (`cv ax click stack 0.985
  0.6`) until `cv ax text stack` prints `""`, the blank page. Run `cv ax focus stack`, then `cv ax type
  'Gamma card\ngamma body'`. Do it again from the blank page that follows, with `Delta card with a header
  long enough that it has to truncate before the grip\ndelta body`. Check `cv ax text stack` prints `""`
  before each `focus`: typing with another card showing appends to that card. Alpha, Beta and Gamma
  keep their places, Delta is the bottom card and shows, and the badge reads 4.
- For the scrolling list, repeat that with short headers until `cv ax tree` shows `AXButton "12"`.

- **Open.** Press the badge. Run `cv ax press "Arrange the stack"`. `cv ax tree` has an
  `AXPopover` under the stack window with `AXTable "Stack order"`, one `AXRow` per card and
  `AXCell "Alpha card, 1 of 4"` and so on, top first. The shown card's cell ends `, current card` and
  its row is `[selected]`. `cv shot arrange-open` shows the popover under the badge, the shown
  row tinted and semibold, and a grip (≡) at the right end of each row.
- **Truncation.** A long header reads `Delta card with a header long enoug…` before the grip in
  `cv shot`, while its cell in `cv ax tree` keeps the whole title.
- **Move by keyboard.** With Delta selected at the bottom, run `cv ax key opt+up`. `rows` lists Delta at
  `3 of 4`, still `current card` and `[selected]`; `cv ax text stack` still prints Delta's text. Wait
  1.5 s and run `cv files arrange-keys`: the sidecar's `stack` has `seed-a`, `seed-b`, Delta's id,
  Gamma's id. `cv ax key opt+down` moves it back.
- **At an end.** Press `cv ax key opt+up` until Delta is first, then once more. Nothing moves, and
  the announcement `Already at the top` is posted (see Announcements).
- **Select and show.** Run `cv ax key down`, then `cv ax key return`. The selected row follows the
  arrow, and `cv ax text stack` prints that card. `rows` moves `, current card` to it. `cv ax key
  space` on the same row changes nothing. The popover stays open.
- **VoiceOver actions.** Run `cv ax act "Gamma card" "Move up"`. `rows` shows Gamma one place higher.
  Run `cv ax act "Alpha card" AXPress`; the stack shows Alpha. In `cv ax tree` each cell reads
  `actions=[Move up, Move down, Move up, Move down]`: AppKit lists the pair twice.
- **Announcements.** Open the popover, run `source "$(git rev-parse --show-toplevel)/build/verify-runs/current.env"`
  for `EVIDENCE`, then `(cv ax listen 6 > "$EVIDENCE/announce.txt" &)`, and within the 6 s one
  `cv ax act` Move up on the top card and one on another. The file then holds
  `AXAnnouncementRequested: "Already at the top"` and `"Moved to 3 of 4"`. This is what the app
  posts, not what VoiceOver says.
- **Drag by the grip.** Run `read -r X Y < <(cv ax where "Beta card")`, then `cv ax dragat $((X + 118)) $Y
  0 -80`. The grip is 118 points right of the row's center. `rows` lists Beta first, the stack shows
  the same card, and `cv files arrange-drag` shows the new `stack`. For the insertion line, press
  with `cv ax mouse move $((X + 118)) $Y`, `cv ax mouse down $((X + 118)) $Y`, a few `cv ax mouse drag
  $((X + 118)) <y>` steps, then `cv shot arrange-drag-mid` before `cv ax mouse up …`: a blue line sits
  between rows.
- **Only the grip drags.** Run `cv ax dragat $((X - 60)) $Y 0 -60` on a row's name: no card moves.
- **Cancel.** Press on a grip, drag, run `cv ax key escape`, then `cv ax mouse up …`. Drag again and
  release over the card's text instead of the list. Both times `rows` and the sidecar are as before,
  and no text appears in the card.
- **Click a name.** Real click on a row's name (`cv ax mouse move`, `down`, `up` at `where` minus
  60 on x): the stack shows that card. A real click on a grip that does not drag selects the row and
  shows nothing.
- **Toggle and close.** A real click on the badge while open closes it, and the next one opens it.
  A click on the ribbon, or `cv ax key escape`, closes it. `cv ax tree` has no `AXPopover` after.
- **Hide all.** Run `cv ax press "Hide all" stack`, then `cv ax press "Arrange the stack"`. The popover
  hangs under the ribbon (`cv ax windows` lists a 342x46 stack and the popover). `cv ax key opt+down`
  moves a card and the stack stays 342x46. `cv ax act "Beta card" AXPress` turns the stack to Beta
  and `cv ax windows` lists the stack at 342x267 again, the toggle still `Show all`, and the popover
  under the badge in the card's corner.
- **Live updates.** With the popover open run `cv ax press "↩ Stack" card=Gamma` after popping it
  with `cv ax press "↗ Pop" stack` first. A popped card returned joins at the top of `rows`, the
  current mark follows the shown card, and `↗ Pop` removes a row. Pop every stacked card: at zero
  the popover closes by itself.
- **Zero cards.** With nothing stacked, `cv ax tree` shows `AXButton "0" … [disabled]` and `cv ax
  press "Arrange the stack"` fails with `is disabled`. A real click on the badge opens nothing and,
  in the card's corner, puts the caret in the blank page under it.
- **Blank page.** Flip to the blank page (`cv ax click stack 0.015 0.6`) with cards stacked and press
  the badge: the top row is `[selected]` and no cell says `current card`.
- **Scrolling.** With 12 cards the popover is 10 rows tall and `AXTable` is taller than its
  `AXScrollArea`. Drag a grip to just above the list's bottom edge and hold for two seconds with
  `cv ax mouse drag` steps one point apart: the table's `y` in `cv ax tree` moves up, and a drop
  lands the card among the lower rows.

## Gotchas

- Open the popover before `cv ax listen`: it watches the elements that exist when it starts.
- A real click anywhere outside the popover closes it, including `cv ax click`, `focus` and a click
  on a button of the stack. `cv ax press` and keys do not, so use them for steps that must keep it open.
- `cv ax key` goes to the key window. While the popover is open that is the popover, so ⌥↑ moves a
  card instead of typing in the stack. Close it first to type.
- A drag needs the pointer to keep moving in small steps; `dragat` moves in 30 steps. A drop at the
  list's very edge counts as outside it: release a few points inside.
- `cv ax where` prints screen coordinates, the space `mouse` and `dragat` take.
- The grip's open-hand cursor, VoiceOver's speech, Tab reaching the badge and a click while Cards is
  inactive cannot be driven; report them as not verified.
