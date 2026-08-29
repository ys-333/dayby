# Brand marks

Design sources, not Flutter assets. Nothing here is declared in `pubspec.yaml`
and nothing ships in the APK — the launcher icon is exported from these into
`android/app/src/main/res/mipmap-*/`.

## The mark

`◐` — a circle with its left half filled. It is the app's own **partial**
status glyph at full size. Every other tracker's icon means "done"; this one
means "half counts", which is the product's whole argument.

### The chosen mark

| File | Canvas | Use |
|------|--------|-----|
| `icon-partial.svg` | 320×320 | vector source — the mark on its own field |
| `icon-adaptive-foreground.svg` | 432×432 | Android adaptive-icon **foreground layer** — no field; pair with a `#3F6C51` background layer |
| `png/icon-partial-320.png` | 320×320 | Instagram avatar (its stated minimum) |
| `png/icon-partial-512.png` | 512×512 | Play Store listing icon |
| `png/icon-partial-1080.png` | 1080×1080 | upload-anywhere master; downsample rather than re-render |

### The rejected candidates

Kept because each still has a job, and because a rejected mark you can look at
is worth more than a memory of one. All three exist as `.svg` plus PNGs at
320 / 512 / 1080.

| Mark | Why it lost | Where it is still used |
|------|-------------|------------------------|
| `mark-honest-grid` | Nine days, one skipped, one not yet. The dash and the outline cell carry the whole meaning and are the first things to vanish below ~40px, leaving a generic grid | *Why* highlight cover; carousel slide 1 motif |
| `mark-return` | A broken ring with a dot re-entering — recovery, drawn. Nobody decodes it unaided, and it reads as a loading spinner | *Build* highlight cover; any post about recovery time |
| `mark-d-bowl` | A `d` whose bowl is the ◐. The stem pushes the bowl off-centre, which crowds Android's adaptive mask, and it anchors the identity to *Dayby* rather than *Riyaz* | wordmark lockup — landing page footer, Play Store feature graphic |

**Nothing outside this folder consumes the SVGs directly.** Social platforms and
app stores take PNG only — Instagram rejects SVG uploads. Regenerate every PNG
with `sh docs/brand/render.sh` after any change to a mark.

## Constants

| Token | Value | Note |
|-------|-------|------|
| Field | `#3F6C51` | the `ColorScheme` seed in `lib/app/app.dart` — keep these in sync |
| Figure | `#F1F3EF` | deliberately not pure white; matches the app surface and sits better on the green |
| Ring | r=98, stroke 26 | on a 320 canvas, scales linearly |

## Export targets

| Target | Size | Note |
|--------|------|------|
| Android launcher | 432×432 adaptive | foreground art must stay inside the 264px safe circle — the `scale(0.75)` in the file is what guarantees that |
| Play Store listing | 512×512 PNG | 32-bit, **no alpha**, no rounded corners — Google applies them |
| Instagram avatar | 320×320 PNG | upload square; Instagram applies the circle crop |

Always check the mark at **24px** before changing it. That is the comment-thread
size, and it is where detail dies.
