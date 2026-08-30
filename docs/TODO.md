# TODO — closing the redesign

What is left to finish Riyaz's UI end to end, in the order the dependencies
allow. `docs/PROGRESS.md` records what is **done and how it was verified**;
this file records what is **next**. Update both in the same commit as the work.

Status marks follow the ledger's rules:
`[ ]` not started · `[!]` built but unverified, nothing may be built on it ·
`[x]` done **with evidence** — a test, a migration, a build, or a device run.

---

## 0. Decisions — answered

All three were answered on 2026-08-30. Kept here as the record of what was
decided and why, because each one closed off an alternative.

- [x] **Icon vocabulary — replace the emoji.** Eight monochrome stroked glyphs,
      as the Today board specifies. `Commitment.icon` is a `String` written by
      the add screen and serialised into the backup format
      (`backup_codec.dart:49,181`), so this is a data migration over existing
      rows *and* old backups. See §2 for what that costs.
- [x] **Newsreader — skipped.** Google Fonts ships it only as a 451KB variable
      font with no subsetting tool on this machine, and the board's own rule
      (sans for every number) leaves the serif covering a handful of strings.
      451KB does not buy a fix for anything the device pass found. The app
      stays on the device sans; every serif on every board is unrepresented in
      the build, deliberately.
- [x] **Export destination — no new package.** Export stays on the app's
      documents directory plus the clipboard. Android Auto Backup remains the
      lost-phone story. A user who wants their data off the device by hand
      still cannot get it, and that is the accepted cost.

---

## 1. Commitment detail — the only board whose gap is missing *function*

The screen has no edit, no pause, no archive. A user who abandons a commitment
has no way out of a list that only grows.

The data layer is further along than it looks:
`TrackingRepository.pauseCommitment()` (`:292`) and `.setState()` (`:306`)
already exist and have **zero callers**. The engines already honour both —
`resolution.dart:86`, `today_controller.dart:45`, `week_grid.dart:78`.

- [x] **Archive and unarchive** — `unit`, `widget`. Overflow menu, undo, and a
      banner that says history is kept. Archiving **closes the schedule** at
      the archive date; the flag alone is invisible to `lib/domain/` and left
      the commitment accruing a miss a day forever (measured 49 of 49). Tests
      resolve *past* the archive date, which is what the first pair failed to
      do.
- [ ] **Pause and resume.** Wire `pauseCommitment()`. Paused days are
      `NOT_EXPECTED`, never misses — assert that in the same commit.
      **Two traps found while building archive.** `CommitmentState.paused` has
      *zero* references in the whole codebase — the engines read `PausePeriods`
      exclusively (`recurrence_engine.dart:34`, `accounting_engine.dart:162`).
      Wiring Pause to `setState(paused)` would look right and silently do
      nothing, leaving the engine still expecting occurrences and marking them
      MISSED. And `PausePeriod.to` is non-null, so "pause until I resume" needs
      a **nullable column, schema v3** — decided; a far-future sentinel would
      leak into `PauseCoverage.covers`, into calendar arithmetic, and into the
      backup file that `backup_codec.dart` keeps human-readable precisely so a
      damaged one can be repaired by hand.
      Real cost, all of it in the format contract rather than the column:
      bump `BackupDocument.currentVersion`; teach `_readPause` to accept a
      null `to` while still reading old files; write `"to": null` explicitly
      rather than omitting the key; `covers()` becomes
      `date >= from && (to == null || date <= to)`; enforce **at most one open
      pause per commitment**, closing any open one when a new pause starts;
      and give resume the `markStale(from)` that only the create path has
      today. `TableMigration` rebuild — SQLite cannot drop NOT NULL in place.
      `_resolutionVersion` does **not** move: the rule is unchanged, only the
      data.
- [x] **Edit** — `unit`, `widget`. `updateCommitment` is effective-dated: the
      version in force closes the day before the change, a new one opens on
      it, and the past keeps the rules it was lived under. Tests resolve
      *across* the change date in both directions; verified non-vacuous by
      forcing an in-place rewrite, which fails three of them.
      The "amend or version when there is no history" question resolved
      itself: a schedule already beginning on or after the change date **must**
      be amended, because closing it the day before would leave a version
      whose end precedes its start. Not a taste call after all.
- [ ] **The board's layout.** Fifteen stats and thirty undated circles become
      one lead figure and a *dated* twelve-week grid. Cosmetic; do it after
      the three actions work.

## 2. The icon migration — decided, not built

- [ ] Decide the mapping for rows that already hold an emoji.
- [ ] Migrate the stored values; old backups must still import.
- [ ] Replace the picker in `add_commitment_screen.dart`.

## 3. Today — done

Built 2026-08-30. The structure landed independently of §2, as planned: the
emoji still render exactly as before, behind a new `CommitmentIcon` seam so the
vocabulary swap is a change to one file.

- [x] Headline counts **down to zero** instead of scoring you — `unit`,
      `widget`. "Three left today" → "Done for today". A closed day tallies
      instead, because once a day is over the count is a fact rather than a
      verdict delivered mid-effort. Period targets and skips are both excluded
      from the count; `formatting_test.dart` pins that no input produces a `%`.
- [x] Weekly targets move to their own group — `widget`. `PeriodTile` is its
      own widget with pips and a tally and **no status mark**, because a period
      has no status today. Header says "NEVER LATE".
- [x] Drop the greeting and the FAB — `widget`. Add moved into the day bar; the
      test asserts no `FloatingActionButton` exists at all, so it cannot return
      by accident. A fourteen-day banded strip took the greeting's space —
      content rather than chrome, and it scores only days that are over.
- [x] Three unconstrained-`Text`-in-a-`Row` overflows found and fixed before
      shipping (95px at 320dp, 306px at 1.8× scale). Verified at 320dp, 400dp,
      landscape and 1.8×.

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
