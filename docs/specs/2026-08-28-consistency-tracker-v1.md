# CONSISTENCY OS

## Product + Engineering Specification

Build a native Android application called **Consistency OS**.

The purpose of this application is not traditional task management.

It is a **personal behavioral ledger** that lets a person define the things they want to consistently work on and then objectively see whether their actual behavior matches their intentions over days, weeks, months, and years.

The central philosophy is:

> **Don't make me manage my life. Make it extremely easy to record what actually happened.**

The core interaction should take **less than 10 seconds per day**.

---

# 1. THE PROBLEM

A user decides:

* I want to code every day.
* I want to work on my startup.
* I want to exercise.
* I want to learn.
* I want to read.
* I want to sleep before a certain time.

They may do these things consistently for 4–5 days.

Then life happens.

They miss a few days.

The streak breaks.

They stop.

A few weeks later they start again.

Traditional habit trackers tend to overemphasize streaks and make one missed day feel like failure.

Consistency OS should instead answer:

1. What did I say I wanted to do?
2. What did I actually do?
3. How consistently did I do it?
4. When I fell off, how quickly did I recover?
5. What patterns exist in my behavior?

The goal is **visibility and accountability, not guilt**.

---

# 2. CORE PRODUCT MODEL

The fundamental hierarchy is:

```text
Commitment
    ↓
Effective-dated Schedule
    ↓
Expected Occurrences
    ↓
Actual Tracking Events
    ↓
Daily / Period Rollups
    ↓
Analytics
```

Do NOT build the system around a simplistic:

```text
Commitment → DailyRecord
```

because not every commitment is daily.

For example:

```text
Run every day
```

is different from:

```text
Gym 4 times per week
```

and:

```text
Read 2 books per month
```

These need different accounting models.

---

# 3. CORE TERMINOLOGY

## Commitment

Something the user has decided they want to consistently do.

Examples:

* Work on Otto
* Work on Finmonk
* Run
* Gym
* Read
* Learn AI
* Sleep before midnight
* Meditation

A commitment is NOT a one-time task.

---

## Schedule

Defines when and how the commitment is expected.

Schedules are **effective-dated**.

Example:

```text
Otto

Schedule A
Aug 1 → Sep 30
Every day
Target: 1 session/day

Schedule B
Oct 1 → future
3 times/week
```

Historical data from August must always use Schedule A.

Changing a commitment must NEVER silently rewrite historical accounting.

---

## Occurrence

An expected unit of behavior.

Examples:

Daily:

```text
Run → Aug 28
```

Weekly:

```text
Gym → Week of Aug 24
Target = 4
```

Monthly:

```text
Read → August
Target = 2
```

---

## Tracking Event

What the user actually did.

Examples:

```text
Done
Partial
Skipped
```

For count-based commitments:

```text
+1
+1
```

For duration-based commitments:

```text
20 minutes
```

---

# 4. ACCOUNTING DAY

Do NOT assume midnight is the user's behavioral day boundary.

Implement a configurable:

```text
dayBoundaryHour
```

Default:

```text
04:00
```

Meaning:

```text
Aug 27 accounting day
=
Aug 27 04:00
→
Aug 28 03:59
```

Therefore:

```text
Aug 28 at 01:30
```

belongs to:

```text
Aug 27
```

This is important for late-night work and sleep-related commitments.

The accounting engine must use an injected `Clock` and timezone.

Never call:

```kotlin
LocalDate.now()
```

inside business logic.

---

# 5. COMMITMENT TYPES

Support three primary accounting types.

## TYPE A — DAILY

Example:

```text
Run
Every day
Target: 1
```

Today shows:

```text
Running
○
```

Once completed:

```text
Running
✓
```

---

## TYPE B — PERIOD TARGET

Example:

```text
Gym
4 times/week
```

The system should NOT create four daily expected commitments.

Instead:

```text
Week of Aug 24

Gym
2 / 4 completed
```

The user can tap `+`.

After two sessions:

```text
Gym
2 / 4
```

The remaining target is still open.

It must NOT be considered missed simply because Monday or Tuesday passed.

The period is evaluated only when the period closes.

---

## TYPE C — DURATION

Example:

```text
Work on Otto
Target: 60 minutes/day
```

Allow recording:

```text
15 min
30 min
60 min
```

For V1, duration entry can be simple.

Do not build a sophisticated timer unless it is trivial to add.

---

# 6. FLEXIBLE SCHEDULES

A commitment must support:

### Every day

```text
Daily
```

### Specific weekdays

```text
Monday
Tuesday
Wednesday
Thursday
Friday
```

### X times per week

```text
3 × / week
```

### X times per month

```text
10 × / month
```

### Every X days

Optional if architecture supports it cleanly.

### Custom

Leave room for future advanced recurrence.

---

# 7. EXPECTATION ACCOUNTING RULES

These rules are NON-NEGOTIABLE.

## Future occurrences

Never count future occurrences in consistency calculations.

If today is:

```text
Aug 27
```

then Aug 28–31 do not exist in the denominator yet.

Example:

Monthly daily commitment:

Expected elapsed occurrences:

```text
27
```

NOT:

```text
31
```

---

## Today's unchecked occurrence

Today's occurrence remains:

```text
PENDING
```

until the accounting day closes.

It is not missed yet.

---

## Past unchecked occurrence

After the accounting day closes:

```text
PENDING → MISSED
```

unless the user explicitly skipped it or the commitment was paused.

---

# 8. STATUS MODEL

Support:

```text
PENDING
DONE
PARTIAL
MISSED
SKIPPED
PAUSED
NOT_SCHEDULED
```

Rules:

### DONE

Counts as successful completion.

### PARTIAL

Counts partially according to the commitment's weighting.

Default:

```text
PARTIAL = 0.5
```

Make weighting configurable in the analytics layer.

### MISSED

Counts as zero and remains in the denominator.

### SKIPPED

Does NOT count as failure.

Exclude from denominator.

Show skip count separately.

### PAUSED

Excluded from denominator.

### NOT_SCHEDULED

Excluded.

### PENDING

Excluded until the accounting period closes.

---

# 9. IMPORTANT DISTINCTION: SKIPPED VS MISSED

These must NOT be treated identically.

Example:

User intentionally doesn't run because they are traveling.

They tap:

```text
Skip
```

This should not lower consistency.

But:

```text
Missed
```

means:

> I intended to do it and didn't.

Therefore:

```text
Consistency =
weighted completed occurrences
/
eligible expected occurrences
```

Where:

```text
eligible expected occurrences
=
expected
-
skipped
-
paused
-
not scheduled
-
future
```

Display skipped separately.

Example:

```text
August

Expected: 27
Completed: 20
Partial: 2
Missed: 3
Skipped: 2

Consistency: 78%
```

---

# 10. PERIOD-SCOPED ACCOUNTING

This is critical.

For:

```text
Gym
4× per week
```

Today should display:

```text
🏋️ Gym

2 / 4 this week
```

NOT:

```text
Gym
Missed
```

The week remains open until the week ends.

Similarly:

```text
Read
2 / 3 this month
```

remains open throughout the month.

At period close:

```text
Target: 4
Completed: 3

Period result:
MISSED TARGET
```

The accounting engine should support:

```text
DAILY
WEEKLY
MONTHLY
```

as separate period scopes.

---

# 11. WEEKLY TARGET EXAMPLE

Suppose:

```text
Gym
4× per week
```

User records:

Monday +1
Tuesday +1
Thursday +1

Wednesday nothing.

Thursday:

```text
3 / 4
```

This is NOT a missed day.

At Sunday end:

```text
3 / 4

Period completion:
75%
```

The analytics engine records the period result.

---

# 12. MONTHLY TARGET EXAMPLE

Suppose:

```text
Read
2× / month
```

On August 10:

```text
0 / 2
```

This is not failure.

On August 31:

```text
1 / 2
```

The month closes at:

```text
50%
```

---

# 13. SCHEDULE VERSIONING

Schedules must be separate, effective-dated records.

Example:

```text
Commitment:
Work on Otto

Schedule 1:
effectiveFrom = 2026-08-01
effectiveTo = 2026-09-30
frequency = DAILY
target = 1

Schedule 2:
effectiveFrom = 2026-10-01
effectiveTo = null
frequency = WEEKLY
target = 5
```

When calculating August:

Use Schedule 1.

When calculating October:

Use Schedule 2.

Never recalculate August using Schedule 2.

Historical data must remain immutable in meaning.

---

# 14. HOME SCREEN

This is the most important screen.

The user should open the application and immediately understand:

```text
TODAY
```

Example:

```text
Good evening 👋

Wednesday
Aug 27

TODAY'S PROGRESS

80%

4 / 5
```

Then:

```text
TODAY

💻 Work on Otto
2 / 2 sessions       ✓

💼 Finmonk
1 / 1 session        ✓

🏃 Running
0 / 1                 ○

📚 Learning
1 / 1                 ✓

🏋️ Gym
2 / 4 this week       +
```

The distinction between daily and period commitments must be visually obvious.

---

# 15. ONE-TAP INTERACTION

Default action:

```text
Tap → DONE
```

For count-based commitments:

```text
Tap + → increment
```

For example:

```text
Otto
0 / 2

[ + ]
```

Tap:

```text
1 / 2
```

Tap again:

```text
2 / 2 ✓
```

Do not require opening a detail page.

---

# 16. UNDO

Every write action should support undo.

After:

```text
Running ✓
```

show a Snackbar:

```text
Running marked done     UNDO
```

Undo should restore the previous state.

This is required because one-tap tracking will inevitably create accidental taps.

---

# 17. LONG PRESS

Normal tap:

```text
DONE
```

Long press should reveal:

```text
Mark Partial
Skip
Add Note
Edit
```

This keeps the main interaction fast while retaining flexibility.

---

# 18. OPTIONAL NOTES

Notes should never be mandatory.

Example:

```text
Otto ✓

Add note
```

User may enter:

```text
Implemented SMS categorisation.
```

Notes should be associated with the relevant tracking event/day.

---

# 19. BACKFILLING

Backfilling is a first-class feature.

The user must be able to open a previous day and record what happened.

Example:

```text
Aug 26

Running
[ Mark Done ]

Otto
[ Mark Partial ]

Learning
[ Skip ]
```

This is particularly important for:

* Late-night activities
* Sleep
* Forgetting to open the app
* Offline usage
* Correcting mistakes

Backfilling yesterday must recalculate affected rollups and analytics.

---

# 20. EDITING PAST DAYS

Allow users to edit historical records.

Example:

```text
Aug 20
Running
Missed
```

User realizes:

> Actually, I did run.

They can change:

```text
Missed → Done
```

Historical analytics must update.

---

# 21. PAUSE

A commitment can be paused.

Example:

```text
Running

Pause:
Aug 28 → Sep 3
```

During that period:

```text
NOT SCHEDULED / PAUSED
```

Those dates are excluded from the denominator.

They do NOT count as missed.

---

# 22. ARCHIVE

User can archive a commitment.

Example:

```text
Learning AI

Started:
Jun 1

Archived:
Aug 27
```

Historical records remain.

Never delete historical performance just because a commitment was archived.

---

# 23. HOME-SCREEN WIDGET

Build an Android home-screen widget using **Jetpack Glance** in V1.

The widget is important because the core product promise is:

> Less than 10 seconds to record the day.

Widget example:

```text
CONSISTENCY OS

Today

💻 Otto       ✓
💼 Finmonk    ✓
🏃 Running    ○
📚 Learning   ✓
🏋️ Gym       2/4

Open app
```

The user should ideally be able to complete a simple commitment directly from the widget.

If Android/widget limitations prevent a particular action, tapping the row should deep-link directly to the relevant screen.

---

# 24. CALENDAR / HISTORY

Create a visual calendar.

Example:

```text
AUGUST 2026

M T W T F S S

○ ● ● ● ○ ○ ○
● ● ● ● ● ○ ○
● ● ◐ ● ● ● ○
...
```

However:

**Do NOT rely on color alone.**

Use:

* fill
* outline
* shape
* icons

for accessibility.

---

# 25. CALENDAR THRESHOLDS

For aggregate daily consistency:

```text
>= 80%
Strong

40–79%
Partial

< 40%
Weak
```

Future dates:

```text
outline-only
```

Never use filled red/amber indicators for future days.

Future ≠ missed.

---

# 26. DAILY CALENDAR DETAIL

Tap a day:

```text
Wednesday
Aug 27

Daily consistency
80%

────────────────

💻 Otto
2 / 2
✓ Done

💼 Finmonk
1 / 1
✓ Done

🏃 Running
0 / 1
✗ Missed

📚 Learning
1 / 1
✓ Done

🏋️ Gym
2 / 4 this week
—
```

Allow editing from here.

---

# 27. WEEKLY VIEW

Example:

```text
WEEK
Aug 24 – Aug 30

             M T W T F S S

Otto         ✓ ✓ ✓ ✓ ○ ○ ○
Finmonk      ✓ ✓ ✓ ✓ ○ ○ ○
Running      ✓ ✓ ✗ ✓ ○ ○ ○
Learning     ✓ ✗ ✓ ✓ ○ ○ ○
Gym          + + + + + + +

```

For future days:

```text
outline only
```

Do not visually imply failure.

---

# 28. WEEKLY ANALYTICS

Example:

```text
THIS WEEK

Consistency
84%

Completed
27

Partial
3

Missed
4

Skipped
2
```

Then:

```text
Best commitment

Otto
100%
```

And:

```text
Needs attention

Running
50%
```

Weekly analytics should only include elapsed/closed accounting periods appropriately.

---

# 29. MONTHLY ANALYTICS

Example:

```text
AUGUST

Overall consistency

78%

↑ 14% vs July
```

Then show a trend.

IMPORTANT:

Do NOT use raw daily binary values as the main line chart.

Use a:

```text
7-day rolling consistency
```

for smoother behavioral trend visualization.

Example:

```text
100%
 |
 |        ╭──╮
 |   ╭────╯  ╰──╮
 |───╯           ╰──
 |
 +-------------------
 Aug 1           Aug 27
```

---

# 30. YEARLY VIEW

Example:

```text
2026

Yearly consistency

73%

↑ 9% vs 2025
```

Show monthly consistency:

```text
Jan 72%
Feb 81%
Mar 61%
Apr 89%
May 74%
Jun 68%
Jul 79%
Aug 73%
...
```

Future months must NOT be included in the denominator.

---

# 31. COMMITMENT DETAIL

Example:

```text
💻 Work on Otto

Startup

Started:
Aug 1, 2026

Current streak:
5 days

Best streak:
18 days

This week:
86%

This month:
79%

Last 90 days:
73%

This year:
73%
```

Then:

```text
PERFORMANCE

Completed
42

Partial
8

Missed
11

Skipped
4
```

Then:

```text
CONSISTENCY TREND
```

using the rolling 7-day calculation.

Then calendar heatmap.

---

# 32. STREAKS

Streaks are useful but must NOT be the primary product metric.

Display:

```text
Current streak
5 days

Longest streak
18 days
```

But never make:

```text
STREAK = EVERYTHING
```

The user can miss one day and still have a good long-term consistency score.

---

# 33. RECOVERY METRIC

This is a major differentiator.

Measure:

```text
How quickly does the user return after losing momentum?
```

Example:

```text
Average recovery
1.8 days
```

Suppose:

```text
5 days active
4 days missed
1 day to return
```

Recovery time:

```text
1 day
```

Track this across multiple cycles.

---

# 34. MOMENTUM ANALYSIS

Eventually identify patterns such as:

```text
You usually maintain this commitment
for around 5–6 days before dropping off.
```

Or:

```text
Your strongest days are Monday–Thursday.
```

Or:

```text
You miss Running most frequently on Sundays.
```

But these insights must NOT appear prematurely.

---

# 35. INSIGHTS DATA THRESHOLD

Do NOT make behavioral claims from insufficient data.

For momentum-pattern insights require at least:

```text
3 completed streak cycles
```

OR approximately:

```text
21 days of usable history
```

whichever is appropriate for the specific insight.

Before enough data:

```text
Not enough data yet.

Keep tracking for a little longer.
We'll start identifying patterns once
there's enough history.
```

Never manufacture intelligence.

---

# 36. INSIGHTS SCREEN

Example:

```text
INSIGHTS

Consistency
76%

────────────────

MOMENTUM

Average streak
5.2 days

Longest streak
18 days

Average recovery
1.8 days

────────────────

PATTERNS

You're strongest
Monday–Thursday.

You tend to lose momentum
after 5–6 days.

Sunday consistency
48%

────────────────

COMMITMENT LOAD

7 active commitments

⚠ You have 6+ active daily
commitments.

Consider reducing your load.
```

All initial insights should be **rule-based**.

No LLM is required.

---

# 37. ACTIVE COMMITMENT SOFT CAP

When creating a new commitment:

If active daily commitments >= 6:

show:

```text
You already have 6 active
daily commitments.

Adding another may make
your system harder to maintain.

Continue anyway?
```

Do not block the user.

This is a soft warning.

---

# 38. ADD COMMITMENT

The original 4-step wizard is too slow.

Use a **single-screen creation flow**.

Default:

```text
Add Commitment

What do you want to stay
consistent with?

[ Work on Otto ]

Every day · 1×

[ Create ]

More options
```

The default path should take:

```text
2–3 taps
```

---

# 39. QUICK TEMPLATES

Provide templates:

```text
💻 Code
🏃 Run
🏋️ Gym
📚 Read
🧘 Meditate
💼 Work
🚀 Startup
```

Tapping a template should immediately create a reasonable default commitment or open a minimal confirmation.

---

# 40. MORE OPTIONS

Advanced settings:

```text
Frequency
Target
Duration
Category
Start date
End date
Reminder
Pause schedule
Icon
Description
```

Do not put these in the default flow.

---

# 41. NAVIGATION

Bottom navigation:

```text
Home
History
Insights
Commitments
Settings
```

Home:

Today's actions.

History:

Calendar + past tracking.

Insights:

Long-term analytics.

Commitments:

Manage active/paused/archived commitments.

Settings:

Preferences, backup, notifications, theme, data.

---

# 42. SETTINGS

Include:

### General

Theme:

```text
System
Light
Dark
```

### Day boundary

Default:

```text
4:00 AM
```

Allow customization.

### Week starts on

```text
Monday
Sunday
```

### Notifications

Enable/disable.

### Daily review

Configure time.

### Data

```text
Export data
Import data
Backup
Restore
```

### About

App version.

---

# 43. BACKUP & EXPORT — V1

This is mandatory.

Because the app is local-first, losing the phone must not mean losing years of behavioral history.

Implement:

### Android Auto Backup

Enable database backup where appropriate.

### Manual export

Use Android Storage Access Framework.

Export JSON.

Example:

```text
consistency-os-backup-2026-08-28.json
```

The export must include:

* Commitments
* Schedule versions
* Tracking events
* Notes
* Categories
* Pause periods
* Archived commitments
* Settings required for interpretation

---

# 44. IMPORT

Allow restoring exported JSON.

Validate schema.

Do not blindly overwrite existing data.

Use a safe import strategy.

At minimum:

```text
Validate
Preview
Import
```

Handle duplicate IDs safely.

---

# 45. OFFLINE-FIRST

V1 requires NO backend.

Everything should work offline.

Use:

```text
Room
```

for persistence.

The architecture should make cloud sync possible later.

Do NOT introduce authentication in V1.

---

# 46. DATA MODEL

Design the schema properly rather than blindly copying this structure.

Likely entities:

```text
Commitment
CommitmentSchedule
TrackingEvent
PeriodOccurrence
Rollup
Category
Note
PausePeriod
Reminder
```

Possible Commitment:

```text
id
name
description
icon
categoryId
status
createdAt
updatedAt
```

Schedule:

```text
id
commitmentId
effectiveFrom
effectiveTo
frequencyType
periodType
targetCount
targetDuration
daysOfWeek
createdAt
```

TrackingEvent:

```text
id
commitmentId
accountingDate
timestamp
status
count
duration
note
createdAt
updatedAt
```

Do not duplicate derived data unnecessarily.

---

# 47. MATERIALIZED ROLLUPS

Do not calculate every yearly screen directly from raw events every time.

Maintain a materialized:

```text
per-commitment-per-day rollup
```

or appropriate period rollup.

Example:

```text
CommitmentDailyRollup

commitmentId
date
expected
completed
partial
missed
skipped
weightedScore
```

This is derived data.

The schedule remains the source of truth.

When data changes:

```text
tracking event added
        ↓
recalculate affected rollup
        ↓
recalculate affected period
        ↓
analytics become cheap
```

For weekly/monthly commitments, maintain appropriate period-level rollups.

---

# 48. IMPORTANT: DERIVED DATA

Never treat rollups as the canonical source of truth.

Canonical:

```text
Commitment
Schedule
TrackingEvent
Pause
```

Derived:

```text
DailyRollup
WeeklyRollup
MonthlyRollup
Analytics
```

This makes rebuilding/reindexing possible.

Create a mechanism to rebuild derived data from canonical records.

---

# 49. ANALYTICS FORMULA

Default:

```text
weighted completion
/
eligible expected occurrences
```

Where:

```text
Done = 1.0

Partial = 0.5

Missed = 0

Skipped = excluded

Paused = excluded

Future = excluded

Not scheduled = excluded

Pending = excluded
```

Example:

```text
Expected = 20
Done = 15
Partial = 2
Skipped = 2
Missed = 3
```

Weighted completion:

```text
15 + (2 × 0.5)
= 16
```

Eligible denominator:

```text
20 - 2 skipped
= 18
```

Consistency:

```text
16 / 18
= 88.9%
```

Display appropriately rounded.

---

# 50. PERIOD ACCOUNTING

For a weekly target:

```text
4× / week
```

the denominator is:

```text
4
```

not:

```text
7
```

For a monthly target:

```text
10× / month
```

the denominator is:

```text
10
```

not:

```text
number of days
```

However, an open period should not be treated as failed merely because the user hasn't yet reached its target.

The period result becomes final only when the period closes.

---

# 51. SCHEDULE CHANGES

If the user changes:

```text
Every day
```

to:

```text
3× / week
```

on October 1:

Create a new schedule version.

Never mutate the old schedule in a way that changes historical calculations.

---

# 52. TIMEZONE

Timezone must be part of the accounting configuration.

The system must correctly handle:

* Local timezone
* Day boundary
* DST where applicable
* Month boundaries
* Year boundaries
* Leap years

Do not scatter timezone calculations across UI code.

Create a dedicated time/accounting service.

---

# 53. CLOCK ABSTRACTION

Inject:

```text
Clock
```

into all time-dependent services.

Business logic must never directly call:

```text
LocalDate.now()
Instant.now()
System.currentTimeMillis()
```

Use the injected clock.

This allows deterministic testing.

Example:

```text
FixedClock("2026-08-27T23:30")
```

Then:

```text
FixedClock("2026-08-28T01:30")
```

should still resolve to the same accounting date when the boundary is 04:00.

---

# 54. ARCHITECTURE

Use modern Android architecture.

Preferred:

```text
Kotlin
Jetpack Compose
Room
Coroutines
StateFlow
Navigation Compose
Jetpack Glance
```

Use clean separation between:

```text
UI
Application
Domain
Data
```

The recurrence and analytics engines should be:

**pure Kotlin**

with:

* No Android dependencies
* No UI dependencies
* Injected Clock
* Deterministic inputs/outputs

---

# 55. DOMAIN MODULES

At minimum create:

```text
domain/
    recurrence/
    tracking/
    accounting/
    analytics/
    time/
```

### recurrence

Determines expected occurrences.

### tracking

Processes actual user actions.

### accounting

Determines statuses and period closure.

### analytics

Calculates consistency, streaks, recovery and trends.

### time

Handles Clock, timezone and accounting day.

---

# 56. RECURRENCE ENGINE

Given:

```text
Commitment
Schedule
Date
```

return:

```text
EXPECTED
NOT_EXPECTED
PAUSED
```

For period targets:

return the applicable period:

```text
Week
Month
```

Do not create fake daily misses for period targets.

---

# 57. ACCOUNTING ENGINE

Given:

```text
Schedule
Expected occurrence
Tracking events
Current time
Day boundary
Period state
```

determine:

```text
PENDING
DONE
PARTIAL
MISSED
SKIPPED
PAUSED
NOT_SCHEDULED
```

The engine should be pure and testable.

---

# 58. ANALYTICS ENGINE

Calculate:

* Consistency
* Current streak
* Longest streak
* Average streak
* Recovery time
* Completed count
* Partial count
* Missed count
* Skipped count
* Expected count
* Rolling 7-day consistency
* Weekly performance
* Monthly performance
* Yearly performance

Keep formulas centralized.

Do not duplicate analytics calculations inside screens.

---

# 59. SYNTHETIC DATA SEEDER

Implement a development-only synthetic data generator.

This is mandatory.

I should be able to generate:

```text
12 months
20 commitments
realistic completion patterns
misses
partials
skips
pauses
schedule changes
streaks
recovery cycles
```

Example command:

```text
Seed 365 days
```

This lets developers inspect yearly analytics immediately.

Do NOT wait months for real data.

---

# 60. TESTING

Write comprehensive unit tests.

At minimum test:

### Time

* Accounting day boundary
* Midnight
* 4 AM boundary
* Timezone
* Month transition
* Year transition
* Leap year

### Daily commitments

* Future occurrence
* Pending today
* Missed after boundary
* Done
* Partial
* Skip

### Weekly commitments

* 4× per week
* Partial completion
* Open week
* Closed week
* Future days

### Monthly commitments

* Monthly target
* Partial month
* Month closure

### Schedule changes

```text
Daily → Weekly
```

Ensure historical numbers remain unchanged.

### Pause

Ensure paused dates don't count.

### Archive

Ensure history remains.

### Backfill

Ensure analytics recalculate.

### Undo

Ensure previous state is restored.

---

# 61. UI ACCESSIBILITY

Do not rely only on color.

Status should have multiple visual representations.

For example:

```text
✓ Done
◐ Partial
× Missed
— Skipped
○ Pending
```

Use semantic labels for accessibility.

Large touch targets.

Readable typography.

Good contrast.

---

# 62. EMPTY STATES

No commitments:

```text
Nothing to track yet.

Start small.
Stay consistent.

[ Add your first commitment ]
```

No analytics data:

```text
Not enough data yet.

Keep tracking.

We'll start showing patterns
once there's enough history.
```

No history:

```text
Your history will appear here
as you track commitments.
```

---

# 63. DAILY REVIEW

Optional end-of-day review.

Example:

```text
DAILY REVIEW

Today's progress

4 / 5

💻 Otto       ✓
💼 Finmonk    ✓
🏃 Running    ✓
📚 Learning   ×
📖 Reading    ✓

How was your day?

😀 Good
😐 Average
😞 Bad

Optional note:
[                  ]

[ Done ]
```

Keep this under 10 seconds unless the user chooses to write.

---

# 64. WEEKLY REVIEW

Example:

```text
YOUR WEEK

Consistency
78%

Completed
27

Partial
3

Missed
4

Skipped
2

Best:
Otto — 100%

Needs attention:
Running — 50%

Average recovery:
1.8 days
```

Behavioral insights only appear if enough data exists.

---

# 65. PRODUCT PRINCIPLES

Always optimize for:

### Low friction

Fewest taps.

### Truth over gamification

Accurate accounting matters more than streaks.

### Recovery over perfection

Missing doesn't mean failure.

### No guilt

The application should describe behavior, not judge the user.

### Historical integrity

Past numbers must never silently change because the user edited a future schedule.

### Offline first

Tracking must work without internet.

### Data ownership

The user can export their history.

---

# 66. V1 FEATURES

V1 MUST include:

1. Create commitment
2. Quick templates
3. Daily commitments
4. Weekly targets
5. Monthly targets
6. Count-based tracking
7. Basic duration tracking
8. Effective-dated schedules
9. One-tap Done
10. Partial
11. Skip
12. Missed
13. Undo
14. Long press actions
15. Optional notes
16. Backfill
17. Edit past days
18. Pause
19. Archive
20. Home dashboard
21. Calendar history
22. Weekly view
23. Monthly analytics
24. Yearly analytics
25. Consistency score
26. Streaks
27. Recovery time
28. Rolling 7-day trend
29. Basic rule-based insights
30. Insight data thresholds
31. Active commitment warning
32. Jetpack Glance widget
33. Room persistence
34. Offline-first
35. JSON export
36. JSON import
37. Android Auto Backup
38. Dark/light/system theme
39. Configurable accounting day
40. Unit tests
41. Synthetic data seeder

---

# 67. EXPLICITLY DO NOT BUILD IN V1

Do NOT build:

* Authentication
* Backend
* Cloud sync
* Social features
* Friends
* Leaderboards
* AI coach
* Chat
* Subscription
* Payments
* Complex gamification
* Public profiles
* Community
* LLM integration
* Advanced timers
* Complex project management
* Task dependencies

The foundation must be designed so these can be added later, but they are NOT V1.

---

# 68. FUTURE AI LAYER

Later, an AI system can analyze the structured history.

Potential future insights:

```text
You usually lose momentum after 5–6 days.

You have maintained Otto for 18 of the
last 21 days.

Your consistency improved from 61%
to 78% over the last 3 months.

You tend to miss commitments when you
have more than 6 active daily commitments.

You recover faster than you did three
months ago.
```

But the underlying analytics must already be available without AI.

AI should explain data.

It should NOT become the source of truth.

---

# 69. IMPLEMENTATION STRATEGY

Do NOT attempt the entire application in one giant implementation.

Work incrementally.

## PHASE 1 — FOUNDATION

Implement:

* Android project
* Kotlin
* Compose
* Room
* Architecture
* Navigation
* Theme
* Clock abstraction
* Timezone abstraction

Ensure build succeeds.

---

## PHASE 2 — DOMAIN ENGINE

Implement:

* Commitment
* Schedule
* TrackingEvent
* Recurrence engine
* Accounting engine
* Analytics engine

Before building beautiful screens, make these deterministic and tested.

Also implement:

```text
Synthetic data seeder
```

---

## PHASE 3 — CORE TRACKING

Build:

* Home screen
* Add commitment
* One-tap Done
* Partial
* Skip
* Undo
* Long press
* Notes
* Backfill
* Edit history

---

## PHASE 4 — PERIOD TARGETS

Build:

* Weekly targets
* Monthly targets
* Period progress
* Period closure
* Correct accounting

---

## PHASE 5 — HISTORY

Build:

* Calendar
* Daily detail
* Weekly view
* Monthly view
* Commitment detail

---

## PHASE 6 — ANALYTICS

Build:

* Consistency
* Streaks
* Recovery
* Rolling 7-day trend
* Monthly
* Yearly
* Commitment analytics

---

## PHASE 7 — INSIGHTS

Build:

* Pattern detection
* Data thresholds
* Commitment load warning
* Momentum insights

Rule-based only.

---

## PHASE 8 — WIDGET

Build Jetpack Glance widget.

Optimize the entire product for the:

```text
<10 second daily interaction
```

---

## PHASE 9 — DATA SAFETY

Implement:

* JSON export
* JSON import
* Auto Backup
* Restore validation

---

## PHASE 10 — POLISH

Test:

* Empty states
* Loading
* Error handling
* Accessibility
* Dark mode
* Small/large screens
* Rotation/configuration changes
* Performance
* Database migration
* Widget behavior

---

# 70. DEFINITION OF DONE

The app is NOT considered complete merely because it compiles.

Before declaring V1 complete:

### Functional

* I can create a commitment in seconds.
* I can track it with one tap.
* I can undo accidental actions.
* I can track weekly/monthly targets correctly.
* I can skip without damaging consistency.
* I can pause without damaging consistency.
* I can backfill yesterday.
* I can edit historical records.
* I can change schedules without corrupting historical analytics.
* I can archive commitments.
* I can export all data.
* I can restore data.

### Accounting

Verify:

* Future dates aren't counted.
* Today's pending items aren't missed.
* Closed periods are accounted correctly.
* Weekly targets aren't treated as daily commitments.
* Skips are excluded.
* Pauses are excluded.
* Schedule versions preserve history.
* Accounting day works across midnight.
* Timezone works correctly.

### Analytics

Verify:

* Daily consistency
* Weekly consistency
* Monthly consistency
* Yearly consistency
* Rolling 7-day trend
* Streaks
* Recovery
* Period targets

all produce deterministic results.

### Performance

The yearly analytics screen should NOT scan all raw events on every render.

Use materialized rollups.

---

# 71. IMPORTANT DEVELOPMENT INSTRUCTION FOR CLAUDE CODE

You are acting as:

* Senior Android engineer
* Product engineer
* UX engineer
* Data/analytics engineer

Do not blindly implement the specification.

Before coding:

1. Inspect the existing repository.
2. Understand the current architecture.
3. Identify what already exists.
4. Create an implementation plan.
5. Identify potential contradictions or edge cases.
6. Resolve them in favor of the accounting rules in this specification.
7. Implement incrementally.
8. Keep the project buildable after every phase.

When uncertain, prioritize:

```text
Data correctness
>
Historical integrity
>
Low-friction UX
>
Visual polish
>
Extra features
```

---

# 72. FINAL PRODUCT TEST

After implementation, imagine the following user:

They create:

```text
Work on Otto
Every day
1×
```

Then:

```text
Aug 1 ✓
Aug 2 ✓
Aug 3 ✓
Aug 4 ✓
Aug 5 ✓
Aug 6 ✗
Aug 7 ✗
Aug 8 ✗
Aug 9 ✓
```

The app should correctly understand:

```text
Streak:
5 days

Recovery:
3 missed days
then returned

Current streak:
1 day
```

Now another commitment:

```text
Gym
4× / week
```

User completes:

```text
Mon ✓
Tue ✓
Thu ✓
Sat ✓
```

Result:

```text
4 / 4
100%
```

There must never have been a "missed Wednesday."

Now:

```text
Otto
Every day
```

User changes it on Oct 1 to:

```text
3× / week
```

August and September analytics must remain exactly as they were.

Now:

```text
Aug 27 23:45
```

and:

```text
Aug 28 01:30
```

with a 4 AM boundary.

Both belong to:

```text
Aug 27 accounting day
```

Now the user skips a day:

```text
SKIP
```

That day is excluded from the denominator.

Now they pause for vacation:

```text
PAUSE
```

Those days are excluded entirely.

This is the standard the implementation must satisfy.

---

# 73. THE CORE LOOP

The entire product should ultimately reduce to:

```text
I decide what matters
        ↓
I define a commitment
        ↓
I live my day
        ↓
I tap what actually happened
        ↓
The app records it
        ↓
The system calculates the truth
        ↓
I see my patterns
        ↓
I adjust
        ↓
I continue
```

The product is NOT about maintaining a perfect streak.

It is about making behavior visible over time.

The ultimate metric is:

> **How consistently do my actions match the things I say matter to me?**

Build V1 around that principle.
