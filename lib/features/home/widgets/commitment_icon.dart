import 'package:flutter/material.dart';
import 'package:riyaz/app/glyphs.dart';
import 'package:riyaz/app/theme/tokens.dart';

/// The mark at the left edge of a commitment row.
///
/// One widget rather than an inline `Text` in each tile, which is what made
/// the emoji-to-glyph swap a one-file change. The stored value is still a
/// `String`; what changed is that it now names a glyph rather than being one.
/// See `lib/domain/model/commitment_icon.dart` for the vocabulary and
/// `lib/app/glyphs.dart` for how a key becomes a picture.
///
/// The slot is reserved whether or not there is an icon. A list where some
/// rows are indented and others are not reads as a layout bug, and the
/// commitment without an icon is exactly the one that then looks broken.
class CommitmentIcon extends StatelessWidget {
  const CommitmentIcon({required this.icon, this.dimmed = false, super.key});

  /// The stored icon value: a glyph key, or a legacy emoji.
  final String? icon;

  /// Finished rows recede: the mark dims with the name it belongs to.
  final bool dimmed;

  /// Width of the mark itself, before the gap to the text.
  static const double glyphSize = 22;

  @override
  Widget build(BuildContext context) {
    final glyph = glyphFor(icon);
    final ink = Theme.of(context).colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(right: Insets.rowGap),
      child: SizedBox(
        width: glyphSize,
        child: switch ((icon, glyph)) {
          (null, _) => null,
          (_, final IconData g) => Opacity(
              opacity: dimmed ? 0.55 : 1,
              child: Icon(g, size: glyphSize, color: ink),
            ),
          // A value this build has no glyph for — an emoji outside the legacy
          // table, or one typed into the old free-text field. Drawn as it was
          // stored rather than dropped or replaced: the mark is the user's,
          // and losing it silently is worse than one row looking different.
          (final String raw, null) => Opacity(
              opacity: dimmed ? 0.55 : 1,
              child: Text(
                raw,
                style: const TextStyle(fontSize: glyphSize),
                textAlign: TextAlign.center,
              ),
            ),
        },
      ),
    );
  }
}
