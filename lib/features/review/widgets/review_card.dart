import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riyaz/app/theme/riyaz_theme.dart';
import 'package:riyaz/app/theme/tokens.dart';
import 'package:riyaz/app/theme/type_roles.dart';

import '../week_review_controller.dart';

/// The prompt that makes a closed week a *moment* rather than a screen nobody
/// opens.
///
/// It sits above the day's headline on Monday and disappears once read. That
/// is the whole reason the review exists as its own surface: the numbers were
/// already reachable on History and Insights, and being reachable is not the
/// same as being seen. A week that closes silently teaches the user that weeks
/// do not close.
///
/// It renders nothing at all when there is nothing to say — no closed week with
/// anything in it, or one already dismissed — so it never becomes chrome the
/// eye learns to skip.
class ReviewCard extends ConsumerWidget {
  const ReviewCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(reviewPendingProvider).value ?? false;
    if (!pending) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.rowH),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(Radii.row),
        child: InkWell(
          onTap: () => context.push('/review'),
          borderRadius: BorderRadius.circular(Radii.row),
          child: Padding(
            padding: const EdgeInsets.all(Insets.rowH),
            child: Row(
              children: [
                Icon(
                  Icons.event_available_outlined,
                  size: 20,
                  color: context.statusColors.done,
                ),
                const SizedBox(width: Insets.rowTrailingGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Last week is in', style: theme.textTheme.rowTitle),
                      const SizedBox(height: Insets.titleGap),
                      Text(
                        'See how it went',
                        style:
                            theme.textTheme.footnote?.copyWith(color: muted),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
