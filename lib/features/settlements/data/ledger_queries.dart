import 'package:sqflite/sqflite.dart';
import '../domain/balance_engine.dart';

/// Net balances for a group, derived from live expenses and CONFIRMED
/// settlements only. currency -> memberId -> net minor units.
Future<Map<String, Map<String, int>>> loadNetBalances(
    DatabaseExecutor db, String groupId) async {
  final exp = await db.query('expenses',
      where: 'group_id = ? AND deleted_at IS NULL', whereArgs: [groupId]);
  final parts = await db.rawQuery('''
    SELECT ep.expense_id, ep.profile_id, ep.share_minor
    FROM expense_participants ep
    JOIN expenses e ON e.id = ep.expense_id
    WHERE e.group_id = ? AND e.deleted_at IS NULL
  ''', [groupId]);

  final sharesByExpense = <String, Map<String, int>>{};
  for (final r in parts) {
    sharesByExpense
        .putIfAbsent(r['expense_id'] as String, () => {})[r['profile_id'] as String] =
        r['share_minor'] as int;
  }
  final expenses = exp.map((r) => ExpenseRecord(
        payerId: r['paid_by'] as String,
        currency: r['currency'] as String,
        totalMinor: r['amount_minor'] as int,
        shares: sharesByExpense[r['id'] as String] ?? const {},
      ));

  final sets = await db.query('settlements',
      where: "group_id = ? AND status = 'confirmed'", whereArgs: [groupId]);
  final settlements = sets.map((r) => SettlementRecord(
        fromId: r['from_profile'] as String,
        toId: r['to_profile'] as String,
        currency: r['currency'] as String,
        amountMinor: r['amount_minor'] as int,
      ));

  return computeNetBalances(expenses: expenses, settlements: settlements);
}
