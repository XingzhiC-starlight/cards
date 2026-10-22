# Cards — prototype spec (agreed 2026-10-21, revised 2026-10-22)

Personal-use macOS prototype. Native Swift app built with Xcode.

## Windows and layering
- Each card is a real macOS window on the normal window layer (not always-on-top, not desktop-pinned).
- Cards behave as one group: clicking any card brings all cards forward; clicking another app drops them all behind it.
- Clicking a card activates the app and takes keyboard focus. Return to other apps the normal way (click or ⌘-Tab).
- Cards follow the user across Spaces and over full-screen apps.
- App home: menu bar icon with Show all / Hide all / Open stack / Quit. Global shortcut ⌥⌘C hides/shows every card.

## Hide all (revised 2026-10-22)
- Hide all (menu bar icon, the stack's menu, or ⌥⌘C) hides every popped card, free ones included, and shrinks the stack to just its blue ribbon, at the top of wherever the stack is. The ribbon never hides.
- While hidden, the ribbon keeps New, Pop, Clarity, the count badge and the menu button; the menu offers Show all. The ribbon can still be dragged.
- Show all, ⌥⌘C, or opening the app again (Spotlight, Finder, Launchpad) while it runs brings back the stack's card area and every popped card, and brings the app forward.
- New or Pop while hidden shows only that card; the rest stay hidden. Its slot is chosen as if the hidden cards were in place, free ones included.
- Hidden is not persisted: every launch starts with everything shown.

## Grid and sizing
- Screen is an invisible 5 × 4 grid. Card width = screen width / 5; height = (screen height below menu bar) / 4.
- 20 equal slots. The stack takes one (top-left by default), so at most 19 cards are on the desktop.
- Recomputed when the display setup changes; snapped cards re-snap to their slots, free cards and a free stack keep their place as a fraction of the screen (revised 2026-10-22).

## Stack
- Its own card-sized window, top-left until you move it: the control center, marked by a sky-blue ribbon on top.
- Moved like a card (see Moving cards and the stack), by pressing the ribbon's empty space and dragging. A click there that does not move still acts as the edge band under it.
- Looks like one card: the ribbon holds the toolbar and a count badge; below it, the selected stacked card (header and body). No list or divider for the cards underneath.
- Toolbar: New, Pop, Clarity on/off (global), and a menu button with Show all / Hide all / Settings… / Quit, so the control center works even when the menu bar icon is hidden.
- The selected stacked card is a full card (revised 2026-10-22): edited in place exactly like a popped card (see Card content and editing), with the same per-card buttons except ↩ Stack, and collapsible to its summary (see Clarity mode).
- Deleting the selected card shows the one underneath.
- At launch the stack shows its top card, or the blank page when the stack is empty.
- The count badge counts real cards only, never the blank page.

## Pop / return / find space
- Pop takes the first grid slot (left→right, top→bottom) not taken by a card or the stack. A snapped card or stack takes its slot; a free one takes the slot it covers most. Other apps' windows are ignored.
- No slot left, or 19 cards already on the desktop → Pop refuses and the stack shows "Desktop full".
- Pop is disabled while the blank page shows.
- Popping the card being edited on the stack moves the cursor with it; the stack then shows the next card.
- "↩ Stack" button returns a card to the top of the stack. It forgets where the card was; a later Pop takes the first free slot.

## Moving cards and the stack (new 2026-10-22)
- Drag a card by its header, or the stack by its ribbon's empty space.
- While dragging, a guide outlines the slot nearest the dragged card's center: faint and dashed while a drop would stay free, solid and filled in once a drop would snap.
- On release it snaps to that slot if its center is within 15% of a cell (in cell widths and heights) of the slot's center. Otherwise it stays exactly where it was dropped.
- Snapping onto a slot held by another snapped card or the stack swaps them: the occupant goes to the dragged one's old place, a slot or an exact free spot. Free cards that only overlap the slot stay put.
- Free cards overlap anything. The card being dragged comes to the front; clicking the app keeps the cards' front-to-back order.
- A drop always ends fully on screen: a card dropped past an edge slides back in.
- Free positions are saved, so they survive relaunch.

## Switching stacked cards (stack only; revised 2026-10-22)
- Purpose: show the cards hidden under the stack.
- The stack is a loop. Next sends the selected card to the bottom and shows the one under it; previous brings the bottom card back up.
- The loop always holds one blank page, after the last card and before the first.
- Two-finger horizontal swipe on the stack: one card per swipe, next or previous following the system scroll direction. Vertical scroll scrolls the selected card's text.
- Edge bands stay as a click alternative: an invisible band = 5% of the stack's width/height along all four edges. Right/bottom = next, left/top = previous. On hover the band tints faintly and shows ‹ or ›. Popped cards have no bands.
- Because of the blank page, swiping and the bands work with any number of stacked cards, including zero or one.
- Pop takes the selected card.

## Blank page (new 2026-10-22)
- Typing its first character turns it into a real card in the same place in the loop (the bottom of the stack). The card stays selected with the cursor in it, and a new blank page appears right after it.
- Left untouched, it creates nothing.
- Always expanded, even with Clarity ON. No per-card buttons until it becomes a card.

## Card content and editing
- Applies to popped cards and to the selected stacked card alike.
- First line (first paragraph) is automatically the bold level-1 header, regardless of formatting.
- Body formatting: bold, italic, bullet list, numbered list, checkboxes. Nothing else.
- Apply via ⌘B / ⌘I; typing `- `, `1. `, `[] ` starts lists; Enter continues a list, Enter on an empty item ends it.
- A five-button formatting bar appears along the bottom of a card only while editing.
- Scroll wheel/trackpad scrolls whichever card the pointer is over. The card being edited has a stronger border.
- Per-card buttons (clarity toggle, summary refresh, ↩ Stack, trash) fade in on hover only. Trash asks "Delete this card?". The stacked card has all of them except ↩ Stack.
- New: creates a blank card and pops it straight out, cursor on the header line, always expanded. Desktop full → New shows the stack's blank page instead.

## Clarity mode
- Collapsed card: same size and position, header stays, body replaced by the 2-line AI summary in a lighter style. Applies on the stack too.
- Stack's Clarity button is a global toggle: ON collapses every card, stacked ones included; OFF expands every card.
- Clicking a collapsed card's body expands just that card and puts the cursor in it; does not flip the global button.
- Per-card button toggles just that card.
- A card popped keeps its state, so a card popped while global is ON comes out collapsed.

## AI summaries
- Provider: Anthropic API, model Claude Haiku 5.5. API key pasted once into the app's settings, stored outside the code.
- Every card gets one, stacked or popped, under the same rules.
- Trigger: a few seconds after typing stops; cached with the card; regenerated only on content change; per-card refresh button.
- No summary for empty or one-line bodies.
- Prompt: header + body in → at most two short sentences (~25 words), no preamble, same language as the card.
- While generating: small spinner in the summary area. On failure: "Summary unavailable", hover shows the reason.

## Storage
- One Markdown (.md) file per card in ~/Documents/Cards/.
- One hidden sidecar file for positions (each card's and the stack's slot or free spot), stack order, collapsed state, and cached summaries.

## Look
- Neutral light cards, thin border, soft shadow, system font. Per-card colors later.

## Explicitly out of scope for the prototype
- Always-on-top mode, drag-to-stack, fonts/colors/sizes/tables/images/links, multiple stacks, sync, sharing.
