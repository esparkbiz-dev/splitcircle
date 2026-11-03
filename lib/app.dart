import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'core/theme/app_theme.dart';
import 'features/dashboard/presentation/home_screen.dart';
import 'features/expenses/presentation/add_expense_screen.dart';
import 'features/groups/presentation/group_detail_screen.dart';

final _router = GoRouter(routes: [
  GoRoute(path: '/', builder: (_, __) => const HomeScreen(), routes: [
    GoRoute(
      path: 'group/:id',
      builder: (_, s) => GroupDetailScreen(groupId: s.pathParameters['id']!),
      routes: [
        GoRoute(
          path: 'add-expense',
          builder: (_, s) => AddExpenseScreen(groupId: s.pathParameters['id']!),
        ),
      ],
    ),
  ]),
]);

class SplitCircleApp extends StatelessWidget {
  const SplitCircleApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'SplitCircle',
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        routerConfig: _router,
      );
}
