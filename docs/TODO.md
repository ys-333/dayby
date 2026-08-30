# TODO — closing the redesign

**Every engineering item on this list is done as of 2026-08-30**, the
period-close review included. What is left is the device checks at the foot,
and none of it is code Claude can write. The rest of the file is the record of
what was built and what was decided against.

What was left to finish Riyaz's UI end to end, in the order the dependencies
allowed. `docs/PROGRESS.md` records what is **done and how it was verified**;
this file records what is **next**. Update both in the same commit as the work.

Status marks follow the ledger's rules:
`[ ]` not started · `[!]` built but unverified, nothing may be built on it ·
`[x]` done **with evidence** — a test, a migration, a build, or a device run.

---

## 0. Decisions — answered

All three were answered on 2026-08-30. Kept here as the record of what was
decided and why, because each one closed off an alternative.

- [x] **Icon vocabulary — replace the emoji.** Built as 28 outlined Material
      glyphs rather than the board's eight hand-drawn paths, on the argument
      that they are indistinguishable at 22dp and cost no asset, no dependency
      and no fixed box. `Commitment.icon` is a `String` written by
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

## 1. Commitment detail — done

All three missing actions and the layout. The screen had no edit, no pause and
no archive: a user who abandoned a commitment had no way out of a list that
only grows.

- [x] **Archive and unarchive** — `unit`, `widget`. Overflow menu, undo, and a
      banner that says history is kept. Archiving **closes the schedule** at
      the archive date; the flag alone is invisible to `lib/domain/` and left
      the commitment accruing a miss a day forever (measured 49 of 49). Tests
      resolve *past* the archive date, which is what the first pair failed to
      do.
- [x] **Pause and resume** — `unit`, `widget`, `migration`. Schema v3 makes
      `pause_periods.to_day` nullable via a `TableMigration` rebuild, so a
      pause can be open-ended. Both traps were real and both are now pinned:
      `CommitmentState.paused` is still unread by `lib/domain/`, so the action
      writes a `PausePeriod` — and the test that proves it goes through the
      menu, then resolves sixty days *past* the pause and asserts nothing
      resolves at all. Twelve of nineteen tests fail if the pause stops
      extending, so the suite is not decorative.
      **Format contract, all of it done:** `BackupDocument.currentVersion` is
      2; `"to": null` is written explicitly rather than the key omitted, so
      "still paused" and "field lost in a truncated write" are different
      bytes; `_readPause` accepts a null *or* a missing `to`, because a v1 file
      always carried a date and a hand-repaired one may have had the line
      deleted; `covers()` is
      `date >= from && (to == null || date <= to)`. **At most one open pause**
      is enforced by closing any open one the day before a new one starts, and
      deleting it if that leaves it covering nothing. Resume invalidates
      rollups from the pause's *start*, not from the resume date — wider than
      strictly needed, on the principle that a rollup is a cache and one stale
      row nothing corrects costs more than rebuilding a few extra days.
      `_resolutionVersion` did **not** move: the rule is unchanged, only the
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
- [x] **The board's layout** — `widget`. Fifteen equal-weight stats and thirty
      undated circles become one lead figure, a dated twelve-week grid, three
      momentum figures, four small windows and the latest note.
      The circles were the real loss: they showed a *sequence* with nothing to
      hang it on, so a gap could not be placed in a week or a month and could
      not be learned from. The grid is anchored to a **week start**, not to
      "today minus 83" — otherwise each row holds a different weekday and the
      one pattern it exists to show is destroyed.
      A **period** commitment's grid marks only where completions landed, never
      a per-day status, and its legend says "Counted toward a target" — the
      same two shapes and the same wording as the week grid, because a
      4×/week target has no opinion about which days it is met on.
      The lead figure states its own denominator ("Of 29 scheduled days this
      month"): a percentage with no stated base cannot be argued with. It shows
      an em dash and "Nothing has settled this month yet" rather than 0%.
      Four geometry tests now cover this screen at 320dp, 1.8× and landscape,
      scrolling the whole thing — it is reached by a push, so it was never in
      the polish suite's list of screens, which is how an overflowing grid
      could have shipped unnoticed. One was found that way: the note's rule
      needed `IntrinsicHeight`, since a stretched `Row` in a `ListView` asks
      for infinite height.

## 2. The icon migration — done

Built 2026-08-30. Schema **v4**, data-only: `commitments.icon` stops holding an
emoji and starts holding a glyph key.

- [x] The mapping for rows that already hold an emoji — `unit`, `migration`.
      Fourteen entries in `legacyEmojiIcons`, exhaustive over what could
      actually be stored: the seven add-screen templates and the fourteen the
      synthetic seeder wrote. Not a general emoji dictionary and not meant to
      become one. U+FE0F is stripped before lookup, because `🏋️` and `🏋` are
      different strings for one picture and the seeder wrote the first.
      **Anything outside the table is left exactly as written** and still
      renders — replacing a user's own mark with the nearest glyph would be
      destroying something the migration had only guessed at.
- [x] Migrate the stored values; old backups still import — `migration`,
      `unit`. The v4 step is a plain `UPDATE` per known emoji, so nothing can
      fail on a constraint. `_readCommitment` normalises on import too, so a
      restore converges on the same vocabulary. **No format-version bump:** an
      icon is a display value, and an older build meeting an unknown key draws
      the raw string — a cosmetic surprise, not a misread record. That is the
      line `currentVersion` is for, and a nullable `pause.to` crossed it where
      this does not.
- [x] Replace the picker — `widget`. `GlyphPicker` is a grid of the whole
      vocabulary, and it replaces **two** free-text inputs: the add screen's
      template-only icon and the edit sheet's 64px text field, which accepted
      any string at all. Both now write keys. Clearing a mark needed a real
      `clearIcon` flag through `updateCommitment`, since a null `icon` already
      means "unchanged" and one value cannot carry two meanings.
- [x] The vocabulary is 28 outlined Material glyphs — in the font already, no
      asset, no dependency, and they scale with text size where a fixed-box
      SVG would not. The keys live in `lib/domain/model/commitment_icon.dart`
      because they are a **data contract**; how a key becomes a picture lives
      in `lib/app/glyphs.dart` and can be swapped for bundled vectors later
      without moving a single stored row.

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

- [x] **Rollup logic version** — `unit`. All three calendar settings are now
      in `_logicVersion`, read off the resolution service's own calendar rather
      than by injecting `AppSettings`. They are the ones with teeth: a rollup
      caches "what happened on this date", and each of them changes what a date
      *is* — move the boundary and every late-night completion shifts a day,
      change the zone and the same instants land elsewhere, change the week
      start and every weekly target is scored over a different seven days.
      Not one stored row moves in any of those cases, so the staleness
      watermark sees nothing. Three tests, and dropping the change fails
      exactly those three. Still latent: `appSettings` is a hardcoded constant.
- [x] The raw `scheme.*` call sites — **decided, not renamed.** All 38 already
      resolve to the right palette value; 34 are `onSurfaceVariant`, which is
      Material's role for de-emphasised text and is exactly the question a
      caption is asking. Rewriting them as `palette.ink2` swaps a semantic role
      for a palette index and reads worse. `StatusColors` and `BandColors`
      exist because Material has no role for "a missed day"; it does have one
      for quiet text.
      What was actually missing was any **guard on the mapping** — 34 widgets
      trusted `onSurfaceVariant` to be `ink2` and nothing said so, so one line
      in `riyazTheme` could have re-tinted every caption with no test failing.
      `theme_contract_test.dart` pins every role the app leans on, in both
      brightnesses, including that **nothing anywhere reads as red** —
      `ColorScheme.fromSeed` supplies a real red for `error` unless overridden.
      Two call sites did move: `TrendChart`'s line and grid. A plotted series
      is a graphic, not a button, and `scheme.primary` would re-tint the chart
      the day the button changed.
- [x] **Insights against its board** — `widget`. Six differences found, four
      of them product rules and all four closed: the current streak was the
      headline metric that `CLAUDE.md` says it must not be; the lead
      percentage stated no denominator; Skipped read as a fourth outcome
      rather than a tally outside the score; and the trend chart had no scale.
      Two left as taste — by month stays bars, and the trend axis is fixed at
      0–100% rather than fitted as the board draws it, because fitting turns
      an ordinary wobble into a cliff.
- [x] **Period-close review UI** — `widget`. Spec §64, and the only surface in
      the app allowed to state a **final** verdict. It reviews the week that is
      *over*, never the one in progress: a period's result is final only at
      period close, and grading a Wednesday would contradict every other
      screen. A card above the day's headline carries it, because the numbers
      were already reachable on History and being reachable is not being seen.
      Two departures from the spec, both recorded in `PROGRESS.md`: "Hardest"
      rather than "Needs attention", and nothing named at all when there is one
      commitment or a tie.

---

## Device checks — only you can sign these off

Claude certifies "logic verified". "Feel verified" is a separate claim and
Claude never makes it.

- [x] **First device run** — 2026-08-30, release build on Android 14 with a
      seeded year. Found two bugs no test could: the 14-day strip collapsed to
      zero height, and "A target every a week". Both fixed and pinned.
- [ ] **Feel check:** create and track in under 10 seconds on a real phone.
- [x] **The strip was too loud** — answered and fixed. It is the heat ramp
      now, all fills, no rings, no clay, which is what the board drew and what
      `Palette.heat`'s own doc reserves the full ramp for.
- [ ] **Right-edge taps.** Synthetic taps at x≥985 on a 1080-wide screen do
      not reach the app; x=955 does. Almost certainly the phone's edge handle
      or a scrollbar, not the app — but check with a real thumb that the week
      grid's review button is comfortable to hit.
- [x] **Widget device check** — `device`. Done 2026-08-30 by temporarily
      switching the default launcher to `com.android.launcher3` and switching
      back afterwards. `render()` and `applyPayload()` have now executed:
      the widget was pinned from Settings, drew on the home screen, matched
      the app exactly (`7/8` against `TODAY 7 OF 8`, same four rows, same
      order, Reading as `—` for skipped), deep-linked into the app on tap, and
      **updated live to `8/8`** when a commitment was marked done in the app —
      so the whole chain from tap to pixels is now observed, not assumed.

      Two things only looking could have found:

      1. The APK on the phone was stale. It rendered `13/18`, the pre-fix
         daily+period figure, because the release reinstall had run *before*
         the daily-only commit. Nothing was wrong with the code; the check
         would have certified the wrong binary. Rebuild before believing a
         device observation.
      2. The widget drew **white on a black home screen** beside a dark app.
         Cause and fix below.
- [x] **The widget follows the system theme, not the launcher's** — `device`,
      `arch`. The layout used `?android:attr/colorBackground` and
      `textColorPrimary` on the stated reasoning that a widget "is drawn by
      the launcher in a theme this app does not control", so it should defer
      to that theme. On hardware the reasoning inverted: RemoteViews are
      inflated *by the launcher*, so a theme attribute resolves against the
      launcher's theme rather than the user's dark-mode setting. This
      launcher hosts widgets light, so a phone in dark mode running a dark app
      got a white slab.

      Now named colours (`widget_surface`, `widget_ink`, `widget_ink_dim`) with
      a `values-night` variant, taken from `Palette.light` / `Palette.dark` so
      the widget and the app are the same warm paper and warm near-black.
      Verified both ways on device by forcing `cmd uimode night no` and back.

      The first attempt at this shipped a worse bug than the one it fixed:
      `sed` caught the two inline `textColor` attributes in the layouts and
      missed `@style/RiyazWidgetRow` in `values/styles.xml`, so the background
      went dark while the rows stayed at the launcher's dark ink — dark on
      dark, unreadable. Found by looking at the screen; no test could have.
      `tool/check_arch.sh` rule 5 now scans the widget layouts **and the
      RiyazWidget styles** for `?android:attr`, and is verified non-vacuous
      against each site separately.

- [ ] Week grid, Insights, the rebuilt Today and the rebuilt commitment detail
      on a device — all built, none seen on hardware.
- [ ] The glyph vocabulary on a real screen. Twenty-eight outlined Material
      icons at 22dp were chosen over the board's hand-drawn paths on the
      argument that they are indistinguishable at that size and cost nothing.
      That argument has not been checked with eyes.
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
