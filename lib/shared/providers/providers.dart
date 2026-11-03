import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/app_database.dart';
import '../../features/expenses/data/expense_repository.dart';
import '../../features/groups/data/group_repository.dart';
import '../../features/settlements/data/settlement_repository.dart';
import '../../features/settlements/domain/balance_engine.dart';
import '../models/models.dart';

// Overridden in main().
final appDatabaseProvider =
    Provider<AppDatabase>((_) => throw UnimplementedError('db not opened'));
final meIdProvider =
    Provider<String>((_) => throw UnimplementedError('user not ready'));

final groupRepoProvider =
    Provider((ref) => GroupRepository(ref.watch(appDatabaseProvider).db));
final expenseRepoProvider =
    Provider((ref) => ExpenseRepository(ref.watch(appDatabaseProvider).db));
final settlementRepoProvider =
    Provider((ref) => SettlementRepository(ref.watch(appDatabaseProvider).db));

class GroupRow {
  final GroupSummary group;
  /// My net in the group's currency. +ve = owed to me, -ve = I owe.
  final int myNet;
  const GroupRow(this.group, this.myNet);
}

class DashboardData {
  final List<GroupRow> groups;
  /// currency -> amount others owe me
  final Map<String, int> owedToMe;
  /// currency -> amount I owe others
  final Map<String, int> iOwe;
  const DashboardData(this.groups, this.owedToMe, this.iOwe);
}

final dashboardProvider = FutureProvider.autoDispose<DashboardData>((ref) async {
  final repo = ref.watch(groupRepoProvider);
  final me = ref.watch(meIdProvider);
  final groups = await repo.listGroups();
  final rows = <GroupRow>[];
  final owedToMe = <String, int>{};
  final iOwe = <String, int>{};
  for (final g in groups) {
    final nets = await repo.balances(g.id);
    rows.add(GroupRow(g, nets[g.currency]?[me] ?? 0));
    nets.forEach((cur, m) {
      final v = m[me] ?? 0;
      if (v > 0) owedToMe[cur] = (owedToMe[cur] ?? 0) + v;
      if (v < 0) iOwe[cur] = (iOwe[cur] ?? 0) - v;
    });
  }
  return DashboardData(rows, owedToMe, iOwe);
});

class GroupDetail {
  final GroupSummary group;
  final List<Member> members;
  final List<ExpenseView> expenses;
  final List<SettlementView> settlements;
  final Map<String, Map<String, int>> balances;
  final Map<String, List<Transfer>> suggestions;
  const GroupDetail(this.group, this.members, this.expenses, this.settlements,
      this.balances, this.suggestions);

  String nameOf(String id) =>
      members.where((m) => m.id == id).map((m) => m.name).firstOrNull ?? 'Former member';
  int get totalSpent => expenses.fold(0, (a, e) => a + e.amountMinor);
}

final groupDetailProvider =
    FutureProvider.autoDispose.family<GroupDetail, String>((ref, id) async {
  final gr = ref.watch(groupRepoProvider);
  final group = await gr.getGroup(id);
  if (group == null) throw StateError('Group not found');
  final members = await gr.listMembers(id, activeOnly: false);
  return GroupDetail(
    group,
    members,
    await ref.watch(expenseRepoProvider).list(id),
    await ref.watch(settlementRepoProvider).list(id),
    await gr.balances(id),
    await ref.watch(settlementRepoProvider).suggestions(id),
  );
});

void refreshAll(WidgetRef ref, String groupId) {
  ref.invalidate(groupDetailProvider(groupId));
  ref.invalidate(dashboardProvider);
}
