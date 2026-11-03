import 'package:sqflite/sqflite.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/db_helpers.dart';
import '../../../shared/models/models.dart';
import '../domain/split_engine.dart';

class ExpenseInput {
  /// Client-generated UUID. Retrying with the same key never duplicates.
  final String clientRequestId;
  final String groupId;
  final String actorId;
  final String description;
  final int amountMinor;
  final String currency;
  final String category;
  final DateTime date;
  final String paidBy;
  final SplitMethod method;
  final List<SplitEntry> entries;
  final String? notes;

  const ExpenseInput({
    required this.clientRequestId,
    required this.groupId,
    required this.actorId,
    required this.description,
    required this.amountMinor,
    required this.currency,
    required this.category,
    required this.date,
    required this.paidBy,
    required this.method,
    required this.entries,
    this.notes,
  });
}

class ExpenseRepository {
  final Database db;
  ExpenseRepository(this.db);

  Future<String> create(ExpenseInput i) {
    return db.transaction((txn) async {
      final dup = await txn.query('expenses',
          columns: ['id'],
          where: 'client_request_id = ?',
          whereArgs: [i.clientRequestId]);
      if (dup.isNotEmpty) return dup.first['id'] as String;

      final shares = await _validate(txn, i);
      final id = newId();
      final now = nowIso();
      await txn.insert('expenses', {
        'id': id,
        'group_id': i.groupId,
        'client_request_id': i.clientRequestId,
        'description': i.description.trim(),
        'amount_minor': i.amountMinor,
        'currency': i.currency,
        'category': i.category,
        'expense_date': i.date.toUtc().toIso8601String(),
        'paid_by': i.paidBy,
        'split_method': i.method.name,
        'notes': i.notes,
        'created_by': i.actorId,
        'created_at': now,
        'updated_at': now,
      });
      await _writeParticipants(txn, id, i, shares);
      await logActivity(txn,
          groupId: i.groupId,
          actorId: i.actorId,
          entityType: 'expense',
          entityId: id,
          action: 'created',
          details: {'amount_minor': i.amountMinor, 'currency': i.currency});
      return id;
    });
  }

  Future<void> update(String expenseId, ExpenseInput i) {
    return db.transaction((txn) async {
      final old = await txn.query('expenses',
          where: 'id = ? AND group_id = ? AND deleted_at IS NULL',
          whereArgs: [expenseId, i.groupId]);
      if (old.isEmpty) throw const AppException('Expense not found.');
      final shares = await _validate(txn, i);
      await txn.update(
          'expenses',
          {
            'description': i.description.trim(),
            'amount_minor': i.amountMinor,
            'currency': i.currency,
            'category': i.category,
            'expense_date': i.date.toUtc().toIso8601String(),
            'paid_by': i.paidBy,
            'split_method': i.method.name,
            'notes': i.notes,
            'updated_at': nowIso(),
          },
          where: 'id = ?',
          whereArgs: [expenseId]);
      await txn.delete('expense_participants',
          where: 'expense_id = ?', whereArgs: [expenseId]);
      await _writeParticipants(txn, expenseId, i, shares);
      await logActivity(txn,
          groupId: i.groupId,
          actorId: i.actorId,
          entityType: 'expense',
          entityId: expenseId,
          action: 'edited',
          details: {
            'before_amount_minor': old.first['amount_minor'],
            'after_amount_minor': i.amountMinor,
          });
    });
  }

  /// Soft delete: the row stays for audit, but no longer counts in balances.
  Future<void> delete(
      {required String expenseId,
      required String groupId,
      required String actorId}) {
    return db.transaction((txn) async {
      await _requireActiveMember(txn, groupId, actorId);
      final n = await txn.update('expenses', {'deleted_at': nowIso()},
          where: 'id = ? AND group_id = ? AND deleted_at IS NULL',
          whereArgs: [expenseId, groupId]);
      if (n == 0) throw const AppException('Expense not found.');
      await logActivity(txn,
          groupId: groupId,
          actorId: actorId,
          entityType: 'expense',
          entityId: expenseId,
          action: 'deleted');
    });
  }

  Future<List<ExpenseView>> list(String groupId) async {
    final rows = await db.query('expenses',
        where: 'group_id = ? AND deleted_at IS NULL',
        whereArgs: [groupId],
        orderBy: 'expense_date DESC, created_at DESC');
    final parts = await db.rawQuery('''
      SELECT ep.expense_id, ep.profile_id, ep.share_minor
      FROM expense_participants ep JOIN expenses e ON e.id = ep.expense_id
      WHERE e.group_id = ? AND e.deleted_at IS NULL
    ''', [groupId]);
    final byExp = <String, Map<String, int>>{};
    for (final r in parts) {
      byExp.putIfAbsent(r['expense_id'] as String, () => {})[
          r['profile_id'] as String] = r['share_minor'] as int;
    }
    return rows
        .map((r) => ExpenseView(
              id: r['id'] as String,
              description: r['description'] as String,
              amountMinor: r['amount_minor'] as int,
              currency: r['currency'] as String,
              category: r['category'] as String,
              date: DateTime.parse(r['expense_date'] as String).toLocal(),
              paidBy: r['paid_by'] as String,
              method: SplitMethod.values.byName(r['split_method'] as String),
              notes: r['notes'] as String?,
              shares: byExp[r['id'] as String] ?? const {},
            ))
        .toList();
  }

  // ---- internals ----

  Future<Map<String, int>> _validate(DatabaseExecutor d, ExpenseInput i) async {
    if (i.description.trim().isEmpty) {
      throw const AppException('Description is required.');
    }
    if (i.amountMinor <= 0) {
      throw const AppException('Amount must be greater than zero.');
    }
    final g = await d.query('groups',
        columns: ['archived_at'], where: 'id = ?', whereArgs: [i.groupId]);
    if (g.isEmpty) throw const AppException('Group not found.');
    if (g.first['archived_at'] != null) {
      throw const AppException('This group is archived and read-only.');
    }
    await _requireActiveMember(d, i.groupId, i.actorId);
    final active = (await d.query('group_members',
            columns: ['profile_id'],
            where: "group_id = ? AND status = 'active'",
            whereArgs: [i.groupId]))
        .map((r) => r['profile_id'] as String)
        .toSet();
    if (!active.contains(i.paidBy)) {
      throw const AppException('Payer is not a member of this group.');
    }
    for (final e in i.entries) {
      if (!active.contains(e.memberId)) {
        throw const AppException('A participant is not a member of this group.');
      }
    }
    return computeSplit(
        totalMinor: i.amountMinor, method: i.method, entries: i.entries);
  }

  Future<void> _requireActiveMember(
      DatabaseExecutor d, String groupId, String profileId) async {
    final r = await d.query('group_members',
        where: "group_id = ? AND profile_id = ? AND status = 'active'",
        whereArgs: [groupId, profileId]);
    if (r.isEmpty) throw const AppException('You are not a member of this group.');
  }

  Future<void> _writeParticipants(DatabaseExecutor d, String expenseId,
      ExpenseInput i, Map<String, int> shares) async {
    final raw = {for (final e in i.entries) e.memberId: e.value};
    for (final entry in shares.entries) {
      await d.insert('expense_participants', {
        'id': newId(),
        'expense_id': expenseId,
        'profile_id': entry.key,
        'share_minor': entry.value,
        'split_value': raw[entry.key] ?? 0,
      });
    }
  }
}
