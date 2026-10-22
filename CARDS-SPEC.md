# Cards — prototype spec (agreed 2026-10-21)

Personal-use macOS prototype. Native Swift app built with Xcode.

## Windows and layering
- Each card is a real macOS window on the normal window layer (not always-on-top, not desktop-pinned).
- Cards behave as one group: clicking any card brings all cards forward; clicking another app drops them all behind it.
- Clicking a card activates the app and takes keyboard focus. Return to other apps the normal way (click or ⌘-Tab).
- Cards follow the user across Spaces and over full-screen apps.
- App home: menu bar icon with Show all / Hide all / Open stack / Quit. Global shortcut ⌥⌘C hides/shows every card.

## Grid and sizing
- Screen is an invisible 5 × 4 grid. Card width = screen width / 5; height = (screen height below menu bar) / 4.
- 20 slots: 19 for cards, 1 (top-left) for the stack.
- Recomputed when the display setup changes; cards re-snap to their slots.

## Stack
- Its own card-sized window in the top-left slot: the control center, marked by a sky-blue ribbon on top.
- Looks like one card: the ribbon holds the toolbar and a count badge; below it, the selected stacked card (header and body). No list or divider for the cards underneath.
- Toolbar: New, Pop, Clarity on/off (global).

## Pop / return / find space
- Pop takes the first grid slot (left→right, top→bottom) not occupied by another card. Other apps' windows are ignored.
- All slots full → Pop refuses and the stack shows "Desktop full".
- Drag a card by its header; on release it snaps to the nearest slot, swapping with the occupant if any.
- "↩ Stack" button returns a card to the top of the stack.

## Edge switching (stack only; revised 2026-10-21)
- Only the stack window has edge bands: an invisible band = 5% of its width/height along all four edges. Popped cards have none.
- Purpose: show the cards hidden under the stack.
- Select a card with the bands, then operate on it: right/bottom band click → the selected card goes to the bottom and the next one shows; left/top → the bottom card comes back up. A loop.
- Pop takes the selected card.
- On hover the band tints faintly and shows ‹ or ›. Fewer than two stacked cards → bands do nothing.

## Card content and editing
- First line (first paragraph) is automatically the bold level-1 header, regardless of formatting.
- Body formatting: bold, italic, bullet list, numbered list, checkboxes. Nothing else.
- Apply via ⌘B / ⌘I; typing `- `, `1. `, `[] ` starts lists; Enter continues a list, Enter on an empty item ends it.
- A five-button formatting bar appears along the bottom of a card only while editing.
- Scroll wheel/trackpad scrolls whichever card the pointer is over. The card being edited has a stronger border.
- Per-card buttons (clarity toggle, ↩ Stack, trash) fade in on hover only. Trash asks "Delete this card?".
- New: creates a blank card and pops it straight out, cursor on the header line, always expanded.

## Clarity mode
- Collapsed card: same size and position, header stays, body replaced by the 2-line AI summary in a lighter style.
- Stack's Clarity button is a global toggle: ON collapses every popped card; OFF expands every card.
- Clicking a collapsed card's body expands just that card; does not flip the global button.
- Per-card button toggles just that card.
- A card popped while global is ON comes out collapsed; otherwise its last state.

## AI summaries
- Provider: Anthropic API, model Claude Haiku 5.5. API key pasted once into the app's settings, stored outside the code.
- Trigger: a few seconds after typing stops; cached with the card; regenerated only on content change; per-card refresh button.
- No summary for empty or one-line bodies.
- Prompt: header + body in → at most two short sentences (~25 words), no preamble, same language as the card.
- While generating: small spinner in the summary area. On failure: "Summary unavailable", hover shows the reason.

## Storage
- One Markdown (.md) file per card in ~/Documents/Cards/.
- One hidden sidecar file for slot positions, stack order, collapsed state, and cached summaries.

## Look
- Neutral light cards, thin border, soft shadow, system font. Per-card colors later.

## Explicitly out of scope for the prototype
- Always-on-top mode, free-form placement, drag-to-stack, fonts/colors/sizes/tables/images/links, multiple stacks, sync, sharing.
