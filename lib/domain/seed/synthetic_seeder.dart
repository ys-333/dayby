import 'dart:math';

import '../model/commitment.dart';
import '../model/frequency.dart';
import '../model/pause_period.dart';
import '../model/schedule.dart';
import '../model/tracking_event.dart';
import '../time/civil_date.dart';

/// A generated history, ready to load into the database.
class SyntheticDataset {
  const SyntheticDataset({
    required this.commitments,
    required this.schedules,
    required this.pauses,
    required this.events,
  });

  final List<Commitment> commitments;
  final List<CommitmentSchedule> schedules;
  final List<PausePeriod> pauses;
  final List<TrackingEvent> events;

  @override
  String toString() => 'SyntheticDataset(${commitments.length} commitments, '
      '${schedules.length} schedules, ${pauses.length} pauses, '
      '${events.length} events)';
}

class _Template {
  const _Template(this.name, this.icon, this.frequency, this.reliability);

  final String name;
  final String icon;
  final Frequency frequency;

  /// Chance of acting on a day while in a good run. Deliberately varied so the
  /// insights screen has both strong and weak commitments to talk about.
  final double reliability;
}

/// Generates a year of plausible behaviour so analytics screens can be built
/// and judged today instead of after months of real use.
///
/// Deterministic: the same [seed] always produces the same dataset, which makes
/// it safe to assert against in tests and to compare screenshots across runs.
///
/// The generator models *momentum* rather than a coin flip per day. A
/// commitment sits in a run or a lapse; runs decay the longer they last, and
/// lapses end with a rising chance of return. Independent coin flips would
/// produce data with no streaks, no recovery cycles and no patterns — exactly
/// the things the analytics exist to surface.
class SyntheticSeeder {
  const SyntheticSeeder();

  static const List<_Template> _templates = [
    _Template('Work on Otto', 'code', Frequency.daily(), 0.88),
    _Template('Finmonk', 'work', Frequency.daily(), 0.82),
    _Template('Running', 'run', Frequency.daily(), 0.55),
    _Template('Learning', 'study', Frequency.daily(), 0.7),
    _Template('Reading', 'read', Frequency.daily(), 0.62),
    _Template('Meditate', 'yoga', Frequency.daily(), 0.44),
    _Template('Gym', 'gym', Frequency.timesPerWeek(target: 4), 0.6),
    _Template('Swim', 'swim', Frequency.timesPerWeek(target: 2), 0.66),
    _Template('Deep work', 'focus', Frequency.timesPerWeek(target: 5), 0.72),
    _Template('Books', 'book', Frequency.timesPerMonth(target: 2), 0.58),
    _Template('Call family', 'call', Frequency.timesPerWeek(target: 3), 0.75),
    _Template(
      'Weekday standup',
      'note',
      Frequency.weekdays(days: {1, 2, 3, 4, 5}),
      0.9,
    ),
    _Template('Long walk', 'walk', Frequency.everyNDays(n: 3), 0.68),
  ];

  SyntheticDataset generate({
    required CivilDate endingOn,
    int days = 365,
    int commitmentCount = 20,
    int seed = 42,
  }) {
    final rng = Random(seed);
    final start = endingOn.plusDays(-(days - 1));

    final commitments = <Commitment>[];
    final schedules = <CommitmentSchedule>[];
    final pauses = <PausePeriod>[];
    final events = <TrackingEvent>[];

    for (var i = 0; i < commitmentCount; i++) {
      final template = _templates[i % _templates.length];
      final id = 'seed-c$i';
      final suffix = i >= _templates.length ? ' ${i ~/ _templates.length + 1}' : '';

      // Stagger start dates so not every commitment has a full year.
      final startedOn = start.plusDays(rng.nextInt(days ~/ 3));
      final archived = i % 11 == 10;

      commitments.add(Commitment(
        id: id,
        name: '${template.name}$suffix',
        icon: template.icon,
        startedOn: startedOn,
        state: archived ? CommitmentState.archived : CommitmentState.active,
        archivedOn: archived ? endingOn.plusDays(-rng.nextInt(40) - 1) : null,
      ));

      schedules.addAll(_schedulesFor(id, template, startedOn, endingOn, i));
      final pause = _maybePause(id, startedOn, endingOn, rng, i);
      if (pause != null) pauses.add(pause);

      events.addAll(_behaviour(
        commitmentId: id,
        template: template,
        from: startedOn,
        to: commitments.last.archivedOn ?? endingOn,
        pause: pause,
        rng: rng,
      ));
    }

    return SyntheticDataset(
      commitments: commitments,
      schedules: schedules,
      pauses: pauses,
      events: events,
    );
  }

  /// Most commitments keep one schedule; every third gets a mid-history change
  /// so schedule-versioning code meets real versioned data.
  List<CommitmentSchedule> _schedulesFor(
    String commitmentId,
    _Template template,
    CivilDate startedOn,
    CivilDate endingOn,
    int index,
  ) {
    if (index % 3 != 0) {
      return [
        CommitmentSchedule(
          id: '$commitmentId-s0',
          commitmentId: commitmentId,
          effectiveFrom: startedOn,
          frequency: template.frequency,
        ),
      ];
    }

    final changeOn = startedOn
        .plusDays(startedOn.daysUntil(endingOn) ~/ 2)
        .startOfMonth;
    return [
      CommitmentSchedule(
        id: '$commitmentId-s0',
        commitmentId: commitmentId,
        effectiveFrom: startedOn,
        effectiveTo: changeOn.plusDays(-1),
        frequency: template.frequency,
      ),
      CommitmentSchedule(
        id: '$commitmentId-s1',
        commitmentId: commitmentId,
        effectiveFrom: changeOn,
        frequency: const Frequency.timesPerWeek(target: 3),
      ),
    ];
  }

  PausePeriod? _maybePause(
    String commitmentId,
    CivilDate startedOn,
    CivilDate endingOn,
    Random rng,
    int index,
  ) {
    if (index % 4 != 1) return null;
    final span = startedOn.daysUntil(endingOn);
    if (span < 30) return null;
    final from = startedOn.plusDays(rng.nextInt(span - 20) + 10);
    return PausePeriod(
      id: '$commitmentId-pause',
      commitmentId: commitmentId,
      from: from,
      to: from.plusDays(rng.nextInt(9) + 3),
    );
  }

  /// Walks the history day by day, flipping between runs and lapses.
  List<TrackingEvent> _behaviour({
    required String commitmentId,
    required _Template template,
    required CivilDate from,
    required CivilDate to,
    required PausePeriod? pause,
    required Random rng,
  }) {
    final events = <TrackingEvent>[];
    var inRun = true;
    var runLength = 0;
    var lapseLength = 0;
    var n = 0;

    for (var date = from; date <= to; date = date.plusDays(1)) {
      if (pause != null && pause.covers(date)) continue;

      if (inRun) {
        // Runs decay: the longer one lasts, the likelier it ends. This is what
        // produces the "you tend to drop off after 5-6 days" pattern.
        if (rng.nextDouble() < 0.04 + runLength * 0.022) {
          inRun = false;
          runLength = 0;
          lapseLength = 0;
          continue;
        }
        runLength++;
        if (rng.nextDouble() > template.reliability) continue;

        final roll = rng.nextDouble();
        final kind = roll < 0.08
            ? TrackingKind.skipped
            : roll < 0.22
                ? TrackingKind.partial
                : TrackingKind.done;

        events.add(TrackingEvent(
          id: '$commitmentId-e${n++}',
          commitmentId: commitmentId,
          accountingDate: date,
          recordedAtUtc: DateTime.utc(date.year, date.month, date.day, 18),
          kind: kind,
          minutes: kind == TrackingKind.done ? 15 + rng.nextInt(60) : null,
        ));
      } else {
        lapseLength++;
        // Returning gets likelier the longer the lapse runs.
        if (rng.nextDouble() < 0.18 + lapseLength * 0.06) {
          inRun = true;
          runLength = 0;
        }
      }
    }

    return events;
  }
}
