# TODO — closing the redesign

What is left to finish Riyaz's UI end to end, in the order the dependencies
allow. `docs/PROGRESS.md` records what is **done and how it was verified**;
this file records what is **next**. Update both in the same commit as the work.

Status marks follow the ledger's rules:
`[ ]` not started · `[!]` built but unverified, nothing may be built on it ·
`[x]` done **with evidence** — a test, a migration, a build, or a device run.

---

## 0. Blocked on you — nothing moves until these are answered

- [ ] **Icon vocabulary.** The Today board replaces the emoji with eight
      monochrome stroked glyphs. The device pass agreed: full-colour emoji are
      now the loudest thing on a deliberately muted screen.
      **The catch:** `Commitment.icon` is a `String` written by the add screen
      and serialised into the backup format (`backup_codec.dart:49,181`), so
      this is a data migration over existing rows *and* old backups — not a
      repaint. Answer needed: keep emoji, replace them, or allow both.
      **Blocks phase 3.**
- [ ] **Newsreader.** Specified by the Tokens board (serif for language, sans
      for all numbers, one bundled weight, never `google_fonts`). Google Fonts
      ships it *only* as a 451KB variable font and there is no subsetting tool
      on this machine. Two agents disagree; it is your call. Blocks nothing.
- [ ] **Export destination.** Reaching Downloads or a share sheet needs
      `file_picker` or `share_plus` — a new dependency, which needs your yes.

---

## 1. Commitment detail — the only board whose gap is missing *function*

The screen has no edit, no pause, no archive. A user who abandons a commitment
has no way out of a list that only grows.

The data layer is further along than it looks:
`TrackingRepository.pauseCommitment()` (`:292`) and `.setState()` (`:306`)
already exist and have **zero callers**. The engines already honour both —
`resolution.dart:86`, `today_controller.dart:45`, `week_grid.dart:78`.

- [x] **Archive and unarchive** — `unit`, `widget`. Overflow menu, undo, and a
      banner that says history is kept. `archive_test.dart` asserts every
      resolved status and credit is byte-identical across an archive; checked
      non-vacuous by making archived history drop out of resolution.
- [ ] **Pause and resume.** Wire `pauseCommitment()`. Paused days are
      `NOT_EXPECTED`, never misses — assert that in the same commit.
      **Two traps found while building archive.** `CommitmentState.paused` has
      *zero* references in the whole codebase — the engines read `PausePeriods`
      exclusively (`recurrence_engine.dart:34`, `accounting_engine.dart:162`).
      Wiring Pause to `setState(paused)` would look right and silently do
      nothing, leaving the engine still expecting occurrences and marking them
      MISSED. And `PausePeriod.to` is non-null, so "pause until I resume" needs
      either a sentinel far-future date or a nullable column — a **schema v3
      migration**. Decide which before building.
- [ ] **Edit.** The only one missing end to end: there is no
      `updateCommitment` on the repository at all. Name, icon, description.
      Schedule edits must stay **effective-dated** — changing a frequency must
      not alter historical consistency.
- [ ] **The board's layout.** Fifteen stats and thirty undated circles become
      one lead figure and a *dated* twelve-week grid. Cosmetic; do it after
      the three actions work.

## 2. The icon migration — after §0 is answered

- [ ] Decide the mapping for rows that already hold an emoji.
- [ ] Migrate the stored values; old backups must still import.
- [ ] Replace the picker in `add_commitment_screen.dart`.

## 3. Today — the biggest board, and the biggest visible win

Downstream of §2: rehoming the FAB while the icons change underneath is two
migrations tangled together.

- [ ] Headline counts **down to zero** instead of scoring you.
- [ ] Weekly targets move to their own group — a 3×/week target cannot be late
      on a Tuesday and must not sit among things that can.
- [ ] Drop the greeting (~180px) and the FAB that covers the last row. Dropping
      the FAB means rehoming add-commitment.

## 4. Close-out

- [ ] **Rollup logic version.** Fold `timezoneName`, `dayBoundaryHour` and
      `weekStartsOn` into `_logicVersion` (`rollup_repository.dart:48`).
      **Latent, not live** — `appSettings` is a hardcoded constant with no
      runtime source, so nothing can change these today. One line, as
      insurance for the day the timezone becomes device-derived.
- [ ] Period-close review UI — what the user sees when a week ends. Designed
      away rather than built; there is no moment-of-closure summary.
- [ ] The remaining raw `scheme.*` call sites (~20 `onSurfaceVariant`, plus
      `TrendChart`'s line and grid). Low priority — they resolve correctly
      today. The legend bug is the argument for eventually finishing.

---

## Device checks — only you can sign these off

Claude certifies "logic verified". "Feel verified" is a separate claim and
Claude never makes it.

- [ ] **Feel check:** create and track in under 10 seconds on a real phone.
- [ ] **Widget device check:** place it, confirm it renders, updates, and that
      tapping opens the app. The Kotlin has never executed.
- [ ] Week grid and Insights on a device — built, never seen on hardware.
- [ ] Decide whether light mode's near-black "strong" day reads as *best* or
      merely as *different*. Dark mode's equivalent is a light mint.

---

## Working notes

- **Stacked PRs merge base-first**, or the top of the stack is orphaned. This
  has now stranded work twice: `b51e490` on `brand/instagram-launch`, and all
  of PR #5, which merged into `docs/design-canvas` after that branch had
  already reached `main`.
- `git push` needs the ys-333 credential; the active `gh` account 403s.
- `flutter` and `JAVA_HOME` are not on the login PATH. See `CLAUDE.md`.
