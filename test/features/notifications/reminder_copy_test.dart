import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/domain/accounting/occurrence_status.dart';
import 'package:riyaz/domain/accounting/resolved_occurrence.dart';
import 'package:riyaz/domain/model/commitment.dart';
import 'package:riyaz/domain/recurrence/expected_occurrence.dart';
import 'package:riyaz/domain/time/accounting_calendar.dart';
import 'package:riyaz/domain/time/civil_date.dart';
import 'package:riyaz/features/home/today_view.dart';
import 'package:riyaz/features/notifications/reminder_copy.dart';

void main() {
  const today = CivilDate(2026, 9, 1);

  Commitment commitment(String name) => Commitment(
        id: name.toLowerCase(),
        name: name,
        startedOn: const CivilDate(2026, 1, 1),
      );

  TodayItem dailyItem(
    String name, {
    OccurrenceStatus status = OccurrenceStatus.pending,
    int completed = 0,
    int target = 1,
  }) =>
      TodayItem(
        commitment: commitment(name),
        resolved: ResolvedOccurrence(
          occurrence: DailyOccurrence(
            commitmentId: name.toLowerCase(),
            date: today,
            target: target,
          ),
          status: status,
          completed: completed,
          credit: 0,
        ),
      );

  TodayItem weeklyItem(
    String name, {
    OccurrenceStatus status = OccurrenceStatus.pending,
    int completed = 2,
    int target = 4,
  }) =>
      TodayItem(
        commitment: commitment(name),
        resolved: ResolvedOccurrence(
          occurrence: PeriodOccurrence(
            commitmentId: name.toLowerCase(),
            scope: PeriodScope.weekly,
            period: const CivilDateRange(
              CivilDate(2026, 8, 31),
              CivilDate(2026, 9, 6),
            ),
            target: target,
          ),
          status: status,
          completed: completed,
          credit: 0,
        ),
      );

  TodayView viewOf(List<TodayItem> items) =>
      TodayView(date: today, items: items);

  group('it never speaks with nothing to say', () {
    test('an empty day produces no notification', () {
      expect(ReminderCopy.daily(viewOf(const [])), isNull);
    });

    test('a day already finished produces no notification', () {
      final text = ReminderCopy.daily(viewOf([
        dailyItem('Meditate', status: OccurrenceStatus.done),
        dailyItem('Read', status: OccurrenceStatus.done),
      ]));
      expect(text, isNull,
          reason: 'being reminded to do what you have already done is the '
              'worst failure this feature has');
    });

    test('an entirely skipped day produces no notification', () {
      expect(
        ReminderCopy.daily(viewOf([
          dailyItem('Meditate', status: OccurrenceStatus.skipped),
        ])),
        isNull,
      );
    });

    test('an entirely paused day produces no notification', () {
      expect(
        ReminderCopy.daily(viewOf([
          dailyItem('Meditate', status: OccurrenceStatus.paused),
        ])),
        isNull,
      );
    });

    test('a partially finished day still reminds about the rest', () {
      final text = ReminderCopy.daily(viewOf([
        dailyItem('Meditate', status: OccurrenceStatus.done),
        dailyItem('Read'),
      ]));
      expect(text, isNotNull);
      expect(text!.body, 'Read');
      expect(text.body, isNot(contains('Meditate')),
          reason: 'a finished commitment is not something to be reminded of');
    });
  });

  group('the daily reminder', () {
    test('three or fewer are listed without a count', () {
      final text = ReminderCopy.daily(viewOf([
        dailyItem('Meditate'),
        dailyItem('Read'),
        dailyItem('Gym'),
      ]))!;

      expect(text.title, 'Today');
      expect(text.body, 'Meditate, Read, Gym');
    });

    test('more than three carry the count in the title', () {
      final text = ReminderCopy.daily(viewOf([
        dailyItem('Meditate'),
        dailyItem('Read'),
        dailyItem('Gym'),
        dailyItem('Journal'),
        dailyItem('Stretch'),
      ]))!;

      expect(text.title, 'Today · 5 commitments');
      expect(text.lines, hasLength(5));
    });

    test('the count always matches the names beside it', () {
      // A bare count can outlive its truth. Derived from the same list, the two
      // go stale together or not at all.
      final items = [
        dailyItem('Meditate'),
        dailyItem('Read'),
        dailyItem('Gym', status: OccurrenceStatus.done),
        dailyItem('Journal'),
        dailyItem('Stretch'),
      ];
      final text = ReminderCopy.daily(viewOf(items))!;

      expect(text.title, 'Today · 4 commitments');
      expect(text.lines, hasLength(4));
      expect(text.body.split(', '), hasLength(4));
    });

    test('a period commitment carries its progress in the expanded form', () {
      final text = ReminderCopy.daily(viewOf([
        dailyItem('Meditate'),
        weeklyItem('Gym', completed: 2, target: 4),
      ]))!;

      expect(text.lines.last, contains('2/4 this week'));
      expect(text.lines.last, startsWith('Gym'));
    });

    test('the collapsed line stays plain names, even with a period row', () {
      // One line in a notification shade. Progress belongs in the expanded form
      // where there is room for it.
      final text = ReminderCopy.daily(viewOf([
        dailyItem('Meditate'),
        weeklyItem('Gym'),
      ]))!;

      expect(text.body, 'Meditate, Gym');
    });

    test('a monthly commitment says month, not week', () {
      final item = TodayItem(
        commitment: commitment('Deep clean'),
        resolved: ResolvedOccurrence(
          occurrence: PeriodOccurrence(
            commitmentId: 'deep clean',
            scope: PeriodScope.monthly,
            period: const CivilDateRange(
              CivilDate(2026, 9, 1),
              CivilDate(2026, 9, 30),
            ),
            target: 2,
          ),
          status: OccurrenceStatus.pending,
          completed: 1,
          credit: 0,
        ),
      );

      final text = ReminderCopy.daily(viewOf([item]))!;
      expect(text.lines.single, contains('1/2 this month'));
    });

    test('it never evaluates, only reports', () {
      final text = ReminderCopy.daily(viewOf([dailyItem('Meditate')]))!;
      final all = '${text.title} ${text.body} ${text.lines.join(' ')}';

      for (final scold in ['streak', "don't", 'fail', 'behind', 'missed']) {
        expect(all.toLowerCase(), isNot(contains(scold)),
            reason: 'a tracker that scolds gets uninstalled, and the history '
                'is the asset');
      }
    });
  });
}
