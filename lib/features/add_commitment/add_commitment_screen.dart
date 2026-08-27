import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riyaz/app/providers.dart';
import 'package:riyaz/domain/model/commitment.dart';
import 'package:riyaz/domain/model/frequency.dart';
import 'package:riyaz/domain/time/civil_date.dart';

/// Quick-start templates. Tapping one fills the form so the common case is
/// name-free: pick, create, done.
class _Template {
  const _Template(this.icon, this.name, this.frequency);

  final String icon;
  final String name;
  final Frequency frequency;
}

const List<_Template> _templates = [
  _Template('💻', 'Code', Frequency.daily()),
  _Template('🏃', 'Run', Frequency.daily()),
  _Template('🏋️', 'Gym', Frequency.timesPerWeek(target: 4)),
  _Template('📚', 'Read', Frequency.daily()),
  _Template('🧘', 'Meditate', Frequency.daily()),
  _Template('💼', 'Work', Frequency.daily()),
  _Template('🚀', 'Startup', Frequency.daily()),
];

/// Single-screen creation.
///
/// The spec's original four-step wizard was replaced deliberately: a tracker
/// whose promise is ten seconds a day cannot ask for four screens to add a row.
/// Everything past a name and a frequency hides behind "More options".
class AddCommitmentScreen extends ConsumerStatefulWidget {
  const AddCommitmentScreen({super.key});

  @override
  ConsumerState<AddCommitmentScreen> createState() =>
      _AddCommitmentScreenState();
}

class _AddCommitmentScreenState extends ConsumerState<AddCommitmentScreen> {
  final _name = TextEditingController();
  String? _icon;
  Frequency _frequency = const Frequency.daily();
  bool _advanced = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String get _frequencyLabel => switch (_frequency) {
        DailyFrequency(:final target) =>
          target > 1 ? 'Every day · ${target}x' : 'Every day',
        WeekdaysFrequency(:final days) => '${days.length} days a week',
        EveryNDaysFrequency(:final n) => 'Every $n days',
        TimesPerWeekFrequency(:final target) => '${target}x per week',
        TimesPerMonthFrequency(:final target) => '${target}x per month',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Add commitment')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text(
            'What do you want to stay consistent with?',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Work on Otto',
              border: const OutlineInputBorder(),
              prefixIcon: _icon == null
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(left: 12, top: 12),
                      child: Text(
                        _icon!,
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _create(),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in _templates)
                ActionChip(
                  avatar: Text(t.icon),
                  label: Text(t.name),
                  onPressed: () => setState(() {
                    _name.text = t.name;
                    _icon = t.icon;
                    _frequency = t.frequency;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              title: const Text('Frequency'),
              subtitle: Text(_frequencyLabel),
              trailing: Icon(
                _advanced ? Icons.expand_less : Icons.expand_more,
              ),
              onTap: () => setState(() => _advanced = !_advanced),
            ),
          ),
          if (_advanced) ...[
            const SizedBox(height: 12),
            _FrequencyPicker(
              value: _frequency,
              onChanged: (f) => setState(() => _frequency = f),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _name.text.trim().isEmpty || _saving ? null : _create,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;

    if (!await _confirmLoad()) return;
    if (!mounted) return;

    setState(() => _saving = true);
    final repo = ref.read(trackingRepositoryProvider);
    await repo.createCommitment(
      name: name,
      frequency: _frequency,
      startedOn: ref.read(todayProvider),
      nowUtc: ref.read(clockProvider).nowUtc(),
      icon: _icon,
    );
    if (mounted) Navigator.of(context).pop();
  }

  /// Soft cap from the spec: warn past six active daily commitments, but never
  /// block. Over-committing is the failure mode this app exists to make
  /// visible — refusing the input would just hide it.
  Future<bool> _confirmLoad() async {
    if (_frequency.isPeriodScoped) return true;

    final repo = ref.read(trackingRepositoryProvider);
    final today = ref.read(todayProvider);
    final snapshot = await repo.read(CivilDateRange(today, today));
    final activeDaily = snapshot.commitments
        .where((c) => c.state == CommitmentState.active)
        .where((c) => snapshot
            .schedulesFor(c.id)
            .any((s) => !s.frequency.isPeriodScoped))
        .length;

    if (activeDaily < 6 || !mounted) return true;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('That is a lot to hold'),
        content: Text(
          'You already have $activeDaily active daily commitments. '
          'Adding another may make your system harder to keep up.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add anyway'),
          ),
        ],
      ),
    );
    return proceed ?? false;
  }
}

class _FrequencyPicker extends StatelessWidget {
  const _FrequencyPicker({required this.value, required this.onChanged});

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
