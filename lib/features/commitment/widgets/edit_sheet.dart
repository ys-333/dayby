import 'package:flutter/material.dart';
import 'package:riyaz/app/glyphs.dart';
import 'package:riyaz/features/commitment/widgets/glyph_picker.dart';
import 'package:riyaz/app/theme/tokens.dart';
import 'package:riyaz/domain/model/commitment.dart';
import 'package:riyaz/domain/model/frequency.dart';

import 'frequency_picker.dart';

/// What an edit changed. Null fields were not touched.
class CommitmentEdit {
  const CommitmentEdit({
    this.name,
    this.icon,
    this.clearIcon = false,
    this.frequency,
  });

  final String? name;
  final String? icon;
  final Frequency? frequency;

  /// Removes the mark. Distinct from a null [icon], which means "unchanged".
  final bool clearIcon;

  bool get isEmpty =>
      name == null && icon == null && !clearIcon && frequency == null;
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
  late final TextEditingController _name = TextEditingController(
    text: widget.commitment.name,
  );
  late String? _icon = widget.commitment.icon;
  late Frequency _frequency = widget.frequency;

  @override
  void dispose() {
    _name.dispose();
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
      // Scrollable: the sheet is taller than a short screen with the keyboard
      // up, and taller again at a large text scale. It has to give rather than
      // overflow — the same treatment the today screen's action sheet needs.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Edit', style: theme.textTheme.titleLarge),
            const SizedBox(height: Insets.rowH),
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Name',
                border: const OutlineInputBorder(),
                prefixIcon: _icon == null
                    ? null
                    : Icon(glyphFor(_icon), size: 20),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: Insets.rowH),
            // A grid, not the free-text field this replaces. That field took any
            // string at all, which is how a row ends up wearing a hand-typed
            // emoji that renders differently on every device — and, since the
            // value is serialised into the backup, keeps doing so forever.
            //
            // Collapsed by default: most edits are a rename, and twenty-eight
            // swatches open by default would push the frequency controls and the
            // Save button off a short screen.
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Icon'),
              subtitle: Text(
                _icon == null ? 'None' : glyphLabelFor(_icon) ?? '',
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: Insets.rowTrailingGap),
                  child: GlyphPicker(
                    selected: _icon,
                    onSelected: (key) => setState(() => _icon = key),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Insets.rowH),
            Text('Frequency', style: theme.textTheme.titleMedium),
            const SizedBox(height: Insets.titleGap),
            Text(frequencyLabel(_frequency), style: theme.textTheme.bodySmall),
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
      ),
    );
  }

  void _save() {
    final name = _name.text.trim();
    final changed = _icon != widget.commitment.icon;
    Navigator.of(context).pop(
      CommitmentEdit(
        name: name == widget.commitment.name ? null : name,
        icon: changed ? _icon : null,
        clearIcon: changed && _icon == null,
        frequency: _frequencyChanged ? _frequency : null,
      ),
    );
  }
}
