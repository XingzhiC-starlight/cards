# Browse the stack

The stack shows one card at a time. A user flips to the next or previous card with a two-finger
horizontal swipe or a click in the invisible band along the stack's edges. The stack is a loop
with one blank page after the last card. Pop brings the shown card out onto the desktop, ↩ Stack
on a popped card puts it back on top, and the corner badge counts the stacked cards.

## Sub-features

- `stack-next` The right or bottom band, or a swipe, shows the card underneath.
- `stack-previous` The left or top band, or the opposite swipe, goes back.
- `stack-loop` After the last card comes the blank page, then the top card again.
- `stack-pop` Pop moves the shown card to the first free slot; the stack shows the next one.
- `stack-pop-disabled` Pop is disabled on the blank page.
- `stack-return` ↩ Stack puts a popped card on top of the stack, and the stack shows it.
- `stack-count` The badge counts real cards only, never the blank page.

## How to get to it (user POV)

- Two-finger horizontal swipe over the stack (or a horizontal mouse wheel).
- Click within the outer 5% of the stack window: right or bottom = next, left or top = previous.
- `Pop` in the stack's ribbon.
- `↩ Stack` on a popped card (it fades in on hover).

## Driving it with cards-verify

Preconditions:

- `cv launch --seed`; `cv doctor` prints `healthy`.
- `cv ax text stack` prints `"Alpha card\nalpha body"` and the `Cards in the stack` value is 2.

- **Next by band.** Click the right band. Run `cv ax click stack 0.985 0.6`. `cv ax text stack`
  prints `"Beta card\nbeta line one\nbeta line two"`.
- **Blank page.** Click the right band again. Run `cv ax click stack 0.985 0.6`. `cv ax text
  stack` prints `""`, `Pop` shows `[disabled]` in `cv ax tree`, and the badge still reads 2.
- **Wrap.** Swipe to the next page. Run `cv ax scroll stack -40 0`. `cv ax text stack` prints
  the Alpha card again.
- **Previous.** Click the left band. Run `cv ax click stack 0.015 0.6`. The blank page shows.
  Run `cv ax scroll stack 40 0`. The Beta card shows.
- **Pop.** With Beta showing, click Pop. Run `cv shot stack-before-pop`, then `cv ax press Pop`.
  `cv ax tree` shows a card window at the top-left cell (`@0,39` on the owner's display) whose text
  is the Beta card. The stack shows the blank page (Beta was last), and the badge reads 1.
- **Pop saved.** Wait 1.5 s and run `cv files stack-pop`. The sidecar's `placements` holds
  `seed-b` at `"slot" : 0`, and `stack` is `["seed-a"]`. The `.md` files are unchanged.
- **Return.** Click ↩ Stack on the popped card. Run `cv ax press "↩ Stack" card=Beta`. The card
  window is gone from `cv ax tree`, `cv ax text stack` prints the Beta card, and the badge reads 2.
  `cv shot stack-after-return` shows it on the stack.
- **Return saved.** Wait 1.5 s and run `cv files stack-return`. `placements` is empty and `stack`
  is `["seed-b", "seed-a"]`: the returned card is on top.

## Gotchas

- `scroll` sends a mouse-wheel event, which flips once per event. A real trackpad swipe goes
  through phases and momentum; this skill cannot produce one, so report the trackpad path as
  unverified unless a person swiped.
- Flipping never reorders the stack: `stack` in the sidecar changes only on Pop, ↩ Stack, New
  and delete. A flip alone writes nothing.
- The bands are 5% of the window. `0.985` and `0.015` stay inside them on any display; `0.95`
  can miss.
- While Hide all is on, bands and swipes do nothing (see [Hide all](./hide-all.md)).
