import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();
String nowIso() => DateTime.now().toUtc().toIso8601String();

Future<void> logActivity(
  DatabaseExecutor db, {
  required String? groupId,
  required String actorId,
  required String entityType,
  required String entityId,
  required String action,
  Map<String, Object?>? details,
}) async {
  await db.insert('activity_logs', {
    'id': newId(),
    'group_id': groupId,
    'actor_id': actorId,
    'entity_type': entityType,
    'entity_id': entityId,
    'action': action,
    'details': details == null ? null : jsonEncode(details),
    'created_at': nowIso(),
  });
}
