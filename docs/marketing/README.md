# Marketing

Go-to-market working documents for **Riyaz by Dayby** (Instagram `@dayby`).

These are self-contained HTML pages — no build step, no dependencies, no network
calls beyond a Google Fonts stylesheet. **Open them straight in a browser:**

```sh
open docs/marketing/instagram-launch-ledger.html
open docs/marketing/profile-mark.html
```

They live in the repo rather than only as published Artifacts because an Artifact
is tied to the account that created it — switch accounts and the link dies. The
file is the source of truth; a published page is a disposable copy of it.

| File | What it is |
|------|-----------|
| `instagram-launch-ledger.html` | Profile copy (paste-ready), positioning, the 5 content pillars, 16 posts for the first 30 days, the automation stack, and a paid-ads plan held behind three gates |
| `profile-mark.html` | Four candidate profile marks rendered at 176/64/40/24px, with the reasoning for picking `◐`, plus a feed-size comparison against competitor avatars |

## Status

Nothing here has been executed yet. The launch ledger's own section 00 is the
part to read first: **there is no Play Store listing**, so sections 01–05
(profile, content, automation) are actionable now and section 06 (paid) is
deliberately locked until a real destination exists.

## Open decisions

1. **Export the Android icon set with `flutter_launcher_icons`?** It is a dev
   dependency, and `CLAUDE.md` forbids adding a package unasked. The alternative
   is exporting the five `mipmap` PNGs by hand — slower, but `pubspec.yaml` stays
   untouched.
2. **Landing page.** The bio needs a destination before it needs followers. An
   email-capture page is roughly an hour of work and gates the whole content plan.

See `../brand/` for the mark itself and its production spec.
