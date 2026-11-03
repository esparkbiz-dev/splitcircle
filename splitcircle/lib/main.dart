import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/database/app_database.dart';
import 'features/groups/data/group_repository.dart';
import 'shared/providers/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDatabase.open();
  final me = await GroupRepository(db.db).ensureLocalUser();
  runApp(ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      meIdProvider.overrideWithValue(me),
    ],
    child: const SplitCircleApp(),
  ));
}
