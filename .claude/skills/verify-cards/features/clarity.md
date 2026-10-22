# Clarity

Clarity collapses cards to their header and a two-line AI summary, at the same size and place.
The stack's Clarity button collapses or expands every card, stacked and popped. Each card's own
button collapses or expands just that card, and the card keeps its state when it moves.

## Sub-features

- `clarity-global-on` Clarity: Off → On collapses every card, the stacked one included.
- `clarity-global-off` Clarity: On → Off expands every card.
- `clarity-card` A card's collapse/expand button changes only that card, not the global button.
- `clarity-short-body` A card with an empty or one-line body shows that line instead of a summary.
- `clarity-no-key` Without an API key, a longer card shows `Summary unavailable`, with the reason
  on hover.
- `clarity-saved` Collapsed cards and the global state survive in the sidecar.

## How to get to it (user POV)

- `Clarity: Off` / `Clarity: On` in the stack's ribbon.
- The collapse button on a card (fades in on hover), and on the stack's shown card.
- Clicking a collapsed card's body expands it (not driven: use the button).

## Driving it with cards-verify

Preconditions:

- `cv launch --seed`; `cv doctor` prints `healthy`.
- Alpha shows on the stack, and Clarity reads `Clarity: Off`.

- **Global on.** Click Clarity. Run `cv ax press "Clarity: Off"`. `cv ax tree` shows the button
  as `Clarity: On`, no `AXTextArea` in the stack, and two static texts: `Alpha card` and
  `alpha body` (a one-line body shows itself). The card button reads `Expand this card`.
- **Longer body.** Flip to Beta. Run `cv ax click stack 0.985 0.6`. `cv ax tree` shows
  `Beta card` and either `Summary unavailable` (with `No Anthropic API key. Add one in
  Settings.` as its description) when no key is stored, or a summary once one arrives when a key
  is stored. `cv shot clarity-beta` shows the summary line lighter than the header.
- **One card.** Expand only Beta. Run `cv ax press "Expand this card" stack`. The stack's
  `AXTextArea` is back with Beta's text, the card button reads `Collapse this card`, and the ribbon
  still reads `Clarity: On`.
- **Saved.** Wait 1.5 s and run `cv files clarity`. The sidecar has `"clarity" : true` and
  `collapsed` lists `seed-a` only.
- **Global off.** Click Clarity again. Run `cv ax press "Clarity: On"`. The button reads
  `Clarity: Off`, every card is expanded, and after 1.5 s `cv files clarity-off` shows
  `"clarity" : false` and an empty `collapsed`.

## Gotchas

- The API key comes from the login Keychain at launch. On 2026-10-22 this machine had none, so
  Beta showed `Summary unavailable`. With a key stored, Beta first shows a spinner and then real
  text from the Anthropic API, which costs a request. Use Alpha (one body line) when a
  deterministic proof is enough.
- A collapsed card has no text area, so `cv ax text` prints nothing for it, and
  `card=<title>` finds it by its header text instead.
- The refresh button (`Refresh summary`) appears only on a collapsed card whose body wants a
  summary.
