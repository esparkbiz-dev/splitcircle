import 'package:sqflite/sqflite.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/db_helpers.dart';
import '../../../shared/models/models.dart';
import '../domain/balance_engine.dart';
import 'ledger_queries.dart';

const kPaymentMethods = ['cash', 'upi', 'bank_transfer', 'other'];

/// Records offline payments only. No payment provider is integrated, so
/// nothing here moves real money; "confirmed" means both people agree the
/// payment happened outside the app.
class SettlementRepository {
  final Database db;
  SettlementRepository(this.db);

  /// [confirmedByReceiver] = true records an offline payment as completed.
  /// false creates a pending request the receiver must confirm.
  Future<String> record({
    required String clientRequestId,
    required String groupId,
    required String actorId,
    required String fromId,
    required String toId,
    required int amountMinor,
    required String currency,
    required String method,
    required DateTime date,
    String? note,
    String? proofPath,
    required bool confirmedByReceiver,
  }) {
    return db.transaction((txn) async {
      final dup = await txn.query('settlements',
          columns: ['id'],
          where: 'client_request_id = ?',
          whereArgs: [clientRequestId]);
      if (dup.isNotEmpty) return dup.first['id'] as String;

      if (amountMinor <= 0) {
        throw const AppException('Amount must be greater than zero.');
      }
      if (fromId == toId) {
        throw const AppException('Cannot settle with yourself.');
      }
      if (!kPaymentMethods.contains(method)) {
        throw const AppException('Unknown payment method.');
      }
      final g = await txn.query('groups',
          columns: ['archived_at'], where: 'id = ?', whereArgs: [groupId]);
      if (g.isEmpty) throw const AppException('Group not found.');
      if (g.first['archived_at'] != null) {
        throw const AppException('This group is archived and read-only.');
      }
      for (final id in [fromId, toId, actorId]) {
        final m = await txn.query('group_members',
            where: "group_id = ? AND profile_id = ? AND status = 'active'",
            whereArgs: [groupId, id]);
        if (m.isEmpty) {
          throw const AppException('Both people must be active group members.');
        }
      }
      final id = newId();
      final now = nowIso();
      await txn.insert('settlements', {
        'id': id,
        'group_id': groupId,
        'client_request_id': clientRequestId,
        'from_profile': fromId,
        'to_profile': toId,
        'amount_minor': amountMinor,
        'currency': currency,
        'method': method,
        'settled_on': date.toUtc().toIso8601String(),
        'note': note,
        'proof_path': proofPath,
        'status': confirmedByReceiver ? 'confirmed' : 'pending',
        'created_by': actorId,
        'created_at': now,
        'confirmed_at': confirmedByReceiver ? now : null,
      });
      await logActivity(txn,
          groupId: groupId,
          actorId: actorId,
          entityType: 'settlement',
          entityId: id,
          action: confirmedByReceiver ? 'recorded_confirmed' : 'requested',
          details: {'amount_minor': amountMinor, 'currency': currency});
      return id;
    });
  }

  /// Only the receiver of the money can confirm a pending settlement.
  Future<void> confirm({required String settlementId, required String actorId}) {
    return db.transaction((txn) async {
      final r = await txn.query('settlements',
          where: 'id = ?', whereArgs: [settlementId]);
      if (r.isEmpty) throw const AppException('Settlement not found.');
      final s = r.first;
      if (s['status'] != 'pending') {
        throw const AppException('Only pending settlements can be confirmed.');
      }
      if (s['to_profile'] != actorId) {
        throw const AppException('Only the person receiving the money can confirm.');
      }
      await txn.update('settlements',
          {'status': 'confirmed', 'confirmed_at': nowIso()},
          where: 'id = ?', whereArgs: [settlementId]);
      await logActivity(txn,
          groupId: s['group_id'] as String,
          actorId: actorId,
          entityType: 'settlement',
          entityId: settlementId,
          action: 'confirmed');
    });
  }

  /// Auditable reversal: the row is kept with status 'reversed' and a reason.
  Future<void> reverse(
      {required String settlementId,
      required String actorId,
      required String reason}) {
    return db.transaction((txn) async {
      if (reason.trim().isEmpty) {
        throw const AppException('A reason is required to reverse a settlement.');
      }
      final r = await txn.query('settlements',
          where: 'id = ?', whereArgs: [settlementId]);
      if (r.isEmpty) throw const AppException('Settlement not found.');
      final s = r.first;
      if (s['status'] == 'reversed') {
        throw const AppException('Already reversed.');
      }
      final allowed = {s['from_profile'], s['to_profile'], s['created_by']};
      if (!allowed.contains(actorId)) {
        throw const AppException('Only people involved can reverse this.');
      }
      await txn.update(
          'settlements',
          {
            'status': 'reversed',
            'reversal_reason': reason.trim(),
            'reversed_at': nowIso(),
          },
          where: 'id = ?',
          whereArgs: [settlementId]);
      await logActivity(txn,
          groupId: s['group_id'] as String,
          actorId: actorId,
          entityType: 'settlement',
          entityId: settlementId,
          action: 'reversed',
          details: {'reason': reason.trim()});
    });
  }

  Future<List<SettlementView>> list(String groupId) async {
    final rows = await db.query('settlements',
        where: 'group_id = ?', whereArgs: [groupId], orderBy: 'created_at DESC');
    return rows
        .map((r) => SettlementView(
              id: r['id'] as String,
              fromId: r['from_profile'] as String,
              toId: r['to_profile'] as String,
              amountMinor: r['amount_minor'] as int,
              currency: r['currency'] as String,
              method: r['method'] as String,
              date: DateTime.parse(r['settled_on'] as String).toLocal(),
              status: r['status'] as String,
              note: r['note'] as String?,
            ))
        .toList();
  }

  /// currency -> suggested transfers that clear the group.
  Future<Map<String, List<Transfer>>> suggestions(String groupId) async {
    final nets = await loadNetBalances(db, groupId);
    return {for (final e in nets.entries) e.key: simplifyDebts(e.value)}
      ..removeWhere((_, v) => v.isEmpty);
  }
}
