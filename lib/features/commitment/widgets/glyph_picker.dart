import 'package:flutter/material.dart';
import 'package:riyaz/app/glyphs.dart';
import 'package:riyaz/app/theme/riyaz_theme.dart';
import 'package:riyaz/app/theme/tokens.dart';

/// Choose the mark that sits at the left edge of a commitment row.
///
/// A grid of the whole vocabulary rather than a text field. The field it
/// replaces accepted any string at all, which is how a tracker ends up with
/// one row wearing a hand-typed emoji nobody else's font renders the same way
/// — and, since the value is serialised into the backup, how it ends up there
/// permanently.
///
/// Scrolls rather than paginating: twenty-eight marks is small enough that
/// hunting through pages costs more than a short scroll, and the add screen's
/// promise is two or three taps.
class GlyphPicker extends StatelessWidget {
  const GlyphPicker({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  /// The stored icon value, which may be a key or a legacy emoji.
  final String? selected;

  /// Called with the chosen key, or null when the current one is tapped again
  /// — picking no mark at all is a legitimate answer, and the row reserves its
  /// space either way so the list still lines up.
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = selected;

    return Wrap(
      spacing: Insets.titleGap * 3,
      runSpacing: Insets.titleGap * 3,
      children: [
        for (final (key, glyph, label) in glyphVocabulary)
          _Swatch(
            glyph: glyph,
            label: label,
            chosen: glyphFor(current) == glyph,
            onTap: () => onSelected(glyphFor(current) == glyph ? null : key),
            theme: theme,
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.glyph,
    required this.label,
    required this.chosen,
    required this.onTap,
    required this.theme,
  });

  final IconData glyph;
  final String label;
  final bool chosen;
  final VoidCallback onTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: chosen,
        label: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.row),
          child: Container(
            width: Sizes.minTapTarget,
            height: Sizes.minTapTarget,
            decoration: BoxDecoration(
              // Selection is a filled ground *and* a heavier glyph, never a
              // tint alone — the same rule the status marks follow.
              color: chosen
                  ? context.statusColors.done.withValues(alpha: 0.18)
                  : null,
              borderRadius: BorderRadius.circular(Radii.row),
              border: Border.all(
                color: chosen
                    ? context.statusColors.done
                    : theme.colorScheme.outlineVariant,
                width: chosen ? 1.5 : 1,
              ),
            ),
            child: Icon(
              glyph,
              size: 22,
              color: chosen
                  ? context.statusColors.done
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
}
