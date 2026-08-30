# Riyaz — build ledger

## Start here (next session)

Read this section, then **Current position** below. The rest is history.

```sh
export PATH="$HOME/development/flutter/bin:$PATH"      # not on the login PATH
export JAVA_HOME=/opt/homebrew/opt/openjdk@17          # Gradle/APK builds only
export PATH="$JAVA_HOME/bin:$PATH"

flutter pub get
dart run build_runner build --delete-conflicting-outputs   # *.g.dart and
                                    # *.freezed.dart are gitignored, so a
                                    # fresh clone will not analyze until this
                                    # has run
./tool/check_arch.sh && flutter analyze && flutter test     # expect 399 green
```

**State:** all ten build phases are complete, committed and pushed to
`github.com/ys-333/dayby` on `main`. The app builds, persists to SQLite, and
has four tabs: Today, History, Insights, Settings.

**It has never run on a device.** Everything is logic-verified only.

### The four open items — none of them are code Claude can write

1. **Feel check (you).** `flutter run -d <device>`, then: can you create a
   commitment and track a day in under 10 seconds? That is the product's whole
   promise and nothing in the test suite can answer it.
2. **Widget device check (you).** The Kotlin in
   `android/app/src/main/kotlin/.../RiyazWidgetProvider.kt` compiles and is
   registered in the manifest, but **has never executed**. Place the widget,
   confirm it draws, updates when you tick something, and opens the app on tap.
3. **Export destination — needs your decision.** Export currently writes to the
   app's documents directory and offers the JSON on the clipboard. Reaching
   Downloads or a share sheet needs `file_picker` or `share_plus`, and CLAUDE.md
   forbids adding a package unasked. **Answer yes or no and the work is small.**
   Android Auto Backup already covers the lost-phone case.
4. **Period-close review UI — needs your decision.** Never built. A closed
   period's result is visible on History and Insights, but there is no
   moment-of-closure summary. Decide whether you want one.

### Two things worth knowing before touching the code

- **The Stop hook is live.** `.claude/hooks/flutter-analyze.sh` runs
  `tool/check_arch.sh` + `flutter analyze` and blocks completion if either is
  dirty. It is not advisory.
- **Widget tests run in a fake-async zone**, so real file I/O never completes
  and a screen that writes to disk during `pumpAndSettle` hangs forever rather
  than failing. That is why `BackupFileStore` is an interface with an in-memory
  double. Any future screen touching the filesystem needs the same treatment.

### Where things live

| Path | What |
|------|------|
| `docs/specs/2026-08-28-…md` | product spec (Kotlin-era; stack section is obsolete) |
| `lib/domain/` | pure Dart engines — no Flutter, no Drift, injected `Clock` |
| `lib/data/` | Drift schema v4, repositories, backup codec, seeder loader |
| `lib/features/<name>/` | one folder per screen area |
| `tool/check_arch.sh` | enforces domain purity + clock discipline |

---

Tracks what is built AND how it was verified. Update this in the same commit as
the work. A future session reads this file to know where things stand.

## Status legend

| Mark | Meaning |
|------|---------|
| `[ ]` | Not started |
| `[~]` | In progress — see note |
| `[x]` | Done **and** verified; the note says by what |
| `[!]` | Built but NOT verified — do not build on top of it |

**`[x]` requires evidence, not a build succeeding.** Record which of these
applies: `unit` (domain tests), `widget` (widget tests), `migration` (Drift
schema test), `build` (compiles + analyzes clean), `device` (you checked it on
hardware). Compiling alone is `[!]`.

Two claims are tracked separately and neither implies the other:
- **Logic verified** — tests pass. Claude certifies this.
- **Feel verified** — the interaction is actually fast and unannoying on a real
  phone. Only you can certify this; Claude must never mark it.

---

## Current position

**Phase:** all ten build phases complete → remaining items need a device or a decision
**Blocked on:** nothing
**Last verified state:** 399 tests green, `flutter analyze` clean project-wide,
`tool/check_arch.sh` clean, codegen clean, debug APK builds. Three-tab app:
tracking, history (calendar + week grid), insights. Analytics read from
materialised rollups. **Never run on a device** — no feel verification at all.

Data safety landed before the widget, deliberately: a lost phone meant total
data loss until Phase 9, and that cost rose every day the app was used.

---

## Phase 1 — Foundation

- [x] `flutter create` — org `com.yashwantsingh`, package `riyaz`, Android only — `build`
- [x] Boilerplate counter app removed — `build`
- [x] Dependencies added (riverpod 3.4, freezed 4.0, drift 2.34, go_router 18, timezone 0.11) — `build`
- [x] `analysis_options.yaml` — flutter_lints, `always_specify_types: false` — `build`
- [x] Domain purity enforced by `tool/check_arch.sh` — `build`, and proven
      against a probe file importing flutter + drift
- [x] `DateTime.now()` banned in `lib/domain/` — same script, same probe
- [x] Scoring-weight rule: bare `0.5` outside a `scoring` module is rejected — same probe
- [x] `lib/domain|data|features` tree stubbed — `build`
- [x] `build_runner` runs clean (10 outputs) — `build`
- [x] `flutter analyze` clean — `build`
- [x] `flutter test` green (1 test: app boots to home shell) — `widget`
- [x] Debug APK builds — `build`; confirms Android side works without
      `sqlite3_flutter_libs`, which is an eol no-op stub and was removed
- [x] Stop hook blocks on a real analyze error + arch violation, combined —
      verified by injecting both into `lib/domain/`
- [x] Hook confirmed firing in a live session — `build`. Verified end to end by
      planting a domain-purity violation and attempting to stop: the hook
      blocked completion and fed the violations back. Not merely "the script
      works" — the gate actually gates.
- [x] `git init` + generated code (`*.g.dart`, `*.freezed.dart`) gitignored — `build`
- [x] **First commit** pushed to github.com/ys-333/dayby (`main`) — `build`

### Phase 1 notes / deferred
- `go_router` is wired with a single placeholder route. Real routing lands with
  the bottom-nav shell in Phase 3.
- Theme is `ColorScheme.fromSeed` + `ThemeMode.system`. The user-facing
  light/dark/system setting is a Phase 10 item.
- `flutter doctor` warns about two `adb` binaries (Android SDK platform-tools
  and a Homebrew cask). Harmless for builds; may confuse device detection.

## Phase 2 — Domain engines  ← correctness lives here

All logic verified by unit tests (`unit`). Nothing here has been near a device.

- [x] `Clock` abstraction + `FixedClock` — `unit`. `SystemClock` lives in
      `lib/data/` because reading ambient time is what the domain may not do.
- [x] Accounting-day resolution (4 AM boundary, configurable) — `unit`
- [x] Commitment / Schedule / TrackingEvent / PausePeriod models (Freezed) — `unit`
- [x] Recurrence engine — `unit`
- [x] Accounting engine — `unit`
- [x] Analytics engine — `unit`
- [x] Synthetic seeder (365 days x 20 commitments, momentum-modelled) — `unit`

### Test matrix — all verified

Time
- [x] 4 AM boundary: 23:45 and 01:30 resolve to the same accounting day
- [x] Midnight belongs to the previous accounting day
- [x] Month / year transition, leap year, century leap rules (1900 vs 2000)
- [x] DST spring forward — the day holding the skipped hour is 23h
- [x] DST fall back — 25h day; the repeated 01:30 resolves once, to one day
- [x] Zone-relative: one instant is different accounting days in Kolkata vs NY

Daily commitments
- [x] Future occurrence is pending and out of the denominator
- [x] Today stays pending; pending becomes missed only at the 04:00 close
- [x] Done / partial (half credit) / skip
- [x] A skip outranks a completion recorded the same day
- [x] Multi-count targets accumulate; a closed shortfall is partial

Period commitments
- [x] 4x/week emits ONE occurrence — no missed Wednesday can exist
- [x] An open week behind target is pending, never missed
- [x] Denominator is the target (4), not the day count (7)
- [x] Hitting the target closes the week early; overshoot cannot exceed 100%
- [x] A closed short week scores its completion ratio (3/4 = 75%)
- [x] Monthly target stays open all month

Schedule versioning
- [x] Daily → weekly change leaves prior months numerically identical
- [x] A straddling period is clipped to the version that governs it, with a
      prorated target (see decision below)

Exclusions
- [x] SKIPPED excluded from denominator (not scored 0)
- [x] PAUSED days are NOT_EXPECTED; a fully paused period drops out
- [x] Archived commitments retain history (seeder generates them; resolution
      is unaffected by state)

Mutation
- [x] Backfill flips missed → done, raises consistency, repairs the streak
- [x] Past-day edits (done→skip, done→partial, delete) recalculate correctly
- [x] Resolution is a pure function of canonical records, order-independent —
      which is what will make materialised rollups safe to rebuild in Phase 6

### The spec's own acceptance scenario (§72)
- [x] Aug 1–5 done, 6–8 missed, 9 done → longest 5, current 1, recovery 3.0
- [x] Gym Mon/Tue/Thu/Sat → 4/4, full credit, zero missed days

### Decisions taken where the spec was silent

**Straddling periods.** A schedule version that starts or ends mid-week yields a
period *clipped* to the days it governs, with the target prorated (3x/week
starting Thursday → target 2 over 4 days), floored at 1. The alternatives were
both worse: governing a period by its first day silently dropped the tail of a
mid-week change, and charging a full target over a clipped span manufactures an
unavoidable failure. Caught by a test, not by inspection.

**Streak semantics.** `done` extends a run; `partial` and `missed` end one;
skipped/paused/unscheduled are *transparent* (neither extend nor break), so
skipping for travel cannot cost a streak; `pending` is ignored, so an unfinished
today never breaks yesterday's run.

**Period partial credit.** Daily occurrences use the flat 0.5 weight the spec
states in §49. Period occurrences use their completion ratio instead, because
§11 reports a 3-of-4 week as 75% and a flat half would contradict it.

**Spec erratum.** §49's worked example is internally inconsistent: it states 15
done + 2 partial + 3 missed against a denominator of 18, but those counts sum to
20. We implement the stated *formula* (weighted ÷ eligible, skips excluded),
which reproduces its stated answer of 88.9% from self-consistent counts.

### Not built in Phase 2
- Materialised rollups. The engines derive everything from canonical records on
  demand; caching lands with the analytics screens in Phase 6, where the
  performance requirement actually bites.
- JSON serialisation on the models. Deferred to Phase 9 with export/import, so
  codegen stays simple until `CivilDate` converters are actually needed.

## Phase 3 — Core tracking

Persistence landed here too — the engines had nothing to read from before.

### Data layer
- [x] Drift schema: commitments, schedules, tracking events, pauses, settings — `migration`
- [x] `CivilDate` stored as epoch day, instants as UTC millis, never mixed — `unit`
- [x] Every frequency shape round-trips through storage — `unit`
- [x] Foreign keys enforced; deleting a commitment cascades — `unit`
- [x] `schemaVersion` 1 with an explicit migration hook; `deleteOnSchemaChange`
      is never used and a comment says why — `build`
- [x] Repository exposes a live snapshot stream — `unit`

### UI
- [x] Home screen: greeting, date, progress, today's rows — `widget`
- [x] Add commitment, single screen with templates — `widget`
- [x] One-tap Done; countable rows increment instead — `widget`
- [x] Tapping a finished row un-ticks it — `widget`
- [x] Partial · [x] Skip · [x] Clear, via long-press — `widget`
- [x] Undo on every tap-write, restoring exact prior state — `widget`
- [x] Notes, offered only where an event exists to attach to — `widget`
- [x] Backfill: step back to a past day and record — `widget`
- [x] Editing past days recalculates without touching today — `widget`
- [x] Active-commitment soft cap warns past 6, never blocks — `widget`
- [x] Status conveyed by shape + glyph + semantic label, not colour — `build`
- [x] Empty state — `widget`
- [ ] **Feel check (you):** create + track in under 10 seconds on a real phone

### Bugs found and fixed during Phase 3
- Action sheet overflowed on a short screen once it had five rows; now scrolls.
- Note dialog disposed its controller while the exit animation still used it;
  the dialog now owns its own controller.
- `watch()` used `await for`, which did not propagate cancellation — closing a
  screen leaked the subscription. Now `yield*`.

### Decisions taken
- **Timezone is a stored setting defaulting to `Asia/Kolkata`.** Detecting the
  device's IANA zone needs a plugin (`flutter_timezone`);
  `DateTime.now().timeZoneName` yields an ambiguous abbreviation that is
  useless for DST arithmetic. Not added unasked — see open questions.
- **No `rxdart`.** Combining table streams is done with Drift's own
  `tableUpdates`, re-reading the range on change. At one person's scale the
  simplicity beats the saved microseconds.
- **No `intl`.** Seven weekday names and twelve month abbreviations live in
  `lib/app/formatting.dart`. Swap for `DateFormat` if the app is ever localised.
- **Forward navigation stops at today.** Offering future days invites
  pre-ticking days you have not lived.

## Phase 4 — Period targets
- [x] Weekly targets render and increment as "2 / 4 this week" — `widget`
- [x] Monthly targets — `unit` (domain), rendering shares the weekly path
- [x] Period progress display distinct from daily rows — `widget`
- [x] Period closure — `unit`
- [ ] Period-close review UI (what the user sees when a week ends) — not built

## Phase 5 — History
- [x] Month calendar with band-coded days — `widget`
- [x] Daily detail — tapping a day opens it on the tracking tab, which already
      handles any date. One editing surface, not two — `widget`
- [x] Weekly grid: daily rows show seven cells, period rows show one chip — `widget`
- [x] Commitment detail: momentum, consistency windows, trend, recent strip — `widget`
- [x] Future days render outline-only and are not tappable — `widget`
- [x] Status never conveyed by colour alone: shape + glyph + semantic label,
      plus a legend on the calendar — `widget`
- [x] Cannot page past the current month or week — `widget`

## Phase 6 — Analytics
- [x] Consistency for day / week / month / 90 days / year — `widget`
- [x] Streaks and recovery surfaced on both detail and insights — `widget`
- [x] Rolling 7-day trend, hand-drawn, gaps not zeroes — `widget`
- [x] **Yearly view does not scan raw events** — `unit`. Materialised
      `occurrence_rollups` table with watermark invalidation. Proved directly:
      after building rollups the test deletes every tracking event and the
      summary is unchanged, which an event-scanning implementation could not do.
- [x] Rollup aggregation equals direct resolution, and rebuilds from scratch
      to the same numbers — `unit`
- [x] Rollups are discarded when the *logic* that built them changes, not only
      when data changes — `unit`. `rollup.logicVersion` stamps the resolution
      contract; a mismatch throws the cache away. See the decision below.
- [x] Schema v1 → v2 migration adds the rollup table without data loss — `build`
      (declared and compiles; not yet exercised by a migration test — Phase 10)

## Phase 7 — Insights
- [x] Rule-based patterns: momentum, recovery, weakest weekday — `unit`, `widget`
- [x] Data thresholds enforced (21 eligible observations, 3 completed runs,
      3 samples per weekday) — `unit`, `widget`
- [x] Weekday claims require a real spread, so noise is not reported as a
      finding — `unit`
- [x] Commitment load warning, soft and non-blocking — `unit`, `widget`
- [x] Shows "not enough data yet" with how much more is needed, rather than an
      empty list or an invented pattern — `widget`

### Bug found and fixed during 5–7
- `TrackingRepository.onWrite` was fire-and-forget, so a read issued right
  after a write could observe the rollup invalidation marker before it was
  written and silently serve **stale analytics**. The callback now returns a
  future and every call site awaits it.

### Decisions taken
- **Rollup invalidation is a single watermark**, not per-row dirty tracking.
  Any write records the earliest date it could affect; the next read rebuilds
  from there. Backfilling last March costs a rebuild of March onward; ticking
  today costs almost nothing. Per-row tracking is more precise and much easier
  to get subtly wrong.
- **A rollup carries the version of the logic that produced it.** The watermark
  above answers "what data changed"; it cannot answer "what did *resolution*
  change". A rollup is a cached `AccountingEngine.resolve()` result, valid only
  while the rules that produced it hold. Found 2026-08-30: the period-skip fix
  changed how a week resolves, and every stored rollup went on disagreeing with
  the engine afterwards — invisible only because reseeding the test database
  happened to rebuild them. `rollup.logicVersion` now stores a resolution
  version plus the scoring weights; a mismatch discards the whole cache and
  rebuilds. Weights are folded in automatically rather than left to the
  constant alone, because `ScoringWeights` exists to be changed and requiring
  whoever changes it to also remember a version bump is the kind of discipline
  that fails silently.
- **No charting package.** The trend is one polyline with a gap rule, drawn by
  a `CustomPainter`. Null points break the stroke rather than dropping to zero,
  so a window with nothing eligible reads as absent, not as collapse.
- **Weekday insights exclude period occurrences.** A 4x/week commitment has no
  opinion about Tuesday; folding it in would attribute behaviour to days that
  were never individually expected.
- **Insights are descriptive, never verdicts.** "You tend to lose momentum
  after six days" is information; a tracker that judges gets deleted.
- **The load warning is exempt from the history threshold** — it counts what
  exists right now rather than claiming a behavioural pattern.

## Phase 8 — Widget
- [x] Home-screen widget renders today — `build`, `unit`. Native
      `AppWidgetProvider` + `RemoteViews`, fed by a `MethodChannel`
      (`dev.riyaz/widget`). Kotlin compiles, the receiver is in the merged
      manifest under its full class name, and both `riyaz_widget.xml` and
      `riyaz_widget_info.xml` are confirmed compiled into the APK.
- [x] Payload rendering and encoding — `unit`. 13 tests: every status has a
      distinct glyph, skips leave the progress denominator, an empty day shows
      a dash not 0%, unicode survives, and the JSON key set is asserted against
      the Kotlin contract.
- [x] Bridge failure modes — `unit`. A refusing launcher, a missing native
      side, and a non-Android platform all degrade quietly rather than throwing.
- [ ] **Device check (you):** place the widget, confirm it renders and updates,
      and that tapping opens the app. **Nothing below is verified.**

### What is NOT verified
The Kotlin has never executed. Compiling and being registered in the manifest
says nothing about whether the widget draws correctly, updates when the app
writes, or survives a launcher restart. Treat the native half as `[!]` until
it has run on a phone.

### Decisions taken
- **RemoteViews, not Jetpack Glance.** Glance needs Compose on the Gradle
  classpath. The spec asked for Glance, but it predates the Flutter decision,
  and this widget is a heading plus five rows. Zero new dependencies —
  `MethodChannel` is built into Flutter, and the native side is ~120 lines.
- **Dart renders every string.** The payload carries finished text; the Kotlin
  does no arithmetic and knows nothing about skips, pauses or period targets.
  A second implementation of the scoring rules would eventually disagree with
  the first.
- **Tap deep-links into the app rather than completing in place.** Completing
  from the widget would need a background Dart isolate to run the accounting
  engine. The spec explicitly allows deep-linking where widget limitations
  prevent an action.
- **Glyphs, not colours.** The launcher controls the theme and the size; a
  colour-coded dot would be illegible on many launchers and would break the
  same no-colour-alone rule the app follows everywhere.
- **Five row slots.** A scrolling list needs a `RemoteViewsService`; beyond
  five the widget says "+N more" rather than silently truncating.
- **Push failures are swallowed.** The widget is a convenience; a launcher
  that refuses an update must never break the running app.

## Phase 9 — Data safety
- [x] JSON export — `unit`, `widget`. Versioned, self-describing format with a
      `riyaz.backup` tag; dates stay human-readable so a damaged file can be
      inspected and repaired by hand.
- [x] Validated import — `unit`, `widget`. Validate → preview → import, never
      straight to overwriting. Refuses non-JSON, foreign files, a format version
      newer than this build, malformed dates and unknown enum values.
- [x] Merge and replace modes — `unit`. Merge is idempotent: re-importing the
      same file changes nothing, so a retry is always safe.
- [x] Orphans are dropped with a warning rather than failing the whole import — `unit`
- [x] Whole import runs in one transaction; a refused file leaves the database
      untouched — `unit`
- [x] Android Auto Backup — `build`. `allowBackup`, `fullBackupContent` (API
      23–30) and `dataExtractionRules` (API 31+, cloud backup *and* device
      transfer). Verified present in the merged manifest and both XML files
      confirmed compiled into the APK. Journal/WAL files excluded so a restore
      cannot pair a database with a mismatched journal.
- [x] **Round trip: export → wipe → import → analytics identical** — `unit`.
      Over a full synthetic year (20 commitments, schedule changes, pauses,
      archived commitments): every count, the weighted completion to 1e-9, the
      percentage, and **per-commitment** longest/current streak and recovery all
      match. Rollups rebuild to the same numbers after the restore.
- [x] Settings tab hosting the backup UI — `widget`
- [x] Real file store covered by its own unit test (unicode, overwrite,
      listing order, 500KB payload) — `unit`
- [ ] **Export to a user-reachable location** — see below. Currently writes to
      app documents and offers the JSON on the clipboard.

### Blocked on a package decision
Getting a file somewhere the user can actually reach — Downloads, a share
sheet, Drive — needs the Storage Access Framework, which in Flutter means a
plugin (`file_picker` or `share_plus`). CLAUDE.md forbids adding a dependency
unasked, so export writes to the app's documents directory, shows the path, and
puts the JSON on the clipboard. Android Auto Backup covers the lost-phone case
meanwhile. **This needs a yes/no before V1 ships.**

### Bug found and fixed during Phase 9
- The settings widget test hung indefinitely rather than failing.
  `testWidgets` runs in a fake-async zone where real file I/O never completes,
  so a screen writing to disk during `pumpAndSettle` waits forever.
  `BackupFileStore` is now an interface: screens take an in-memory double in
  widget tests, and the real implementation has its own plain `test()` where
  the event loop is real. Worth remembering — the same trap catches any future
  screen that touches the filesystem.

### Decisions taken
- **Rollups are excluded from backups.** They are derived and rebuild
  themselves; including them would let a backup carry a stale contradiction of
  its own source data.
- **Interpretation settings travel with the data.** Timezone, day boundary and
  week start are in the file, because without them every stored civil date is
  ambiguous. Import warns when they differ from the device.
- **Hand-written codec, not codegen.** A backup format is a long-lived contract
  with the user's own history; tying its shape to whatever the model classes
  look like today would make old files unreadable after a refactor.
- **Import refuses rather than guesses.** A half-understood backup is worse
  than a rejected one, because it silently loses history.

## Phase 10 — Polish
- [x] Empty states — `widget`. Every screen renders on an empty database
      without throwing, and each explains itself rather than showing a blank
      frame. Nothing eligible reads as an em dash, never a fabricated 0%.
- [x] Error handling — `widget`. Every screen has loading and error branches;
      a missing commitment and a malformed backup both fail readably.
- [x] Dark and light — `widget`. All four screens render in both, and no Text
      carries a hard-coded black that would vanish on a dark surface.
- [x] Rotation and screen size — `widget`. Portrait (400x800), landscape
      (800x400) and a small phone (320x568), plus 1.8x text scaling.
- [x] Accessibility labels — `widget`. Rows announce name and state; calendar
      cells announce their date and result, and a future day announces "not
      yet" rather than a failure. Passes Flutter's own
      `androidTapTargetGuideline` and `textContrastGuideline`.
- [x] **DB migration from a prior version** — `migration`. A real schema-v1
      database (DDL copied verbatim from a v1 build, not written from memory)
      is populated, opened, and migrated: version advances to 2, every
      commitment, schedule, pause and event survives including a unicode note,
      the rollup table is created empty and usable, and foreign keys are
      enforced on the migrated connection rather than only on fresh installs.

### Bugs found and fixed during Phase 10
Three real layout failures, all found by tests rather than inspection:
- **History month summary overflowed by 124px at phone width.** A headline plus
  four fixed-width counts in one row does not fit 400dp. Now a column, with
  each count `Expanded` so the row divides the width it has.
- **Insights overflowed by 441px at 1.8x text scale.** The year bars used hard
  36dp and 44dp boxes for the month label and percentage; neither can hold
  scaled text. Now `ConstrainedBox` minimums.
- **History mode toggle sat in `AppBar.actions`.** A two-segment button beside
  a title is too wide for a phone. Moved into the body.

The 1.8x text-scale case is worth keeping in the suite: it is a real
accessibility setting, and it broke a screen that looked fine at every normal
size.

### Not done, and why
- **`SchemaVerifier`** (drift's generated step-file migration harness) was not
  set up. It needs `drift_dev schema dump` output committed per version. The
  hand-built v1 fixture tests the same migration path against real data today;
  revisit when there is a v2 → v3 step to verify.
- **Golden/screenshot tests.** They would pin down rendering, but goldens are
  brittle across Flutter versions and none of this has been seen on a device
  yet — pinning pixels before anyone has judged them is premature.

### Fixes from the first device run

Five problems that only surfaced once the app ran against a generated year on a
real phone. Logic verified: `flutter analyze` clean, 264 tests pass. Not feel
verified.

- **A skip inside a period dropped the whole period.** `AccountingEngine` let an
  explicit skip settle any occurrence, but a skip is a statement about one day
  and a period is scored over its target, not its days. A skipped Wednesday
  marked the entire week skipped — pulling it out of the denominator and
  discarding completions already recorded in it, so two done days scored `0 / 3`.
  Now restricted to `DailyOccurrence`. Every earlier skip test was daily, which
  is the only shape the check had ever been written for.
- **The undo bar never went away.** Flutter arms a `SnackBar`'s dismiss timer
  only from inside `ScaffoldMessengerState.build`, which never happens when the
  bar is shown from the continuation after an awaited write. It animated in,
  settled with no frames pending, and sat over the bottom of every tab
  indefinitely. `_TodayListState` now owns the timeout. Pinned in
  `test/features/home/snackbar_test.dart`.
- **The commitment detail screen was unreachable.** Nothing anywhere opened it.
  Added "View details" to the long-press sheet, which is now the only route in.
- **Skip was offered on period rows, where it does nothing.** Skipping a day
  inside "3x/week" has nothing to settle — the week is still asking for three —
  so it recorded an event and visibly changed nothing. Hidden for period rows.
- **The Today tab kept whatever day you had browsed to.** Tapping Today now
  returns to today. The calendar's day drill-down sets the tab directly, so it
  still keeps the date it asked for.

Also added: the synthetic seeder is reachable from Settings in debug builds,
behind a confirm — it replaces the database, so it asks first.

### A token layer for status colour

Statuses had been borrowing Material's UI roles: missed took `scheme.error`,
partial took `scheme.tertiary`, skipped took `scheme.outline`. Those roles mean
something else. `error` is the colour of a form field filled in wrong, and
pointing it at a run you did not go on tells the user their morning was invalid
— which is how a list of six commitments turns into a wall of alarm on the one
screen the app most needs to feel unremarkable to open.

`lib/app/theme/` now holds that vocabulary: `StatusColors` and `BandColors` as
`ThemeExtension`s, plus the numeric tokens (`Insets`, `Radii`, `Sizes`) and the
first two type roles. `StatusIndicator`, `CommitmentTile` and `CalendarCell`
read from it instead of reaching into the scheme.

**Nothing on screen changed, and that was the point.** Every token is still
wired from the `ColorScheme` the widgets used to read — `missed: scheme.error`
— so the pixels are identical by construction rather than by inspection. It is
worth separating because the commit that *does* change the palette then becomes
a diff of values in one directory, reviewable on its own, instead of a repaint
tangled up with a refactor of every widget that mentions a colour.

Logic verified: `flutter analyze` clean, `tool/check_arch.sh` clean, 276 tests
pass (267 before, 9 new). Not feel verified — nothing to feel yet.

- `test/app/theme/token_wiring_test.dart` pins each status and band to the role
  it replaced, in both brightnesses. Checked non-vacuous: mis-wiring `missed`
  to `tertiary` fails three of them.
- It also covers a hole the widget tests cannot. They pump a bare `MaterialApp`
  and so exercise the *fallback* in `RiyazThemeAccess`, never the extension the
  real app registers, which means green tests would have survived the two
  drifting apart — app and tests rendering different palettes, quietly, until
  someone looked at a phone. The test asserts both paths resolve a status to
  the same scheme role.

Deliberately left alone, so the palette commit is the one that moves them:
`onSurfaceVariant` at ~20 call sites, `TrendChart`'s line and grid, and the
calendar's fixed 13px day numeral.

### The palette itself

`lib/app/theme/palette.dart` holds two hand-built palettes — warm near-black
and warm off-white — in place of one seed run through Material's generator. A
generated scheme optimises for internal harmony and has no opinion about what
a colour *means*, which is how a missed run ended up painted in the red a form
uses for an invalid field.

**Every value is solved, not chosen by eye,** and the maths now lives in
`test/app/theme/palette_test.dart` rather than in a document. A palette
verified once stays verified only until the first person nudges a hex code.

Floors enforced on both palettes: 4.5:1 for text and glyphs, 3:1 for rings and
dots that carry meaning, 1.45:1 between adjacent heat-ramp steps, and OKLab
ΔE ≥ 6 between the three status hues under normal, protan, deutan and tritan
vision.

Three things the measurement caught that inspection had not:

- **The recorded ratios were against the page background only.** Marks also sit
  on cards, where contrast is lower. Re-solved against the worst surface each
  mark can land on — the lightest one in dark mode, the darkest in light. Small
  text on a card had been sitting at 4.48:1 while the notes said 4.78.
- **The three status hues collapsed under colour-vision simulation.** They sat
  at nearly identical lightness, which reads fine to full colour vision and
  takes partial-vs-missed down to ΔE 3.0 under deuteranopia — the same brown.
  They are now an evenly spaced lightness ladder: worst case 9.8 in dark, 8.0
  in light. The ladder runs in the direction the statuses mean, done most
  prominent and missed quietest, which is the opposite of what an optimiser
  picks when you only ask it for separation.
- **A weak day and an empty day were separated by ring colour alone** — the one
  thing this app is not allowed to do. They now differ in ring weight too.

Also: `today` no longer borrows partial's hue, and `missedFill` was cut rather
than shipped, because no ink clears 4.5:1 on it in dark mode.

`test/support/harness.dart` now pumps the real theme. It used to pump a bare
`MaterialApp`, so every widget test — the contrast guideline included — was
measuring stock Material against a palette the app does not ship. A passing
accessibility check on colours nobody sees is worse than no check, because it
reads like coverage.

Logic verified: `flutter analyze` clean, `tool/check_arch.sh` clean, 290 tests
pass (276 before). **Not feel verified — this one needs a device pass before it
is anything better than `[!]`.** Contrast maths and CVD simulation say nothing
about whether a screen of sage ticks is pleasant to open at 6am.

Not done: bundling Newsreader. The decision rested on "one weight, ~50–80KB";
Google Fonts ships it only as a 451KB variable font, and there is no subsetting
tool on this machine. Left for a decision rather than quietly absorbed.

**Device pass, Android 14 phone, generated year loaded.** Both themes render,
every screen holds together, and two things only the phone could show:

- **The calendar legend was a second definition of the band vocabulary.** It
  built its swatches out of `scheme.*` rather than `BandColors`, so it happened
  to agree until weak and empty days started differing by ring weight — at
  which point the legend was actively teaching the wrong thing. Now drawn from
  the same styles the grid uses, ring weight included.
- **Momentum's four stat columns had no gutter**, so "Current streak" and
  "Longest" rendered as one word. Spaced.

Still open after the device pass, and better decided by eye than by argument:

- The commitment emoji are full-colour and are now the loudest thing on a
  deliberately muted screen. The palette lost that fight.
- In light mode a strong day is near-black (the ramp's dark end), which is the
  standard direction for a sequential ramp but reads heavy next to the sage
  partial days.
- The FAB still covers the last row, the greeting still costs ~180px, and
  daily and period rows still carry identical weight. All three are Today's
  structure, untouched here by design.



---

## Remaining work

**`docs/TODO.md` is the working list** — what is next, in dependency order,
including the three decisions that are yours rather than Claude's. This section
stays as the narrative; that file is the queue.


### Device checks and decisions — nothing here is code Claude can write

- [ ] **Feel check:** create and track in under 10 seconds on a real phone
- [ ] **Widget device check:** place it, confirm it renders, updates, and that
      tapping opens the app. The Kotlin has never executed.
- [ ] **Export destination decision:** reaching Downloads or a share sheet
      needs `file_picker` or `share_plus`. Blocked on your yes/no.
- [ ] Period-close review UI (what the user sees when a week ends) — designed
      away rather than built; the period result is visible on the history and
      insights screens, but there is no moment-of-closure summary.

### Four designed screens, none built

`docs/design/` holds the **Riyaz Redesign** canvas — five artboards, committed
because they were living in a session scratchpad under `/private/tmp` and would
have been cleaned up. Read `docs/design/README.md` first; the annotations in
`canvas.json` are the argument and the markup is only the evidence.

The design-system board is built — it is the palette work above. The four screen
boards are not, and they are ordinary implementation work, not device checks or
decisions:

- [x] **Insights: the load warning reads as an error** — `widget`. See below.
- [x] **History: period rows break the week grid** — `unit`, `widget`. See below.
- [x] **Detail: three actions and the layout** — `unit`, `widget`,
      `migration`. Archive and unarchive, edit, pause and resume, and the stat
      wall replaced by one lead figure and a dated twelve-week grid. See
      below.
- [x] **Today: the structure the device pass complained about** — `unit`,
      `widget`. All three findings answered. See below.

Also unbuilt, and it cuts across all four: **Newsreader is not bundled**, so
every serif on every board renders in the device sans. See the type note in
`docs/design/README.md`.

### The week grid, and an insight that stopped shouting

Two of the four boards, built. Logic verified: `flutter analyze` clean,
`tool/check_arch.sh` clean, 297 tests pass (290 before, 7 new). **Not feel
verified** — neither has been seen on a phone.

**Period rows now keep the same seven columns as every other row.** They used
to collapse into a single chip that spanned the grid at no particular column
while the header above still read M T W T F S S, which is what made the table
look broken.

The original code's objection was recorded in its class doc and was right:
drawing seven *status* cells for a 4x/week target would claim each day was
expected, which is the misconception the whole period model exists to prevent.
So a period row does not draw statuses. It draws a small dot on the days a
completion actually landed — a record of where the week's work fell, carrying
no claim that any of those days was owed. Two visibly different marks, and the
new week legend names them apart: "Done" versus "Counted toward a target".

- `ResolvedOccurrence.creditedDays` is the new domain field behind it: the days
  inside a span that carried a completion, deduped and sorted. Display only —
  `completed` remains the number that scores, and the two are allowed to
  disagree, since one day can record a count above one. Five tests in
  `accounting_engine_test.dart` cover it, including that a partial credits no
  day and a skip credits nothing.
- **Rollups are untouched by this.** The week grid reads live resolution rather
  than the rollup table, and nothing here changes what a status resolves to, so
  `_resolutionVersion` does not move.
- The tally moved from a floating chip into the row label, tinted when the
  target is met.

**The load insight no longer wears `errorContainer` and a warning triangle.**
Telling someone that eleven daily commitments is a lot, in the livery of a form
they filled in wrong, is the wall-of-alarm problem in miniature — and `Insight`
carries no valence field precisely so the UI cannot start issuing verdicts.
Every card now takes the same surface; only recovery is tinted, being the one
number this app is willing to be pleased about. The icon is stacked layers, not
a hazard triangle.

Both new tests were checked non-vacuous: restoring `errorContainer` fails the
insights test, and crediting every day fails both week-grid tests.

**Deliberately not done:** the board also gives *daily* rows a tally ("2 of 6").
Its sample data counts skipped days in the denominator, which contradicts the
rule that skipped is excluded entirely. That is a real accounting question, not
a layout one, so it is left rather than guessed at.

### Archive, and what it must not touch

The detail screen had no way to archive, pause or edit — a user who abandoned
a commitment had no exit from a list that only grows. Archive and unarchive
are now on the overflow menu, with undo and a banner stating that history is
kept, because "archived" is a word most people read as "deleted".

The data layer was further along than it looked: `setState()` already existed
and had never been called from anywhere.

**What the tests pin is that archiving changes nothing about the past.**
`archive_test.dart` resolves a fortnight of history, archives, resolves again
and asserts every status and every credit is identical. Verified non-vacuous:
flipping `includeArchived` to false — the exact silent failure, where a year
of history stops counting and nothing throws — fails it.

**The first version of this was wrong, and shipped.** It set `state` and
`archivedOn` and stopped there, arguing that archiving needed no rollup
invalidation because it "resolves no occurrence differently". That holds only
for dates at or before the archive date — which is exactly the window the
original tests resolved, so they passed.

`lib/domain/` reads neither `state` nor `archivedOn`; the **schedule** is the
source of truth for what was expected. Leaving the schedule open meant the
commitment kept generating expected occurrences forever, each turning MISSED
as its day closed. Measured on a commitment archived seven weeks earlier:
**49 of 49 days missed, identical to not archiving at all.** Archive a daily
commitment and consistency bleeds a miss a day, indefinitely, with nothing
throwing.

Archiving now closes the schedule at the archive date, in the same transaction
as the flag, and does mark rollups stale. Unarchiving reopens the version it
closed — matched on the stored archive date, so a schedule that genuinely
ended on another day is untouched.

Logic verified: analyze clean, check_arch clean, 305 tests pass (297 before,
8 new). Not feel verified.

The lesson is in the test, not the fix: an assertion that history is unchanged
means nothing if the window it inspects ends where the change begins.

Two traps found while building it, recorded in `docs/TODO.md` before pause is
attempted: `CommitmentState.paused` is referenced nowhere — the engines read
`PausePeriods` alone, so wiring Pause to it would look correct and silently do
nothing — and `PausePeriod.to` is non-null, so an open-ended pause needs a
schema decision.

### Editing, without editing the past

`updateCommitment` did not exist. It does now, and the whole of its care is in
one distinction: name, icon and description describe the commitment, while
**frequency describes what was expected of you**.

Rewriting the current schedule row in place would retroactively change what
every past day was measured against — switch a year-old daily habit to 3×/week
and twelve months re-resolve against a target nobody was ever held to. Nothing
throws. The numbers simply become wrong, which is the same shape as the
archive bug earlier today.

So a frequency change is effective-dated: the version in force closes the day
before, a new one opens on the change date. `frequency_picker.dart` was lifted
out of the add screen rather than copied, so both doors offer the same control
and the same vocabulary.

**The tests resolve across the change date in both directions** — the past
must be unchanged *and* the future must use the new rules. Verified
non-vacuous: forcing an in-place rewrite fails three of them, including
"the past is still judged by the rules it was lived under".

One question raised beforehand answered itself. Whether to amend rather than
version when a commitment has no history looked like a taste call; it is not.
A schedule that already begins on or after the change date **must** be
amended, because closing it the day before would leave a version whose end
precedes its start — an empty row every future reader would have to know to
skip.

The sheet says "your history does not change" *before* the user commits, and
"Saved. Your history is unchanged." after, but only when the frequency
actually moved. A rename does not claim to be a schedule change.

Logic verified: analyze clean, check_arch clean, 314 tests pass (305 before,
9 new). Not feel verified.

### Today, rebuilt around a countdown

The last of the four screen boards, and the three findings the device pass
raised against this screen are each answered by a structural change rather than
a repaint. Logic verified: `flutter analyze` clean, `tool/check_arch.sh` clean,
332 tests pass (325 before, 7 new in `test/app/formatting_test.dart` plus a
rewritten `home_screen_test.dart`). **Not feel verified.**

**The headline counts down instead of scoring.** `_Progress` — a percentage, a
bar and a "3 / 8" — is gone, replaced by one sentence: "Three left today",
reaching "Done for today" at zero. The argument is in `dayHeadline`'s doc and
it is about *when* the number is shown: at nine in the morning a percentage of
a day is a failing grade for a day that has barely started, while a count of
what remains is a task that shrinks as the day goes. A **closed** day still
gets a tally ("2 of 3 done"), because once the day is over the count is a fact
rather than a judgement delivered early.

Two things deliberately do *not* enter the count:

- **Period targets.** A 3x-a-week target cannot be behind on a Tuesday, so it
  is never part of "left today". A user whose commitments are all weekly sees
  "Nothing due today", never a "Done for today" they did not earn.
- **Skips.** A skipped row is not waiting on anyone. It leaves the countdown
  and the group tally exactly as it leaves consistency — and it stays visible
  on screen, uncrossed, per principle 6.

**Daily and period rows are two groups with two different row shapes.** This is
principle 3, and it is the finding that mattered most: rendering a weekly
target at the same weight as a daily one made it look overdue every day of the
week. `PeriodTile` is a separate widget rather than `CommitmentTile` with a
different subtitle — it shows pips and a tally and has no status mark at all,
because a period has no status *today*. The group header says "NEVER LATE" out
loud; without it the split reads as arbitrary.

**The greeting is gone and so is the FAB.** Add moved into the day bar. A FAB
is a 56dp disc pinned over the bottom-right of the one screen whose whole job
is a scrollable column of tap targets, and it permanently hid one of them —
`home_screen_test.dart` now asserts there is no `FloatingActionButton` at all,
so it cannot come back by accident.

What replaced the greeting is content rather than chrome: a fourteen-day banded
strip, which is the same pixels as the old progress bar carrying the opposite
message. The bar scored the day in progress; the strip scores only days that
are over and draws the current one as an outline ring. It reads a wider range
than the list does, so it resolves in its own provider and reserves its height
while loading — a spinner there would put a spinner above the rows the user
opened the app to tap.

**The daily row lost its status caption.** "Not done yet" under every untouched
commitment was a column of noise saying what an empty ring already says. What
survives is the states a mark *cannot* carry: a tally, a status the user chose
(Partial, Skipped, Paused), and their own note — which is now on the row rather
than behind a dialog. The tests assert `OccurrenceStatus` off the model instead
of a string that is deliberately no longer rendered.

**Three layout bugs caught before they shipped**, all the same bug: an
unconstrained `Text` in a `Row`. The strip's caption pair overflowed by 95px at
320dp and 306px at 1.8x text scale; `SectionHeader`'s trailing label and
`PeriodTile`'s tally would have done the same. Every one is now `Flexible` and
wraps. Verified at 320dp, 400dp, landscape and 1.8x.

**One thing found and deliberately not fixed:** marking Partial on *today*
leaves the row reading pending, because an open window is `PENDING` by design
and a partial recorded at ten in the morning must not close a day the user can
still finish. That is the engine being right. It does mean the only feedback
for the action is the undo bar; a caption appears once the day closes. Pinned
by two tests so the distinction is not mistaken for a regression later.

**Not built from this board:** the emoji at the left edge of each row are
unchanged. The board replaces them with stroked glyphs, but `Commitment.icon`
is a `String` that is serialised into the backup format, so that is a data
migration and belongs to its own commit. `CommitmentIcon` is the seam — one
widget, so the vocabulary changes in one file.

### Pause, and the schema change under it

The last missing action, and the only remaining work that could damage a
database. Logic verified: `flutter analyze` clean, `tool/check_arch.sh` clean,
355 tests pass (332 before, 23 new). **Not feel verified.**

**The trap was real, and it was silent.** `CommitmentState.paused` exists on
the model and has never had a single reader — `lib/domain/` consults
`PausePeriods` and nothing else (`recurrence_engine.dart:34`,
`accounting_engine.dart:162`). A Pause button wired to the flag would show the
banner, flip the menu to Resume, and let the engine go on expecting a run every
day, banking a miss for each one. It is the archive bug's exact shape, and it
would have passed every screen-level test.

So the test that carries the claim goes through the menu and then resolves
**sixty days past the pause**, asserting nothing resolves at all. Verified
non-vacuous the hard way: making a pause cover only its own first day fails
twelve of the nineteen tests in `pause_test.dart`.

**Schema v3: `pause_periods.to_day` becomes nullable.** "Pause until I resume"
is the common case — an injury, a trip of unknown length — and making the user
name a return date turns a pause into a second thing to be late for. Null
rather than a far-future sentinel, because a sentinel leaks: into `covers()`,
into any arithmetic over the span, and into the backup file, which
`backup_codec.dart` keeps human-readable precisely so a damaged one can be
repaired by hand. A reader finding `"to": "9999-12-31"` has to know the
convention; a reader finding `"to": null` does not.

SQLite cannot drop NOT NULL in place, so v3 is a `TableMigration` rebuild.
`migration_test.dart` now carries a real v2 fixture — DDL dumped from a live
v2 `sqlite_master`, not retyped — and asserts across the rebuild that every
existing pause keeps its id and its dates, that a dated pause does not become
open-ended, that the foreign key still cascades into the recreated table, and
that a null `to` is storable afterwards. Removing the migration step fails that
last one, which is the check that the whole thing exists for.

**The format contract cost more than the column, as expected.**
`BackupDocument.currentVersion` is 2. That number's only job is refusal: a
build that reads only v1 must not take a null `to` for a corrupt record, and
"update the app and try again" is the honest answer. v1 files still import,
because a v1 pause always carried a date. `"to": null` is written explicitly
rather than the key omitted — otherwise "still paused" and "field lost in a
truncated write" are the same bytes — while the *reader* accepts both
spellings, since someone repairing a file by hand is as likely to delete the
line as to type `null`.

**At most one open pause per commitment.** Two would both cover every future
day, and resuming would close one and leave the other still suspending
everything — a state the user can neither see nor escape. Starting a pause
closes any open one the day before the new one begins; pausing and resuming on
the same day leaves a pause covering nothing, and that row is deleted rather
than stored, for the same reason `updateCommitment` amends rather than closing
a schedule at `on - 1`. The closing helper is plural and unconditional despite
the invariant, because a database restored from a hand-edited backup can arrive
holding two, and repairing that quietly beats honouring it.

Resume invalidates rollups from the pause's **start** rather than from the
resume date. Only later days change status, so the narrow range would do — but
a rollup is a cache, and rebuilding a few extra days costs less than one stale
row that nothing ever corrects.

`_resolutionVersion` did **not** move. The rule is unchanged; only the data is.

### The emoji become glyphs

The loudest finding of the device pass: full-colour emoji were the brightest
thing on a deliberately muted screen, a row of saturated pictograms shouting
over type chosen to be quiet. Logic verified: 374 tests pass (355 before, 19
new). **Not feel verified.**

**Schema v4 is data, not shape.** `commitments.icon` is the same TEXT column it
always was; what changed is that it holds a key rather than a picture. The
migration is a plain `UPDATE` per known emoji, so nothing in it can fail on a
constraint.

The mapping table is fourteen entries and is **exhaustive over what could
actually be stored** — the seven add-screen templates plus the fourteen the
synthetic seeder wrote — not a general emoji dictionary. U+FE0F is stripped
before every lookup, in Dart and in the migration's SQL, because `🏋️` and `🏋`
are different strings for one picture and the seeder happened to write the
first. Anything outside the table is **left exactly as written**, and
`CommitmentIcon` still draws it as text: replacing a user's own mark with the
nearest glyph would be destroying something the migration had only guessed at.
Three migration tests cover that split — recognised, variation-selected, and
unknown.

**No backup-format bump for this**, and the reason is worth recording next to
the one that did bump. An icon is a display value: an older build meeting an
unknown key draws the raw string and carries on. A nullable `pause.to` is a
*record* an older build would misread. `currentVersion` is for the second kind.
Import still normalises, so a restore converges on the vocabulary rather than
reintroducing emoji.

**Where the vocabulary lives is the part most likely to matter later.** The
keys and the legacy mapping are in `lib/domain/model/commitment_icon.dart`
because they are a data contract — the set of legal values for a stored field
— and a data contract belongs beside the model it constrains, not in the widget
that happens to draw it. `lib/app/glyphs.dart` holds only key → `IconData`, so
redrawing the marks as bundled vectors later moves nothing stored.

Twenty-eight outlined Material glyphs, chosen over hand-drawn SVG paths from
the board: they are in the font already, cost no asset and no dependency, and
scale with the user's text size, which a fixed-box SVG would not.

**`GlyphPicker` replaced two free-text inputs, not one.** The add screen only
ever offered seven template icons — but the edit sheet had a 64px `TextField`
that accepted *any* string, which is how a row ends up wearing a hand-typed
emoji that renders differently on every device and, since the value is
serialised into the backup, keeps doing so forever. Both now write keys.

Two things fell out of it. Clearing a mark needed a real `clearIcon` flag
through `updateCommitment`, because a null `icon` already means "unchanged" and
one value cannot carry two meanings — the old text field could not clear one
either, so this is a fix rather than a regression avoided. And the edit sheet
had to become scrollable with the picker collapsed by default: twenty-eight
swatches open by default pushed Save off a short screen, which the existing
frequency test caught immediately.

### The detail screen stops being a wall of numbers

The last of the four screen boards. Logic verified: 383 tests pass (374
before, 9 new). **Not feel verified.**

**Fifteen figures at one weight is not information, it is a wall.** The screen
now opens with the one number the user came for — this month's consistency, at
display size — and the line under it states the denominator: "Of 29 scheduled
days this month". A percentage with no stated base is a number nobody can argue
with or learn from. With nothing settled it reads an em dash and "Nothing has
settled this month yet", never 0%: a month still being lived has no
consistency, and drawing that as zero is a verdict delivered early — the same
rule the Today headline follows.

**The thirty undated circles were the real loss.** They showed a *sequence* —
this, then this, then this — with nothing to hang it on, so a gap could not be
placed in a week or a month and therefore could not be learned from. The
twelve-week grid answers the question that strip was really being asked: *when
do I drop this?*

Two things in it are load-bearing:

- It is anchored to a **week start**, not to "today minus 83". Off by even a
  day and each row of the grid holds a different weekday, which destroys the
  one pattern the grid exists to show. A test pins `gridStart.weekday == 1`.
- A **period** commitment's grid marks only where completions landed, never a
  per-day status, and its legend reads "Counted toward a target" rather than
  "Done". Same two shapes and the same wording as the week grid on History,
  and for the same reason: a 4×/week target has no opinion about which days it
  is met on, so painting one "done" would claim that day was owed. The test
  asserts every grid day's status is null for such a commitment.

Every mark is a shape before it is a colour — solid, half-filled, bare ring,
dot, faint block — so the grid still reads with no colour vision at all. Future
cells are checked *before* status, so a pending occurrence in the current week
cannot borrow a failure's shape. All eighty-four cells carry a dated semantic
label, because this grid is the only place on the screen that says what
happened on a *particular* day.

**The latest note is quoted at the foot.** The user's own words about their own
week are worth more than another figure, and until now the only way to see one
was to long-press the row it belonged to and open a dialog.

**Four geometry tests now cover this screen**, at 320dp, 1.8× text scale, both
at once, and landscape — scrolling the whole thing each time, since the grid
sizes its cells to the width it is handed and an overflow only appears once it
is on screen. This screen is reached by a push, so it was never in the polish
suite's list of four tab screens; that gap is how an overflowing grid could
have shipped without a single test noticing. One bug turned up immediately: the
note's rule needed `IntrinsicHeight`, because a stretched `Row` inside a
`ListView` asks for infinite height.

**One thing not taken from the board.** Its subtitle reads "Every day · since
12 December 2025", and the frequency half is missing here. `ResolvedHistory`
carries no schedules, and widening a type shared by history, analytics and
insights so one subtitle could name a frequency would make three screens pay
for a label only this one shows. What is there instead is what can be said
truthfully from the occurrences already resolved: the period for a period
target, and the start date always.

### Close-out: two guards, and one rename not done

Logic verified: 399 tests pass (383 before, 16 new). **Not feel verified.**

**The rollup logic stamp now includes the calendar.** `timezoneName`,
`dayBoundaryHour` and `weekStartsOn` join the scoring weights, read straight
off the resolution service's own calendar rather than by injecting
`AppSettings`. These three are the ones with teeth. A rollup is a cached answer
to *what happened on this date*, and each of them changes what a date **is**:
move the boundary from 04:00 to midnight and every late-night completion shifts
a day; change the zone and the same instants land on different days; change the
week start and every weekly target is scored over a different seven days. In
none of those cases does a single stored row move — so the staleness watermark,
which tracks changed *data*, sees nothing at all, and every rollup would go on
contradicting the engine silently. Three tests cover it and reverting the change
fails exactly those three. Still latent: `appSettings` is a hardcoded constant
with no runtime source, so nothing can change these yet. This is the cheap half
of the day the timezone becomes device-derived.

**The raw `scheme.*` call sites were a decision, not a rename.** All 38 already
resolve to the right palette value, and 34 of them are `onSurfaceVariant` —
Material's role for de-emphasised text on a surface, which is precisely the
question a caption is asking. Rewriting those as `palette.ink2` would swap a
semantic role for a palette index and read worse at every call site.
`StatusColors` and `BandColors` earn their existence because Material has no
role for "a missed day" or "a weak week"; it does have one for quiet text.

What was genuinely missing was any guard on the mapping. Thirty-four widgets
trusted `onSurfaceVariant` to be `ink2`, and nothing anywhere said so — one
line in `riyazTheme` could have re-tinted every caption in the app with no test
failing. `theme_contract_test.dart` now pins every role the app leans on, in
both brightnesses, and asserts that **nothing anywhere reads as red**:
`ColorScheme.fromSeed` supplies a real red for `error` unless it is overridden,
and one un-overridden role is all it takes to put a validation red on a screen
that has none. Dropping two overrides fails four of its tests.

Two call sites did move. `TrendChart` was asking `scheme.primary` for its line
and `scheme.outlineVariant` for its grid. Those give the right colours today —
the contract test now pins that — but they are UI roles: primary is the colour
of a button, and a chart that borrows it re-tints itself the day the button
does. A plotted series and the rule under it are graphics, so they take graphic
values.

**`CLAUDE.md` said "No code yet".** It had described an empty repository since
before the first commit, which is the first thing a new session reads. Fixed.
