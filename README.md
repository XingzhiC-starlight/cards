# Cards

A macOS prototype where every note is its own small window, laid out on an invisible 5 × 4 grid,
with a stack of the rest in the top-left corner. Native Swift and AppKit, no dependencies.
The behaviour is specified in [CARDS-SPEC.md](CARDS-SPEC.md); how the code is put together is in
[DESIGN.md](DESIGN.md).

Requires macOS 15 or later and Xcode 26.

## Open and run in Xcode

1. Open `Cards.xcodeproj`.
2. Pick the **Cards** scheme and **My Mac** as the destination.
3. Press **⌘R**.

Cards is a menu bar app, so it has no Dock icon. Look for the stacked-rectangles icon in the menu
bar: it has Show All, Hide All, Open Stack, Settings… and Quit. **⌥⌘C** hides or shows every card
from anywhere. Hide All leaves the stack's blue ribbon in the top-left corner, so New, Pop, Clarity
and the menu stay in reach. Opening Cards again from Finder or Spotlight shows everything.

On a MacBook with a crowded menu bar, macOS may hide the icon behind the camera notch. The same
menu is on the stack: click **⋯** at the right of its blue ribbon.

## Build from the command line

```bash
xcodebuild -project Cards.xcodeproj -scheme Cards -configuration Debug -derivedDataPath build/DerivedData build
```

```bash
open build/DerivedData/Build/Products/Debug/Cards.app
```

Run the unit tests (they use the app as their host and never touch `~/Documents/Cards`):

```bash
xcodebuild test -project Cards.xcodeproj -scheme Cards -derivedDataPath build/DerivedData
```

## Where to paste the API key

Summaries use the Anthropic API (model `claude-haiku-5-5`). Click the menu bar icon (or **⋯** on
the stack's blue ribbon), choose **Settings…**, paste your key into **Anthropic API key**, and click **Save**.

The key is stored in your login Keychain (service "Cards"), never in the project or the notes
folder. Without a key everything works; collapsed cards just say "Summary unavailable". Debug
builds are not signed with a stable identity, so after a rebuild macOS may ask once whether Cards
may read its Keychain item; choose **Always Allow**.

## Where notes live

Each card is a Markdown file in `~/Documents/Cards/`. Slot positions, stack order, collapsed
state and cached summaries live in the hidden file `~/Documents/Cards/.cards.json`. To try the app
against another folder, pass `-CardsFolder /path/to/folder` as a launch argument (in Xcode: Product
› Scheme › Edit Scheme › Run › Arguments).

## Using it

| To | Do |
| --- | --- |
| Make a card | **New** on the stack, or type on the stack's blank page |
| Select a stacked card | Swipe left or right with two fingers on the stack, or click the thin band along its edge: right/bottom = next, left/top = previous |
| Edit a stacked card | Click into it on the stack; it edits like any other card |
| Bring a card out | Select it, then click **Pop** in the stack's blue ribbon |
| Move a card | Drag it by its title; it snaps to the nearest cell and swaps with whatever is there |
| Put a card back | Hover it and click **↩ Stack** |
| Collapse to a summary | Hover a card and click the collapse button, or use **Clarity** on the stack for every card |
| Format | ⌘B, ⌘I, or start a line with `- `, `1. ` or `[] `; the bar at the bottom of the card has the same five actions |

The stack is a loop with one blank page after the last card. Swiping past the last card shows the
blank page, and swiping once more shows the top card again. Typing on the blank page makes a new
card at the bottom of the stack; leaving it empty makes nothing.
