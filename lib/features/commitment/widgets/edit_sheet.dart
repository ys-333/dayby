import 'package:flutter/material.dart';
import 'package:riyaz/app/theme/tokens.dart';
import 'package:riyaz/domain/model/commitment.dart';
import 'package:riyaz/domain/model/frequency.dart';

import 'frequency_picker.dart';

/// What an edit changed. Null fields were not touched.
class CommitmentEdit {
  const CommitmentEdit({this.name, this.icon, this.frequency});

  final String? name;
  final String? icon;
  final Frequency? frequency;

  bool get isEmpty => name == null && icon == null && frequency == null;
}

/// Edits a commitment in a sheet rather than a screen.
///
/// A sheet because editing is a correction, not a task: the detail behind it
/// stays visible, and dismissing costs one tap rather than a back-navigation.
class EditSheet extends StatefulWidget {
  const EditSheet({
    required this.commitment,
    required this.frequency,
    super.key,
  });

  final Commitment commitment;
  final Frequency frequency;

  @override
  State<EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<EditSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.commitment.name);
  late final TextEditingController _icon =
      TextEditingController(text: widget.commitment.icon ?? '');
  late Frequency _frequency = widget.frequency;

  @override
  void dispose() {
    _name.dispose();
    _icon.dispose();
    super.dispose();
  }

  bool get _frequencyChanged => _frequency != widget.frequency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: Insets.rowH,
        right: Insets.rowH,
        top: Insets.rowH,
        bottom: MediaQuery.viewInsetsOf(context).bottom + Insets.rowH,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Edit', style: theme.textTheme.titleLarge),
          const SizedBox(height: Insets.rowH),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 64,
                child: TextField(
                  controller: _icon,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    labelText: 'Icon',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: Insets.rowTrailingGap),
              Expanded(
                child: TextField(
                  controller: _name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: Insets.rowH),
          Text('Frequency', style: theme.textTheme.titleMedium),
          const SizedBox(height: Insets.titleGap),
          Text(
            frequencyLabel(_frequency),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: Insets.rowTrailingGap),
          FrequencyPicker(
            value: _frequency,
            onChanged: (f) => setState(() => _frequency = f),
          ),
          if (_frequencyChanged) ...[
            const SizedBox(height: Insets.rowTrailingGap),
            // Said plainly, because the alternative is a user assuming their
            // past consistency just moved — or worse, expecting it to.
            Text(
              'Takes effect today. Every day before today keeps the '
              'frequency it was tracked under, so your history does not '
              'change.',
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: Insets.xl),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _name.text.trim().isEmpty ? null : _save,
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _save() {
    final name = _name.text.trim();
    final icon = _icon.text.trim();
    Navigator.of(context).pop(
      CommitmentEdit(
        name: name == widget.commitment.name ? null : name,
        icon: icon == (widget.commitment.icon ?? '')
            ? null
            : (icon.isEmpty ? null : icon),
        frequency: _frequencyChanged ? _frequency : null,
      ),
    );
  }
}
