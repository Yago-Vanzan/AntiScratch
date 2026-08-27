# AntiScratch

<p align="center">
  <img src="docs/antiscratch-paper.png" width="310" alt="AntiScratch using the Paper theme">
</p>

<p align="center">
  A tiny, native scratchpad for macOS — always one shortcut away.
</p>

AntiScratch is a keyboard-first place for thoughts, quick calculations, checklists and timers. It is built entirely with SwiftUI, keeps notes on your Mac and stays out of the way until you press <kbd>⌥ A</kbd>.

## Highlights

- Native macOS app with a compact, fixed-size window
- Global <kbd>⌥ A</kbd> shortcut and menu bar access
- Horizontal swipe between an ordered stack of notes
- Automatic local persistence — no account and no cloud
- Inline math, variables, percentages and unit conversions
- Checklists, totals, averages, counters and timers
- Mint, Aubergine and Paper themes
- Optional Dock icon

## Smart note modes

Start the first line with a command followed by `:`.

```text
math:
price: 120
price + 15% = 138
10 km to mi = 6.213712 mi
```

| Command | What it does |
| --- | --- |
| `math:` | Calculates expressions after `=` and supports variables, percentages and conversions |
| `list:` | Return creates a checkbox; Backspace on an empty item removes it |
| `sum:` | Adds every number in the note |
| `avg:` | Shows the average of every number |
| `count:` | Counts lines, words and characters |
| `timer: 5m` | Starts a countdown; `timer:` without a duration is a stopwatch |

Lines beginning with `//` are ignored by aggregate modes.

## Install

1. Download `AntiScratch-1.0.0.dmg` from the [latest release](../../releases/latest).
2. Drag AntiScratch to Applications.
3. On first launch, right-click the app and choose **Open**. The public build is ad-hoc signed and is not notarized by Apple yet.

Requires macOS 14 Sonoma or newer.

## Build from source

```bash
git clone https://github.com/Yago-Vanzan/AntiScratch.git
cd AntiScratch
open AntiScratch.xcodeproj
```

To create the same distributable DMG:

```bash
./scripts/build-dmg.sh
```

The output is written to `dist/AntiScratch-1.0.0.dmg`.

## Privacy

Notes are encoded and stored in the app's local `UserDefaults` container. AntiScratch has no analytics, account system or network code.

## Project status

This is an independent open-source project inspired by the immediacy of disposable scratchpads. It is not affiliated with AntiNote or its developers.

## License

MIT © Yago Vanzan
