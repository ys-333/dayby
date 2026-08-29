# Design

The **Riyaz Redesign** canvas — five artboards drawn on 2026-08-30, covering a
design system and four screens. Design sources, not Flutter assets. Nothing
here is declared in `pubspec.yaml` and nothing ships in the APK.

They live in the repo rather than only as a published Artifact because an
Artifact is tied to the account that created it — switch accounts and the link
dies. Same reasoning as `../marketing/`. **The files are the source of truth;
the published page is a disposable copy.**

## The artboards

| File | Board | Status |
|------|-------|--------|
| `Tokens.dc.html` | Design system | **implemented** — `lib/app/theme/` |
| `Main.dc.html` | Today | not implemented |
| `Week.dc.html` | History / Week | **implemented** — period rows only |
| `Insights.dc.html` | Insights (full scroll) | **partly** — the advice card |
| `Detail.dc.html` | Commitment detail | not implemented |

`canvas.json` holds the layout and, more importantly, the **annotations** — one
per board, stating what problem it solves. Read those before reading any
markup; they are the argument, and the markup is only the evidence.

## Viewing them

These are `.dc.html` canvas artboards, not standalone pages — unlike
`../marketing/`, **they do not open in a browser.** Each references a
`./support.js` (the `DCLogic` base class and the `{{...}}` template engine)
that the canvas host supplies and that is not in this repo.

What they *are* is complete and readable: every colour, dimension, string and
piece of interaction logic is inline in the file. `Main.dc.html` carries a
working Today screen — tap a row and it toggles, bump a weekly target and the
pips fill.

To see them rendered, open the published canvas:
<https://claude.ai/code/artifact/4f56407b-417e-49b6-bbaf-ade92b601c1a>

To read them without it, read the markup. It is hand-written and ordinary.

## What shipped, and what did not

Only the design system board was built, in two commits — `415d3a1` moved status
colour into its own token vocabulary without changing a pixel, then `c9e7e13`
changed the values.

The ground, ink, line and heat-ramp values shipped **verbatim** (`#14120E`,
`#1B1915`, `#23201B`, `#2C2924`, `#F2EEE6`, the five-step ramp, and the light
triple). The status accents did not, and the divergence is deliberate:

| Status | Board | Shipped (dark) | Shipped (light) |
|--------|-------|----------------|-----------------|
| sage · done | `#8FB39A` | `#A2C6AD` | `#18462A` |
| ochre · partial | `#C0A46B` | `#C7A45A` | `#6D5100` |
| clay · missed | `#B58573` | `#AD7E6C` | `#9F5B45` |

The board picked three hues at roughly equal lightness. Measured, that collapses
to OKLab ΔE 3.0 under deuteranopia — partial and missed become the same brown.
They were re-solved as a lightness ladder running in the direction the statuses
mean. See `lib/app/theme/palette.dart` and `test/app/theme/palette_test.dart`,
which holds the maths.

**The four screen boards are unbuilt.** Three of the "still open after the
device pass" items in `../PROGRESS.md` — the FAB covering the last row, the
~180px greeting, daily and period rows carrying identical weight — are the Today
board's agenda. It answers them; nothing has acted on it.

## The six principles

From the foot of `Tokens.dc.html`, and the part most worth keeping if
everything else here rots:

1. A practice journal, not a dashboard. Warm ground, one voice for language and
   one for numbers.
2. **No red anywhere.** The strongest negative is clay, reserved for a closed,
   missed day.
3. **Daily and period commitments never share a group.** A weekly target cannot
   be late today, so it never sits in a list of things that can.
4. **The day's headline counts down to zero.** A percentage of today is a
   verdict; a count of what is left is a task.
5. The future is outline only. Nothing unlived is drawn as a failure.
6. Skips are shown, never hidden, and never struck through — a skip is a
   decision, not a deletion.

Points 5 and 6 restate rules `CLAUDE.md` already carries. Points 2 and 3 are the
ones with teeth: 2 shipped, 3 has not.

## Type, and an open decision

The board specifies **Newsreader for language only** — the day's headline,
insight sentences, screen titles — with the device sans for every number,
including the big ones, and `FontFeature.tabularFigures()` wherever numbers
align in a column. A serif figure reads as decoration.

It also settles *how*: a bundled `pubspec.yaml` `fonts:` entry, one weight, an
asset rather than a package. **Never `google_fonts`** — runtime fetching is the
wrong shape for an app that is offline-first by design.

This is still unbuilt, and the blocker is recorded in `../PROGRESS.md`: the
decision rested on "one weight, ~50–80KB", and Google ships Newsreader only as a
451KB variable font with no subsetting tool on this machine. The app currently
renders entirely in the device sans, so every serif on every board is
unrepresented in the build.
