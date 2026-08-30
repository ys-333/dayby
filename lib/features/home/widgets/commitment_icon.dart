import 'package:flutter/material.dart';
import 'package:riyaz/app/theme/tokens.dart';

/// The mark at the left edge of a commitment row.
///
/// One widget rather than an inline `Text` in each tile, because
/// `Commitment.icon` is about to stop being an emoji. The stored value is a
/// `String` that is written by the add screen and serialised into the backup
/// format, so replacing the vocabulary is a data migration — and it should be
/// a change to one file, not to every row that happens to draw one.
///
/// The slot is reserved whether or not there is an icon. A list where some
/// rows are indented and others are not reads as a layout bug, and the
/// commitment without an icon is exactly the one that then looks broken.
class CommitmentIcon extends StatelessWidget {
  const CommitmentIcon({required this.icon, this.dimmed = false, super.key});

  /// The stored icon value, today an emoji.
  final String? icon;

  /// Finished rows recede: the mark dims with the name it belongs to.
  final bool dimmed;

  /// Width of the mark itself, before the gap to the text.
  static const double glyphSize = 22;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: Insets.rowGap),
        child: SizedBox(
          width: glyphSize,
          child: icon == null
              ? null
              : Opacity(
                  opacity: dimmed ? 0.55 : 1,
                  child: Text(
                    icon!,
                    style: const TextStyle(fontSize: glyphSize),
                    textAlign: TextAlign.center,
                  ),
                ),
        ),
      );
}
