import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/domain/accounting/occurrence_status.dart';
import 'package:riyaz/domain/accounting/resolved_occurrence.dart';
import 'package:riyaz/domain/analytics/scoring.dart';
import 'package:riyaz/domain/model/commitment.dart';
import 'package:riyaz/domain/recurrence/expected_occurrence.dart';
import 'package:riyaz/domain/time/accounting_calendar.dart';
import 'package:riyaz/domain/time/civil_date.dart';
import 'package:riyaz/features/home/today_view.dart';
import 'package:riyaz/features/widget/widget_payload.dart';

import '../../support/dates.dart';

TodayItem item({
  required String name,
  required OccurrenceStatus status,
  int completed = 0,
  int target = 1,
  bool period = false,
  String? icon,
}) {
  final occurrence = period
      ? PeriodOccurrence(
          commitmentId: name,
          scope: PeriodScope.weekly,
          period: CivilDateRange(d(2026, 8, 24), d(2026, 8, 30)),
          target: target,
        )
      : DailyOccurrence(
          commitmentId: name,
          date: d(2026, 8, 28),
          target: target,
        ) as ExpectedOccurrence;

  return TodayItem(
    commitment: Commitment(
      id: name,
      name: name,
      startedOn: d(2026, 8, 1),
      icon: icon,
    ),
    resolved: resolutionOf(
      occurrence: occurrence,
      status: status,
      completed: completed,
      weights: ScoringWeights.standard,
    ),
  );
}

void main() {
  group('glyphs', () {
    test('every status has a distinct glyph, and none rely on colour', () {
      final glyphs = {
        for (final s in OccurrenceStatus.values) s: WidgetPayload.glyphFor(s),
      };
      expect(glyphs.values.toSet(), hasLength(OccurrenceStatus.values.length),
          reason: 'two states sharing a glyph would be indistinguishable');
      expect(glyphs[OccurrenceStatus.done], '✓');
      expect(glyphs[OccurrenceStatus.pending], '○');
      expect(glyphs[OccurrenceStatus.missed], '✗');
      expect(glyphs[OccurrenceStatus.skipped], '—');
    });
  });

  group('payload', () {
    test('renders every string in Dart, so native does no arithmetic', () {
      final view = TodayView(
        date: d(2026, 8, 28),
        items: [
          item(name: 'Running', status: OccurrenceStatus.done, completed: 1),
          item(
            name: 'Gym',
            status: OccurrenceStatus.pending,
            completed: 2,
            target: 4,
            period: true,
          ),
        ],
      );
      final payload = WidgetPayload.fromView(view, 'Friday, Aug 28');

      expect(payload.dateLabel, 'Friday, Aug 28');
      expect(payload.progressLabel, '1/2');
      expect(payload.rows, hasLength(2));

      expect(payload.rows[0].glyph, '✓');
      expect(payload.rows[0].detail, '', reason: 'a simple row has no counter');

      // A period row carries its progress, not a bare tick.
      expect(payload.rows[1].detail, '2/4');
    });

    test('an empty day shows a dash, never zero percent', () {
      final payload = WidgetPayload.fromView(
        const TodayView(date: CivilDate(2026, 8, 28), items: []),
        'Friday, Aug 28',
      );
      expect(payload.progressLabel, '—');
      expect(payload.isEmpty, isTrue);
      expect(payload.rows, isEmpty);
    });

    test('skipped rows leave the progress denominator', () {
      final view = TodayView(
        date: d(2026, 8, 28),
        items: [
          item(name: 'Running', status: OccurrenceStatus.done, completed: 1),
          item(name: 'Reading', status: OccurrenceStatus.skipped),
        ],
      );
      // Same rule as the app: a skip is not a failure, so it is not counted.
      expect(WidgetPayload.fromView(view, 'x').progressLabel, '1/1');
    });

    test('icons are carried through, absent ones as empty strings', () {
      final view = TodayView(
        date: d(2026, 8, 28),
        items: [
          item(name: 'Running', status: OccurrenceStatus.pending, icon: '🏃'),
          item(name: 'Plain', status: OccurrenceStatus.pending),
        ],
      );
      final payload = WidgetPayload.fromView(view, 'x');
      expect(payload.rows[0].icon, '🏃');
      expect(payload.rows[1].icon, '');
    });
  });

  group('encoding', () {
    test('produces JSON the native side can parse', () {
      final view = TodayView(
        date: d(2026, 8, 28),
        items: [
          item(name: 'Running', status: OccurrenceStatus.done, completed: 1),
        ],
      );
      final json =
          jsonDecode(WidgetPayload.fromView(view, 'Friday, Aug 28').encode())
              as Map<String, dynamic>;

      // These keys are the contract with RiyazWidgetProvider.kt. Changing one
      // without changing the Kotlin leaves a silently blank widget.
      expect(json.keys.toSet(),
          {'dateLabel', 'progressLabel', 'isEmpty', 'rows'});
      final row = (json['rows'] as List).single as Map<String, dynamic>;
      expect(row.keys.toSet(), {'id', 'label', 'glyph', 'detail', 'icon'});
      expect(row['label'], 'Running');
      expect(row['glyph'], '✓');
    });

    test('survives unicode in names and notes', () {
      final view = TodayView(
        date: d(2026, 8, 28),
        items: [
          item(name: 'Café — 5km', status: OccurrenceStatus.done, completed: 1,
              icon: '🏋️'),
        ],
      );
      final encoded = WidgetPayload.fromView(view, 'x').encode();
      final row = ((jsonDecode(encoded) as Map)['rows'] as List).single as Map;
      expect(row['label'], 'Café — 5km');
      expect(row['icon'], '🏋️');
    });
  });
}
