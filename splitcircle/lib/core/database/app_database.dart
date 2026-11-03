import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Local SQLite database. All data lives on the device.
class AppDatabase {
  final Database db;
  AppDatabase._(this.db);

  static const int version = 1;

  /// [path] defaults to the app databases folder. Pass [inMemoryDatabasePath]
  /// and a ffi [factory] in tests.
  static Future<AppDatabase> open({String? path, DatabaseFactory? factory}) async {
    final f = factory ?? databaseFactory;
    final resolved = path ?? p.join(await f.getDatabasesPath(), 'splitcircle.db');
    final db = await f.openDatabase(
      resolved,
      options: OpenDatabaseOptions(
        version: version,
        onConfigure: (d) async => d.execute('PRAGMA foreign_keys = ON'),
        onCreate: (d, v) async {
          for (final s in _schema) {
            await d.execute(s);
          }
        },
      ),
    );
    return AppDatabase._(db);
  }

  Future<void> close() => db.close();
}

const List<String> _schema = [
  '''
CREATE TABLE profiles (
  id TEXT PRIMARY KEY,
  display_name TEXT NOT NULL,
  email TEXT,
  phone TEXT,
  avatar_path TEXT,
  is_local_user INTEGER NOT NULL DEFAULT 0,
  default_currency TEXT NOT NULL DEFAULT 'INR',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)''',
  '''
CREATE TABLE groups (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  category TEXT NOT NULL CHECK (category IN ('trip','home','couple','family','friends','other')),
  icon TEXT NOT NULL DEFAULT 'group',
  color INTEGER NOT NULL DEFAULT 4280391411,
  default_currency TEXT NOT NULL DEFAULT 'INR',
  created_by TEXT NOT NULL REFERENCES profiles(id),
  archived_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)''',
  '''
CREATE TABLE group_members (
  id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
  profile_id TEXT NOT NULL REFERENCES profiles(id),
  role TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('admin','member')),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','removed','left')),
  joined_at TEXT NOT NULL,
  left_at TEXT,
  UNIQUE (group_id, profile_id)
)''',
  '''
CREATE TABLE group_invitations (
  id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
  code TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','accepted','rejected','expired')),
  invited_by TEXT NOT NULL REFERENCES profiles(id),
  expires_at TEXT NOT NULL,
  created_at TEXT NOT NULL
)''',
  '''
CREATE TABLE friends (
  id TEXT PRIMARY KEY,
  owner_id TEXT NOT NULL REFERENCES profiles(id),
  friend_id TEXT NOT NULL REFERENCES profiles(id),
  created_at TEXT NOT NULL,
  UNIQUE (owner_id, friend_id),
  CHECK (owner_id <> friend_id)
)''',
  '''
CREATE TABLE expenses (
  id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
  client_request_id TEXT NOT NULL UNIQUE,
  description TEXT NOT NULL,
  amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
  currency TEXT NOT NULL,
  category TEXT NOT NULL DEFAULT 'other',
  expense_date TEXT NOT NULL,
  paid_by TEXT NOT NULL REFERENCES profiles(id),
  split_method TEXT NOT NULL CHECK (split_method IN ('equal','exact','percentage','shares','custom')),
  notes TEXT,
  created_by TEXT NOT NULL REFERENCES profiles(id),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT
)''',
  '''
CREATE TABLE expense_participants (
  id TEXT PRIMARY KEY,
  expense_id TEXT NOT NULL REFERENCES expenses(id) ON DELETE CASCADE,
  profile_id TEXT NOT NULL REFERENCES profiles(id),
  share_minor INTEGER NOT NULL CHECK (share_minor >= 0),
  split_value INTEGER NOT NULL DEFAULT 0,
  UNIQUE (expense_id, profile_id)
)''',
  '''
CREATE TABLE settlements (
  id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
  client_request_id TEXT NOT NULL UNIQUE,
  from_profile TEXT NOT NULL REFERENCES profiles(id),
  to_profile TEXT NOT NULL REFERENCES profiles(id),
  amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
  currency TEXT NOT NULL,
  method TEXT NOT NULL CHECK (method IN ('cash','upi','bank_transfer','other')),
  settled_on TEXT NOT NULL,
  note TEXT,
  proof_path TEXT,
  status TEXT NOT NULL CHECK (status IN ('pending','confirmed','reversed')),
  reversal_reason TEXT,
  created_by TEXT NOT NULL REFERENCES profiles(id),
  created_at TEXT NOT NULL,
  confirmed_at TEXT,
  reversed_at TEXT,
  CHECK (from_profile <> to_profile)
)''',
  '''
CREATE TABLE expense_receipts (
  id TEXT PRIMARY KEY,
  expense_id TEXT NOT NULL REFERENCES expenses(id) ON DELETE CASCADE,
  file_path TEXT NOT NULL,
  created_at TEXT NOT NULL
)''',
  '''
CREATE TABLE notifications (
  id TEXT PRIMARY KEY,
  profile_id TEXT NOT NULL REFERENCES profiles(id),
  type TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT,
  related_id TEXT,
  is_read INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
)''',
  '''
CREATE TABLE activity_logs (
  id TEXT PRIMARY KEY,
  group_id TEXT REFERENCES groups(id) ON DELETE CASCADE,
  actor_id TEXT NOT NULL REFERENCES profiles(id),
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  action TEXT NOT NULL,
  details TEXT,
  created_at TEXT NOT NULL
)''',
  '''
CREATE TABLE user_preferences (
  profile_id TEXT PRIMARY KEY REFERENCES profiles(id),
  theme_mode TEXT NOT NULL DEFAULT 'system',
  language TEXT NOT NULL DEFAULT 'en',
  notify_expenses INTEGER NOT NULL DEFAULT 1,
  notify_settlements INTEGER NOT NULL DEFAULT 1,
  notify_reminders INTEGER NOT NULL DEFAULT 1
)''',
  'CREATE INDEX idx_members_group ON group_members(group_id, status)',
  'CREATE INDEX idx_expenses_group ON expenses(group_id, deleted_at, expense_date)',
  'CREATE INDEX idx_participants_expense ON expense_participants(expense_id)',
  'CREATE INDEX idx_settlements_group ON settlements(group_id, status)',
  'CREATE INDEX idx_activity_group ON activity_logs(group_id, created_at)',
  'CREATE INDEX idx_notifications_profile ON notifications(profile_id, is_read)',
];
