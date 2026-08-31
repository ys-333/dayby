# Notifications — spec and build plan

**Status:** spiked, not built. `flutter_local_notifications ^22.3.0` is in,
the manifest and Gradle are wired, and a throwaway spike is installed on the
iQOO awaiting a delivery observation. No phase in §9 has started.
**Decision 1 (the package) is answered — yes**, 2026-09-01. Decision 2 (weekly
review in the first cut) is still open and gates nothing before Phase 2.
**Supersedes:** the four unspecified mentions in
`docs/specs/2026-08-28-consistency-tracker-v1.md` (`:1593`, `:1633`, `:1668`,
`:1785`), which name the feature and design none of it.

---

## 1. The problem

Every number in Riyaz depends on the user tapping. Nothing is measured
automatically — no sensor, no integration, no inference. The accounting rules
are unforgiving about that:

- the day closes at 04:00 and unchecked occurrences become MISSED
- consistency denominator = elapsed expected occurrences
- recovery time is measured from the first miss

So **"I forgot to open the app" and "I didn't do the thing" produce identical
rows.** Both land as MISSED, both enter the denominator, both drag the two
figures `CLAUDE.md` calls the headline. Nothing downstream can separate them,
and neither can the user reading the yearly screen six months later.

That makes forgetting-to-tap a **data-correctness** problem, which sits at the
top of this project's conflict-resolution order. Backfill is the cure that
exists today, and it depends on remembering on Thursday what happened on
Tuesday — the thing people are worst at.

The home-screen widget is a partial answer and not a sufficient one: it is
**passive**. It works only if the user's eyes land on that launcher page before
04:00. A notification is **active** — it arrives.

## 2. Scope

Three separate features share the word "notification". This spec builds one,
designs the second, and defers the third.

| | Feature | This spec |
|---|---|---|
| **A** | **Daily reminder** — one notification, user-set time, today's expected commitments | **Build** |
| **B** | **Weekly review nudge** — fires when a week closes, carries the number, opens `WeekReviewScreen` | **Build** (the screen already exists and is currently unreachable at the moment it is about) |
| **C** | **Per-commitment reminders** — the spec's `Reminder` entity, "Gym at 18:00" | **Defer** |
| **D** | **Day-close warning** — "day closes in an hour, 2 open" | **Defer** |

**Why C is deferred.** It multiplies notification volume by commitment count.
The synthetic seeder models ~20 commitments; twenty notifications a day is how
an app gets muted, and a muted app loses A and B as well. It also needs a
schema table, a per-commitment UI in More Options, and its own scheduling
horizon. Revisit once A has been lived with.

**Why D is deferred.** It is the strongest one for data integrity and the most
likely to feel like nagging. Ship it later, opt-in, off by default — after A has
proved the delivery mechanism works.

## 3. Blocking discovery: settings do not persist

`lib/app/providers.dart:26`:

```dart
@Riverpod(keepAlive: true)
AppSettings appSettings(Ref ref) => const AppSettings();
```

`AppSettings` is a compile-time constant. The Settings screen renders "Day
starts at" and "Timezone" as `enabled: false` tiles because there is nothing
behind them to write to. **The app has no preference persistence of any kind.**

A reminder time is a preference that must survive a restart, so Phase 0 builds
that layer. It is a genuine prerequisite, not scaffolding — and the dark-mode
toggle needs precisely the same piece, so the cost is shared across both
features.

### The trap, and the way around it

`accountingCalendarProvider` watches `appSettingsProvider`, and the entire
engine graph watches *that*. Making the settings provider `Future`-returning
would turn every downstream provider async and ripple into every screen and
every widget test.

**Load settings before `runApp` and override the provider**, exactly as
`tzdata.initializeTimeZones()` is already handled:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  final db = AppDatabase(openConnection());
  final settings = await SettingsRepository(db).load();   // once, at startup
  runApp(ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      appSettingsProvider.overrideWithValue(settings),
    ],
    child: const RiyazApp(),
  ));
}
```

Every downstream provider stays synchronous. Writes go through a notifier that
persists and then invalidates, so the graph rebuilds — the same one-way flow the
app already uses.

## 4. The central design decision: pre-render, do not wake

**Question.** At 08:00, with the app not running, how does a notification know
that three commitments are expected today?

**Rejected — headless Dart isolate.** WorkManager wakes a Dart entrypoint, opens
a second Drift connection, initialises the timezone database, runs the
recurrence and accounting engines, composes the text, posts the notification.
This is a second SQLite connection to a file the foreground may hold, a second
initialisation path that can drift from `main()`, and a large surface that is
almost impossible to test. `lib/features/widget/widget_payload.dart` records
that this cost was already weighed and refused once, for widget completion.

**Chosen — pre-render and hand to the OS.** While the app is in the foreground,
compute the next N days of notifications, render each to final text in Dart,
and hand them to Android with a fire time. The OS posts them with **no Dart
running at all**.

This is the same architecture as the widget, and for the same reason: every
string is decided in Dart where the accounting rules live, and the native side
does no arithmetic. One implementation of the scoring rules, not two.

### What it costs: staleness

A notification composed last night can be wrong by the time it fires. Three
mitigations, in order of importance:

1. **Reschedule on every foreground resume and every tracking write.** Both
   moments have the app alive, the DB open and the engines available. This is
   where correctness actually comes from.
2. **Cancel when the day is finished.** When a write leaves `TodayView` with no
   pending items, cancel today's reminder. The app is running at that instant,
   so this is always possible and it kills the worst failure mode — being
   reminded to do what you have already done.
3. **Fire early in the day.** The reminder default is morning; the accounting
   day opened at 04:00. The window in which the user acts *before* the
   reminder — and thus the window in which staleness matters — is small by
   construction. (This is precisely why **D** is harder: an evening warning has
   a whole day of drift behind it.)

Residual risk, accepted and written down: a user who tracks on day 1, never
opens the app on day 2, and receives day 2's reminder gets text composed on day
1. It will name the right commitments, because the schedule is the source of
truth and the schedule was already known. It can only be wrong about what has
been *completed* — and nothing was completed on a day the app never opened.

### Scheduling horizon

Schedule **7 days** ahead, replacing the whole set on every reschedule. Long
enough that a user who does not open the app for a week keeps being reminded;
short enough that pre-rendered text cannot drift far from the schedule that
produced it. Android's per-app limit on pending alarms is far above 7.

## 5. What the user sees

Anti-nag rules, non-negotiable, because a tracker that scolds gets uninstalled
and the history is the asset:

- **Informational, never evaluative.** State what is true. Never "don't break
  your streak", never a guilt clause. This is the same product stance that made
  streaks deliberately not the headline metric.
- **Never fires with nothing to say.** No expected commitments, everything
  already done, everything paused, or all-skipped → **no notification at all.**
  "Nothing today" is pure noise and it is how an app trains its user to swipe
  without reading.
- **No count that outlives its truth.** Copy names the commitments; the count is
  derived from that list, so both go stale together or not at all.

### A — Daily reminder

Collapsed:

```
┌────────────────────────────────────────────┐
│ ◐ Riyaz · 8:00                             │
│ Today                                      │
│ Meditate, Read, Gym                        │
└────────────────────────────────────────────┘
```

Expanded (`BigTextStyle`), when more than three:

```
┌────────────────────────────────────────────┐
│ ◐ Riyaz · 8:00                             │
│ Today · 5 commitments                      │
│ Meditate                                   │
│ Read                                       │
│ Gym  ·  2/4 this week                      │
│ Journal                                    │
│ Stretch                                    │
└────────────────────────────────────────────┘
```

- Title: `Today` when ≤3, `Today · N commitments` when more.
- Body: names, comma-joined, in the same order Today renders them.
- Period commitments carry their progress (`2/4 this week`) because that is the
  number that decides whether today matters for them.
- **Tap** opens the app deep-linked to Today. Nothing else.
- **No action buttons in V1** — a "Done" button would have to write a tracking
  event from a background isolate, which is the cost §4 refuses. When the
  isolate question is reopened, action buttons and widget completion should be
  reconsidered together, since they need exactly the same machinery. Note also
  that a notification write is user-triggered by tapping, so it would need undo,
  and there is no surface to offer undo on.

### B — Weekly review

Fires on the first morning after a week closes, at the same configured time.

```
┌────────────────────────────────────────────┐
│ ◐ Riyaz · 8:00                             │
│ Last week — 84%                            │
│ Up from 78%. Strongest: Meditate.          │
└────────────────────────────────────────────┘
```

- Tap opens `WeekReviewScreen` at `/review` for the week that closed.
- The comparison clause is dropped when there is no prior week to compare.
- The "strongest" clause is dropped when `WeekReview.namesAreMeaningful` is
  false — the controller already makes that judgement and it must not be
  second-guessed here.
- Never phrased as a decline. "Down from 78%" is a fact and is allowed;
  "you slipped" is not.
- On a day carrying both A and B, post **B only**, and let it carry today's
  count in the expanded body. Two notifications at the same minute is one too
  many.

### Settings screen

New section, sitting above `Accounting`:

```
Reminders
  ├─ Daily reminder            [ off ⟵⟶ on ]
  ├─ Remind me at              08:00
  └─ Weekly review             [ off ⟵⟶ on ]
```

Both default **off**. The permission prompt is requested on first enable, never
at startup — asking before the user has expressed interest is how apps get
permanently denied.

If the OS permission is denied, the toggle reverts to off and the subtitle says
so plainly, with a route to system settings. A toggle that reads "on" while the
OS blocks delivery is a lie the user cannot debug.

## 6. Data model

### `app_settings` table (schema v5)

Single-row key-value, not a typed column per setting: it absorbs the dark-mode
preference, and later C and D, without another migration each time.

```dart
class AppSettingsRows extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  @override
  Set<Column> get primaryKey => {key};
}
```

Keys added here: `reminder.daily.enabled`, `reminder.daily.time` (`HH:mm`),
`reminder.weekly.enabled`. Absent key → the default in `AppSettings`, so the
migration creates an **empty** table and no backfill is needed.

Migration step, following the established pattern in `app_database.dart`:

```dart
if (from < 5) {
  // v5 adds user preferences. Empty on creation: every key falls back to the
  // default already compiled into AppSettings, so there is nothing to backfill
  // and nothing that can fail.
  await m.createTable(appSettingsRows);
}
```

### Backup format — unchanged, deliberately

`BackupDocument.currentVersion` **stays 2**. Its doc comment states the
admission rule: interpretation settings travel with the data because a stored
civil date is ambiguous without the timezone and day boundary. A reminder time
interprets nothing — restoring a backup onto a new phone and finding the
reminder at its default is correct behaviour, not data loss. Bumping the format
version for a preference would force every older build to refuse the file, for
nothing.

The same argument governs the dark-mode preference. Write it down there too.

## 7. Architecture

Domain purity is enforced by `tool/check_arch.sh`, so the split is forced and
is also the right one:

```
lib/domain/notifications/
  reminder_schedule.dart     PURE. (settings, calendar, clock) → List<PendingReminder>
  reminder_copy.dart         PURE. TodayView / WeekReview → title + body + expanded

lib/data/
  settings_repository.dart   load/save the app_settings table
  notification_gateway.dart  interface + real plugin impl + in-memory double

lib/features/notifications/
  reminder_scheduler.dart    composes the three; called on resume and on write
```

Four points that matter:

- **`reminder_schedule.dart` is pure and fully unit-testable.** "Given a
  reminder at 08:00, the Asia/Kolkata zone, a 04:00 day boundary and a clock at
  Tuesday 21:00, what are the next seven fire instants?" is a deterministic
  question with a table of answers — including across DST and across a day
  boundary the reminder time sits *before* (a 03:00 reminder belongs to the
  previous accounting day, and the tests must pin that).
- **Fire times are `tz.TZDateTime`.** `flutter_local_notifications` schedules in
  `package:timezone`, which this project already depends on and already
  initialises. The zone comes from `AccountingCalendar.zone` — never from a
  fresh lookup, or the notification and the accounting engine could disagree
  about the same day.
- **`NotificationGateway` is an interface with an in-memory double.**
  `docs/PROGRESS.md` records that widget tests run in a fake-async zone where
  real I/O never completes, which is why `BackupFileStore` exists in that shape.
  A plugin call has the same property. Follow the existing pattern.
- **Every gateway failure is swallowed and logged**, as `WidgetBridge` already
  does. A denied permission, a launcher-less platform or a test must never break
  the app running in front of the user.

## 8. Android platform work

| Item | Detail |
|---|---|
| Desugaring | **`isCoreLibraryDesugaringEnabled = true`** plus `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs")` in `android/app/build.gradle.kts`. The plugin compiles against `java.time`, absent below API 26; without this the build fails at `:app:checkDebugAarMetadata`. Found by the spike, not predicted. Desugaring is what lets `minSdk` stay at 24 rather than dropping Android 7 to gain reminders. |
| Permission | `POST_NOTIFICATIONS` — declared by the plugin itself since v16, so nothing to add; runtime request on first enable (required at targetSdk ≥ 33, and this app targets 36) |
| Exact alarms | **Not used.** `AndroidScheduleMode.inexactAllowWhileIdle` — a habit reminder does not need minute precision, and this avoids `SCHEDULE_EXACT_ALARM` entirely, along with its Play Store justification and its user-revocable toggle. Delivery may drift by minutes under Doze; that is acceptable and should be stated in the settings subtitle. |
| Reboot | `RECEIVE_BOOT_COMPLETED` + the plugin's boot receiver, or every reminder dies at the next restart. **Verified on device 2026-09-01**: reminders are re-registered at their original fire time — but only after the user *unlocks* the phone. Android sends `LOCKED_BOOT_COMPLETED` before unlock and `BOOT_COMPLETED` only after it, so a phone rebooted overnight and left on the lock screen has no reminders registered until it is next unlocked. An 08:00 reminder on a phone unlocked at 09:00 is therefore at risk; whether the plugin fires it late or drops it is **untested** and worth pinning before Phase 6. |
| Channel | One channel, `riyaz.reminders`, default importance — no sound escalation |
| Icon | Monochrome small icon; Android silhouettes it, so a coloured asset renders as a white blob |
| Deep link | `go_router` already routes `/review`; the payload carries the route and `MainActivity` is already `singleTop` |

## 9. Task breakdown

Ledger conventions apply: `[x]` requires evidence — unit / widget / migration /
build / device — never a successful compile. Built-but-unverified is `[!]` and
nothing may be built on it.

### Phase 0 — Settings persist (prerequisite; also unblocks dark mode)

- [ ] `app_settings` table + schema v5 migration — `migration`
- [ ] `SettingsRepository` load/save, defaults on absent keys — `unit`
- [ ] `main()` loads before `runApp`; providers overridden and still synchronous — `widget`
- [ ] A settings write round-trips across an app restart — `unit`
- [ ] Existing 436 tests still green — the provider graph changed shape

### Phase 1 — Domain: when does it fire

- [ ] `PendingReminder` + `reminder_schedule.dart` — `unit`
- [ ] Next-7-days computation from a `FixedClock` — `unit`
- [ ] DST spring-forward and fall-back around the reminder hour — `unit`
- [ ] A reminder time *before* the 04:00 boundary belongs to the previous accounting day — `unit`
- [ ] Weekly review fires the first morning after week close, honouring `weekStartsOn` — `unit`

### Phase 2 — Domain: what does it say

- [ ] `reminder_copy.dart`: `TodayView` → title/body/expanded — `unit`
- [ ] Empty, all-done, all-paused and all-skipped days each produce **no notification** — `unit`
- [ ] Period commitments carry `2/4 this week` — `unit`
- [ ] `WeekReview` → review copy; comparison and "strongest" clauses dropped when unavailable — `unit`
- [ ] Same day carrying A and B posts B only — `unit`

### Phase 3 — Gateway

- [ ] Add `flutter_local_notifications` — **needs approval** (§11)
- [ ] `NotificationGateway` interface + in-memory double — `unit`
- [ ] Real implementation: channel, permission request, `zonedSchedule`, cancel-all — `build`
- [ ] Manifest permissions + boot receiver + monochrome icon — `build`
- [ ] Failures swallowed and logged, never rethrown — `unit`

### Phase 4 — Wiring

- [ ] Reschedule on foreground resume — `widget`
- [ ] Reschedule on every tracking write — `unit`
- [ ] Last pending item completed → today's reminder cancelled — `unit`
- [ ] Changing the day boundary or timezone reschedules everything — `unit`
- [ ] Tap payload deep-links to Today and to `/review` — `widget`

### Phase 5 — Settings UI

- [ ] Reminders section, both toggles, time picker — `widget`
- [ ] First enable requests permission; denial reverts the toggle and says why — `widget`
- [ ] Off by default on a fresh install — `widget`

### Phase 6 — Device (yours, not Claude's)

- [ ] A reminder actually arrives, next morning, at the set time
- [ ] It survives a reboot
- [ ] It survives an overnight Doze
- [ ] Tapping it lands on the right screen
- [ ] **Feel:** is it useful or is it nagging? This is the only question that
      decides whether the feature ships, and no test can answer it.

Phases 1 and 2 are pure and can be written and tested with no device and no
package — they are the safe majority of the work. Phase 0 is the largest single
chunk and the one that touches existing code.

## 10. Risks

- **Phase 0 ripples.** The provider graph changes shape and 436 tests run
  through it. Mitigated by the override-at-startup approach in §3, which keeps
  every provider synchronous, but the risk is real and the phase should land on
  its own commit with the full suite green before Phase 1 starts.
- **Staleness.** Bounded by §4 and not eliminated. If device use shows it
  matters more than argued here, the answer is a shorter horizon plus a
  rescheduling alarm, not an isolate.
- **OEM battery killers.** Xiaomi, OnePlus and others silently drop scheduled
  alarms for background-restricted apps. Nothing in the app can fix this. If it
  bites on your device, the settings subtitle should say so rather than the app
  pretending delivery is guaranteed.
- **Inexact delivery drifts by minutes, measured.** On the device spike Android
  gave a 15-minute-out reminder an 11-minute scheduling window and delivered it
  at the tail of that window, ~3.5 minutes after the nominal time. A reminder at
  "08:00" may therefore arrive at 08:04. Acceptable for a habit nudge, but the
  settings copy should not promise a precise time.
- **A stale APK can certify a false result.** `docs/PROGRESS.md` records this
  exact failure from the widget check. Rebuild and reinstall immediately before
  any Phase 6 observation.

## 11. Decisions needed before Phase 3

1. **`flutter_local_notifications` — yes or no?** `CLAUDE.md` forbids adding a
   package unasked. There is no realistic alternative: the platform work is a
   notification channel, an alarm scheduler, a boot receiver, a permission
   flow and a tap-payload router, on two API-level branches. Hand-rolling it
   over a `MethodChannel` — the reasoning that correctly kept `WidgetBridge`
   dependency-free for a thirty-line Kotlin file — does not transfer to
   something this size. **Recommend: yes.**

2. **Is B (weekly review) in the first cut, or only A?** B is cheap because
   `WeekReviewScreen` and `week_review_controller.dart` already exist and are
   currently unreachable at the moment they are about, which is most of their
   value. It adds Phase 2 copy work and one scheduling rule. **Recommend: yes,
   include it.**

Phases 0, 1 and 2 need neither decision and can start immediately.
