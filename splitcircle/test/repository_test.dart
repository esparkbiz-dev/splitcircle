import 'package:flutter_test/flutter_test.dart';
import 'package:splitcircle/core/database/app_database.dart';
import 'package:splitcircle/core/errors/app_exception.dart';
import 'package:splitcircle/features/expenses/data/expense_repository.dart';
import 'package:splitcircle/features/expenses/domain/split_engine.dart';
import 'package:splitcircle/features/groups/data/group_repository.dart';
import 'package:splitcircle/features/settlements/data/settlement_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase app;
  late GroupRepository groups;
  late ExpenseRepository expenses;
  late SettlementRepository settlements;
  late String me;
  late String gid;
  late String b;
  late String c;

  ExpenseInput input({
    required String key,
    int amount = 300000,
    List<SplitEntry>? entries,
    SplitMethod method = SplitMethod.equal,
  }) =>
      ExpenseInput(
        clientRequestId: key,
        groupId: gid,
        actorId: me,
        description: 'Dinner',
        amountMinor: amount,
        currency: 'INR',
        category: 'food',
        date: DateTime(2026, 1, 1),
        paidBy: me,
        method: method,
        entries: entries ?? [SplitEntry(me), SplitEntry(b), SplitEntry(c)],
      );

  setUp(() async {
    app = await AppDatabase.open(
        path: inMemoryDatabasePath, factory: databaseFactoryFfi);
    groups = GroupRepository(app.db);
    expenses = ExpenseRepository(app.db);
    settlements = SettlementRepository(app.db);
    me = await groups.ensureLocalUser(defaultName: 'Hardik');
    gid = await groups.createGroup(
        actorId: me,
        name: 'Trip',
        category: 'trip',
        currency: 'INR',
        memberNames: ['B', 'C']);
    final members = await groups.listMembers(gid);
    b = members.firstWhere((m) => m.name == 'B').id;
    c = members.firstWhere((m) => m.name == 'C').id;
  });

  tearDown(() => app.close());

  test('expense updates balances immediately', () async {
    await expenses.create(input(key: 'k1'));
    final n = (await groups.balances(gid))['INR']!;
    expect(n[me], 200000);
    expect(n[b], -100000);
    expect(n[c], -100000);
  });

  test('retrying the same request id never duplicates', () async {
    final a = await expenses.create(input(key: 'same'));
    final again = await expenses.create(input(key: 'same'));
    expect(again, a);
    expect((await expenses.list(gid)).length, 1);
    expect((await groups.balances(gid))['INR']![me], 200000);
  });

  test('edit recalculates and delete reverses', () async {
    final id = await expenses.create(input(key: 'k1'));
    await expenses.update(id, input(key: 'k1-edit', amount: 600000));
    expect((await groups.balances(gid))['INR']![me], 400000);
    await expenses.delete(expenseId: id, groupId: gid, actorId: me);
    expect((await groups.balances(gid)), isEmpty);
    final log = await app.db.query('activity_logs',
        where: "entity_type = 'expense'");
    expect(log.map((r) => r['action']),
        containsAll(['created', 'edited', 'deleted']));
  });

  test('only confirmed settlements change balances; reversal restores', () async {
    await expenses.create(input(key: 'k1'));
    final sid = await settlements.record(
        clientRequestId: 's1',
        groupId: gid,
        actorId: b,
        fromId: b,
        toId: me,
        amountMinor: 100000,
        currency: 'INR',
        method: 'upi',
        date: DateTime.now(),
        confirmedByReceiver: false);
    expect((await groups.balances(gid))['INR']![b], -100000,
        reason: 'pending must not count');
    await settlements.confirm(settlementId: sid, actorId: me);
    expect((await groups.balances(gid))['INR']![b], 0);
    await settlements.reverse(
        settlementId: sid, actorId: me, reason: 'entered wrong');
    expect((await groups.balances(gid))['INR']![b], -100000);
  });

  test('payer cannot confirm their own settlement', () async {
    await expenses.create(input(key: 'k1'));
    final sid = await settlements.record(
        clientRequestId: 's1',
        groupId: gid,
        actorId: b,
        fromId: b,
        toId: me,
        amountMinor: 100,
        currency: 'INR',
        method: 'cash',
        date: DateTime.now(),
        confirmedByReceiver: false);
    expect(() => settlements.confirm(settlementId: sid, actorId: b),
        throwsA(isA<AppException>()));
  });

  test('non-member and archived group are rejected', () async {
    final outsider = await groups.createProfile('Outsider');
    expect(
        () => expenses.create(input(key: 'x', entries: [SplitEntry(outsider)])),
        throwsA(isA<AppException>()));
    await groups.setArchived(groupId: gid, actorId: me, archived: true);
    expect(() => expenses.create(input(key: 'y')),
        throwsA(isA<AppException>()));
  });

  test('member with unsettled balance cannot be removed', () async {
    await expenses.create(input(key: 'k1'));
    expect(
        () => groups.removeMember(groupId: gid, actorId: me, memberId: b),
        throwsA(isA<AppException>()));
  });

  test('failed expense leaves nothing behind (atomic)', () async {
    try {
      await expenses.create(input(
          key: 'bad',
          method: SplitMethod.exact,
          entries: [SplitEntry(me, 1), SplitEntry(b, 1)]));
    } on AppException {
      // expected
    }
    expect((await expenses.list(gid)), isEmpty);
  });

  test('suggestions simplify to minimal transfers', () async {
    await expenses.create(input(key: 'k1'));
    final s = (await settlements.suggestions(gid))['INR']!;
    expect(s.length, 2);
    expect(s.every((t) => t.toId == me), isTrue);
  });
}
