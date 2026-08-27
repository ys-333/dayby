import 'package:go_router/go_router.dart';

import '../features/add_commitment/add_commitment_screen.dart';
import '../features/commitment/commitment_detail_screen.dart';
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
          path: 'commitment/:id',
          builder: (context, state) => CommitmentDetailScreen(
            commitmentId: state.pathParameters['id']!,
          ),
        ),
      ],
    ),
  ],
);
