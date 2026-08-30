import 'package:flutter/material.dart';
import 'package:riyaz/app/theme/riyaz_theme.dart';
import 'package:riyaz/app/theme/tokens.dart';
import 'package:riyaz/app/theme/type_roles.dart';

/// The overline naming a group of rows, with an optional tally on the right.
///
/// It exists because of principle 3: daily commitments and period targets
/// never share a group. Once they are two groups, each needs saying which is
/// which — otherwise the split looks like a rendering accident rather than the
/// distinction it is.
class SectionHeader extends StatelessWidget {
  const SectionHeader({required this.title, this.trailing, super.key});

  final String title;

  /// A count, or a reassurance like "Never late". Null when the group's name
  /// says everything.
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.sectionOverline;

    return Semantics(
      header: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: style?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: Insets.rowTrailingGap),
            Flexible(
              child: Text(
                trailing!.toUpperCase(),
                textAlign: TextAlign.end,
                style: style?.copyWith(color: context.statusColors.done),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
