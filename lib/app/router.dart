import 'package:go_router/go_router.dart';

import '../domain/time/civil_date.dart';

import '../features/add_commitment/add_commitment_screen.dart';
import '../features/commitment/commitment_detail_screen.dart';
import '../features/review/week_review_screen.dart';
import 'shell.dart';

final GoRouter router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const AppShell(),
      routes: [
        GoRoute(
          path: 'add',
          builder: (context, state) => const AddCommitmentScreen(),
        ),
        GoRoute(
          path: 'review',
          builder: (context, state) => const WeekReviewScreen(),
          routes: [
            GoRoute(
              path: ':week',
              builder: (context, state) => WeekReviewScreen(
                weekStart:
                    CivilDate.parse(state.pathParameters['week']!),
              ),
            ),
          ],
        ),
        GoRoute(
          path: 'commitment/:id',
          builder: (context, state) => CommitmentDetailScreen(
            commitmentId: state.pathParameters['id']!,
          ),
        ),
      ],
    ),
  ],
);
