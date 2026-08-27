# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Riyaz — daily consistency tracker (Flutter)

Personal Android app. Offline-first, local-only, no backend, no auth in V1.
Core loop: open → tap today's commitments → close, in under 10 seconds.
When two UX options exist, pick the one with fewer taps.

## Repository state

No code yet — the repo holds only `docs/specs/2026-08-28-consistency-tracker-v1.md`,
a ~3000-line product + engineering spec. Not a git repository yet.

The spec is the product source of truth: worked accounting examples, screen
layouts, empty states, definition of done. Two caveats when reading it — it
predates the Flutter decision and prescribes a Kotlin/Compose/Room stack
(ignore that; the stack below wins), and it calls the app "Consistency OS".
Product rules and accounting semantics still apply as written.

## Stack
- Flutter 3.47.0 (stable) / Dart 3.13.0 — installed at `~/development/flutter/bin`,
  which is NOT on the login PATH; export it in your shell before running commands
- State: Riverpod (code-gen), Freezed for models
- DB: Drift (SQLite), migrations required — never `deleteOnSchemaChange`
- Routing: go_router
- Dates: package:timezone — see rules below

## Environment (this machine)

Neither toolchain is on the login PATH. Every command below needs:

```sh
export PATH="$HOME/development/flutter/bin:$PATH"
export JAVA_HOME=/opt/homebrew/opt/openjdk@17   # only Gradle/APK builds need this
export PATH="$JAVA_HOME/bin:$PATH"
```

Without `JAVA_HOME` the Gradle build fails with "Unable to locate a Java
Runtime". `flutter analyze` and `flutter test` do not need Java.

## Commands
- Run: `flutter run -d <device>`
- Test: `flutter test`
- Single test: `flutter test test/path_test.dart --plain-name "description"`
- Codegen: `dart run build_runner build --delete-conflicting-outputs`
- Analyze: `flutter analyze` — must be clean before you say a task is done.
  A Stop hook (`.claude/hooks/flutter-analyze.sh`) enforces this; it no-ops
  until `pubspec.yaml` exists and `flutter` is on PATH.

## Architecture
- `lib/domain/` — pure Dart. No Flutter imports, no Drift imports. The
  recurrence and analytics engines live here and are unit-tested.
- `lib/data/` — Drift tables, DAOs, repositories.
- `lib/features/<name>/` — UI + controllers, one folder per screen area.
- Domain never imports data or UI. Enforce it; don't drift on this.

Domain splits into: recurrence (schedule + date → expected/not-expected/paused,
or the applicable period), tracking (user actions → events), accounting
(status resolution, period closure), analytics (consistency, streaks,
recovery, rolling trends), time (Clock, timezone, day boundary).

### Canonical vs derived
Canonical: commitments, schedules, tracking events, pause periods.
Derived and rebuildable: daily/weekly/monthly rollups, analytics.

Rollups are materialized — the yearly screen must never scan raw events on
render. A tracking-event write recalculates the affected day rollup, then the
affected period. Keep a path that rebuilds all derived data from canonical
records; treat a rollup as a cache, never as truth.

## Domain rules (get these wrong and every number in the app is wrong)
- The **schedule** is the source of truth for what was expected, never the
  stored records. Never derive expectations from what exists in the DB.
- Schedules are **effective-dated**. Changing a commitment's frequency must
  not alter historical consistency. Past dates evaluate against the schedule
  in effect on that date.
- Consistency denominator = **elapsed** expected occurrences only. Future
  dates are never in the denominator. Today is not in it until day close.
- **Day boundary is 4 AM local**, user-configurable — not midnight.
  Nothing becomes MISSED before the day closes.
- **SKIPPED is excluded from the denominator entirely** (not scored as 0).
  PAUSED days are NOT_EXPECTED, not misses.
- Scoring weights: done 1.0, partial 0.5. Keep in one place so it can change.
- Weekly/monthly commitments are scored over their **period**, not per day.
  "Gym 4x/week" is never missed mid-week. The denominator is the target (4),
  not the day count (7), and the period result is final only at period close.
- Archiving preserves history. Never rewrite or delete past records.

Statuses: PENDING, DONE, PARTIAL, MISSED, SKIPPED, PAUSED, NOT_SCHEDULED.

The one formula, centralized — never re-derived in a widget:
`weighted completion / eligible expected`, where eligible expected =
expected − skipped − paused − not-scheduled − future − pending.
Skips are surfaced separately in the UI rather than hidden.

## Time
- No `DateTime.now()` inside `lib/domain/` — ever. Inject a `Clock`.
  Untestable otherwise, and the month/year/DST tests are the point.
- Store dates as local civil dates (`yyyy-MM-dd` string or epoch day) for
  scheduling. Store event timestamps as UTC millis. Don't mix the two.

## Conventions
- `flutter_lints` + `always_specify_types: false`. Prefer records over
  tuple-ish classes.
- Every write the user can trigger by tapping needs undo.
- Domain logic changes require tests in the same commit.
- Don't add a package without asking — dependency count stays low.

## Product constraints that shape implementation
- One-tap Done from home and the widget; long-press reveals Partial / Skip /
  Add Note / Edit. Add-commitment is a single screen, 2–3 taps by default,
  with quick templates; advanced options stay behind "More options".
- Backfill and past-day editing are first-class, and they recalculate the
  affected rollups.
- Insights are rule-based only, gated behind data thresholds (~3 completed
  streak cycles, or ~21 days of usable history). Show "not enough data yet"
  rather than manufacturing a pattern.
- Streaks are shown but are deliberately not the headline metric — long-run
  consistency and recovery time are.
- Status is never conveyed by colour alone: pair with shape/fill/icon
  (✓ ◐ × — ○) and semantic labels. Future days render outline-only, never as
  failure.
- A dev-only synthetic seeder (365 days × ~20 commitments, with realistic
  misses, partials, skips, pauses, schedule changes) is required early —
  analytics screens are otherwise uninspectable for months.
- JSON export + validated import ship in V1. Local-only data with no backup
  path means one lost phone erases years of history.

## Not in V1
Social, leaderboards, AI coach, cloud sync, auth, subscriptions.
Don't scaffold for them.

## Tracking progress

`docs/PROGRESS.md` is the build ledger — what is done and **how it was verified**.
Update it in the same commit as the work. Rules that matter:

- `[x]` requires evidence (unit / widget / migration / build / device), not a
  successful compile. Built-but-unverified is `[!]` and nothing may be built on it.
- "Logic verified" (tests pass) and "feel verified" (fast and unannoying on a real
  phone) are separate claims. Claude certifies the first and never the second.

## Build order
Foundation → domain engines + seeder → core tracking → period targets →
history screens → analytics → insights → widget → export/import → polish.
Domain engines get deterministic and tested before screens get built.

Resolving contradictions:
`data correctness > historical integrity > low-friction UX > visual polish > extra features`
