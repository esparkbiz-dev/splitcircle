# SplitCircle (local-first)

Shared-expense app. **All data is stored on the device in SQLite** (`sqflite`).
No server, no account, no network needed.

## Run it

```bash
cd splitcircle
flutter create . --platforms android,ios   # generates android/ and ios/ only; keeps lib/
flutter pub get
flutter run
flutter test                                # engine + repository tests
dart run tool/verify_engines.dart           # pure-Dart check, no Flutter needed
```

Requires Flutter 3.27+ (uses `CardThemeData`). Run `flutter pub upgrade` to take current package versions.

## Architecture

```
lib/
  core/        database (schema), theme, utils (money, ids), errors
  features/
    expenses/    domain/split_engine.dart      data/expense_repository.dart   presentation/
    settlements/ domain/balance_engine.dart    data/{ledger_queries,settlement_repository}.dart
    groups/      data/group_repository.dart    presentation/
    dashboard/   presentation/
  shared/        models, providers (Riverpod)
```

Money rules: integer minor units everywhere, no `double`. Splits use the
largest-remainder method so shares always add up to the total exactly.
Balances are **derived** from live expenses + confirmed settlements, never stored,
so edit / delete / reversal are correct by construction. Deletes are soft
(row kept for audit). Every financial write runs in one SQLite transaction,
is idempotent via `client_request_id`, and writes an `activity_logs` row.

## Status checklist

Legend: [x] done and verified here, [~] written, needs `flutter test` on your machine, [ ] not started

- [x] Money parsing/formatting, 5 split methods, validation (verified: 7,000 randomized iterations)
- [x] Balance engine + debt simplification (net balances preserved, transfer count bound)
- [~] SQLite schema (all 12 required tables, FKs, CHECKs, indexes)
- [~] Group / expense / settlement repositories (atomic, idempotent, audited, archive-aware)
- [~] Repository tests (duplicates, edit/delete reversal, pending vs confirmed, reversal, atomicity)
- [~] Dashboard, group detail, add-expense (all 5 split methods, live share preview), settle, reverse, archive
- [ ] Onboarding / profile setup / settings / theme switch
- [ ] Edit-expense screen (repository `update` is done)
- [ ] Receipts + payment proof (table + `proof_path` exist; needs image_picker + app-private file storage)
- [ ] Group members screen (add/remove UI; repository done), invite codes (table exists)
- [ ] Friends, activity feed, notifications + reminders (flutter_local_notifications)
- [ ] Analytics charts, PDF/CSV export, JSON data export, delete-all-data
- [ ] Draft expenses / sync status (only needed if a backend is added later)
- [ ] Multi-currency conversion (needs an explicit rate source)

## Local-first limits

- One device = one user. Other members are local names, not accounts, so there are
  no cross-device invitations, push notifications or shared live balances.
- "Mark paid" records a payment made outside the app. Nothing moves real money.
- Adding a backend later (e.g. Supabase) means syncing these same tables; the
  `client_request_id` columns are already there for idempotent sync.
