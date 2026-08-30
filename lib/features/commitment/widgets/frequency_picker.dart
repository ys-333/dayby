import 'package:flutter/material.dart';
import 'package:riyaz/domain/model/frequency.dart';

/// One definition of how a frequency is chosen and how it is named.
///
/// Extracted from the add screen when editing needed the same control. Two
/// copies of this would drift — a segment added in one place and not the
/// other, or two spellings of "3x per week" — and the user would meet a
/// different vocabulary depending on which door they came through.
String frequencyLabel(Frequency frequency) => switch (frequency) {
      DailyFrequency(:final target) =>
        target > 1 ? '$target times a day' : 'Every day',
      WeekdaysFrequency(:final days) => '${days.length} days a week',
      EveryNDaysFrequency(:final n) => 'Every $n days',
      TimesPerWeekFrequency(:final target) => '${target}x per week',
      TimesPerMonthFrequency(:final target) => '${target}x per month',
    };

class FrequencyPicker extends StatelessWidget {
  const FrequencyPicker({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final Frequency value;
  final ValueChanged<Frequency> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'daily', label: Text('Daily')),
            ButtonSegment(value: 'week', label: Text('Per week')),
            ButtonSegment(value: 'month', label: Text('Per month')),
          ],
          selected: {
            switch (value) {
              TimesPerWeekFrequency() => 'week',
              TimesPerMonthFrequency() => 'month',
              _ => 'daily',
            }
          },
          onSelectionChanged: (selection) => onChanged(
            switch (selection.first) {
              'week' => const Frequency.timesPerWeek(target: 3),
              'month' => const Frequency.timesPerMonth(target: 4),
              _ => const Frequency.daily(),
            },
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Text('Target'),
            const Spacer(),
            IconButton(
              onPressed: value.target <= 1
                  ? null
                  : () => onChanged(_withTarget(value, value.target - 1)),
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Text('${value.target}'),
            IconButton(
              onPressed: () => onChanged(_withTarget(value, value.target + 1)),
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
      ],
    );
  }

  Frequency _withTarget(Frequency frequency, int target) => switch (frequency) {
        DailyFrequency() => Frequency.daily(target: target),
        WeekdaysFrequency(:final days) =>
          Frequency.weekdays(days: days, target: target),
        EveryNDaysFrequency(:final n) =>
          Frequency.everyNDays(n: n, target: target),
        TimesPerWeekFrequency() => Frequency.timesPerWeek(target: target),
        TimesPerMonthFrequency() => Frequency.timesPerMonth(target: target),
      };
}
