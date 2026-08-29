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
./tool/check_arch.sh && flutter analyze && flutter test     # expect 253 green
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
| `lib/data/` | Drift schema v2, repositories, backup codec, seeder loader |
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
**Last verified state:** 253 tests green, `flutter analyze` clean project-wide,
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


---

## Remaining work

Everything left is either a device check only you can do, or a decision only
you can make.

- [ ] **Feel check:** create and track in under 10 seconds on a real phone
- [ ] **Widget device check:** place it, confirm it renders, updates, and that
      tapping opens the app. The Kotlin has never executed.
- [ ] **Export destination decision:** reaching Downloads or a share sheet
      needs `file_picker` or `share_plus`. Blocked on your yes/no.
- [ ] Period-close review UI (what the user sees when a week ends) — designed
      away rather than built; the period result is visible on the history and
      insights screens, but there is no moment-of-closure summary.
