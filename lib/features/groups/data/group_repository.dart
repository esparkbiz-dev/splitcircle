import 'package:sqflite/sqflite.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/db_helpers.dart';
import '../../../shared/models/models.dart';
import '../../settlements/data/ledger_queries.dart';

class GroupRepository {
  final Database db;
  GroupRepository(this.db);

  /// Returns the id of the single on-device user, creating it on first run.
  Future<String> ensureLocalUser({String defaultName = 'Me'}) async {
    final rows = await db.query('profiles',
        where: 'is_local_user = 1', limit: 1);
    if (rows.isNotEmpty) return rows.first['id'] as String;
    final id = newId();
    final now = nowIso();
    await db.insert('profiles', {
      'id': id,
      'display_name': defaultName,
      'is_local_user': 1,
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('user_preferences', {'profile_id': id});
    return id;
  }

  Future<String> createProfile(String displayName, {String? email}) async {
    final name = displayName.trim();
    if (name.isEmpty) throw const AppException('Name is required.');
    final id = newId();
    final now = nowIso();
    await db.insert('profiles', {
      'id': id,
      'display_name': name,
      'email': email,
      'created_at': now,
      'updated_at': now,
    });
    return id;
  }

  Future<String> createGroup({
    required String actorId,
    required String name,
    required String category,
    required String currency,
    int color = 0xFF1E88E5,
    String icon = 'group',
    List<String> memberNames = const [],
  }) {
    final n = name.trim();
    if (n.isEmpty) throw const AppException('Group name is required.');
    return db.transaction((txn) async {
      final gid = newId();
      final now = nowIso();
      await txn.insert('groups', {
        'id': gid,
        'name': n,
        'category': category,
        'icon': icon,
        'color': color,
        'default_currency': currency,
        'created_by': actorId,
        'created_at': now,
        'updated_at': now,
      });
      await _addMember(txn, gid, actorId, 'admin');
      for (final raw in memberNames) {
        final mn = raw.trim();
        if (mn.isEmpty) continue;
        final pid = newId();
        await txn.insert('profiles', {
          'id': pid,
          'display_name': mn,
          'created_at': now,
          'updated_at': now,
        });
        await _addMember(txn, gid, pid, 'member');
      }
      await logActivity(txn,
          groupId: gid,
          actorId: actorId,
          entityType: 'group',
          entityId: gid,
          action: 'created',
          details: {'name': n});
      return gid;
    });
  }

  Future<void> _addMember(
      DatabaseExecutor d, String gid, String pid, String role) async {
    await d.insert('group_members', {
      'id': newId(),
      'group_id': gid,
      'profile_id': pid,
      'role': role,
      'joined_at': nowIso(),
    });
  }

  Future<void> addMember(
      {required String groupId, required String actorId, required String name}) {
    return db.transaction((txn) async {
      await _requireAdmin(txn, groupId, actorId);
      final pid = newId();
      final now = nowIso();
      await txn.insert('profiles', {
        'id': pid,
        'display_name': name.trim(),
        'created_at': now,
        'updated_at': now,
      });
      await _addMember(txn, groupId, pid, 'member');
      await logActivity(txn,
          groupId: groupId,
          actorId: actorId,
          entityType: 'member',
          entityId: pid,
          action: 'added',
          details: {'name': name.trim()});
    });
  }

  /// Removes a member. Blocked while they have a non-zero balance so no
  /// money is silently lost.
  Future<void> removeMember(
      {required String groupId, required String actorId, required String memberId}) {
    return db.transaction((txn) async {
      if (memberId != actorId) await _requireAdmin(txn, groupId, actorId);
      final nets = await loadNetBalances(txn, groupId);
      for (final m in nets.values) {
        if ((m[memberId] ?? 0) != 0) {
          throw const AppException(
              'This member has an unsettled balance. Settle up first.');
        }
      }
      final left = memberId == actorId;
      final n = await txn.update(
          'group_members',
          {'status': left ? 'left' : 'removed', 'left_at': nowIso()},
          where: "group_id = ? AND profile_id = ? AND status = 'active'",
          whereArgs: [groupId, memberId]);
      if (n == 0) throw const AppException('Member not found in this group.');
      await logActivity(txn,
          groupId: groupId,
          actorId: actorId,
          entityType: 'member',
          entityId: memberId,
          action: left ? 'left' : 'removed');
    });
  }

  Future<void> setArchived(
      {required String groupId, required String actorId, required bool archived}) {
    return db.transaction((txn) async {
      await _requireAdmin(txn, groupId, actorId);
      await txn.update(
          'groups',
          {'archived_at': archived ? nowIso() : null, 'updated_at': nowIso()},
          where: 'id = ?',
          whereArgs: [groupId]);
      await logActivity(txn,
          groupId: groupId,
          actorId: actorId,
          entityType: 'group',
          entityId: groupId,
          action: archived ? 'archived' : 'unarchived');
    });
  }

  Future<void> _requireAdmin(
      DatabaseExecutor d, String groupId, String actorId) async {
    final r = await d.query('group_members',
        where: "group_id = ? AND profile_id = ? AND status = 'active' AND role = 'admin'",
        whereArgs: [groupId, actorId]);
    if (r.isEmpty) throw const AppException('Only a group admin can do this.');
  }

  Future<List<GroupSummary>> listGroups({bool archived = false}) async {
    final rows = await db.query('groups',
        where: archived ? 'archived_at IS NOT NULL' : 'archived_at IS NULL',
        orderBy: 'created_at DESC');
    return rows.map(_group).toList();
  }

  Future<GroupSummary?> getGroup(String id) async {
    final rows = await db.query('groups', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _group(rows.first);
  }

  GroupSummary _group(Map<String, Object?> r) => GroupSummary(
        id: r['id'] as String,
        name: r['name'] as String,
        category: r['category'] as String,
        color: r['color'] as int,
        currency: r['default_currency'] as String,
        archived: r['archived_at'] != null,
      );

  Future<List<Member>> listMembers(String groupId, {bool activeOnly = true}) async {
    final rows = await db.rawQuery('''
      SELECT p.id, p.display_name, gm.role, gm.status
      FROM group_members gm JOIN profiles p ON p.id = gm.profile_id
      WHERE gm.group_id = ? ${activeOnly ? "AND gm.status = 'active'" : ''}
      ORDER BY gm.joined_at
    ''', [groupId]);
    return rows
        .map((r) => Member(r['id'] as String, r['display_name'] as String,
            r['role'] as String, r['status'] == 'active'))
        .toList();
  }

  Future<Map<String, Map<String, int>>> balances(String groupId) =>
      loadNetBalances(db, groupId);
}
