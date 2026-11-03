// Pure-Dart verification (no Flutter needed): dart run tool/verify_engines.dart
import 'dart:math';
import '../lib/core/errors/app_exception.dart';
import '../lib/core/utils/money.dart';
import '../lib/features/expenses/domain/split_engine.dart';
import '../lib/features/settlements/domain/balance_engine.dart';

int failures = 0;
void check(bool ok, String name) {
  if (!ok) {
    failures++;
    print('FAIL: $name');
  }
}

bool throwsApp(void Function() f) {
  try {
    f();
  } on AppException {
    return true;
  }
  return false;
}

void main() {
  final rnd = Random(42);

  // 1. Split methods always sum exactly to the total (randomized).
  for (var n = 0; n < 5000; n++) {
    final total = 1 + rnd.nextInt(10000000);
    final k = 1 + rnd.nextInt(9);
    final ids = List.generate(k, (i) => 'm$i');
    final eq = computeSplit(
        totalMinor: total,
        method: SplitMethod.equal,
        entries: ids.map(SplitEntry.new).toList());
    check(eq.values.fold(0, (a, b) => a + b) == total, 'equal sum');
    check(eq.values.reduce(max) - eq.values.reduce(min) <= 1, 'equal spread');

    final sh = computeSplit(
        totalMinor: total,
        method: SplitMethod.shares,
        entries: ids.map((i) => SplitEntry(i, 1 + rnd.nextInt(7))).toList());
    check(sh.values.fold(0, (a, b) => a + b) == total, 'shares sum');

    // random percentages summing to 10000
    var left = 10000;
    final pct = <SplitEntry>[];
    for (var i = 0; i < k; i++) {
      final v = i == k - 1 ? left : 1 + rnd.nextInt(max(1, left - (k - 1 - i)));
      if (v <= 0 || (i < k - 1 && left - v < k - 1 - i)) {
        pct.clear();
        break;
      }
      pct.add(SplitEntry(ids[i], v));
      left -= v;
    }
    if (pct.length == k && left == 0) {
      final r = computeSplit(
          totalMinor: total, method: SplitMethod.percentage, entries: pct);
      check(r.values.fold(0, (a, b) => a + b) == total, 'pct sum');
    }
  }

  // 2. Documented example.
  final ex = computeSplit(
      totalMinor: 300000,
      method: SplitMethod.equal,
      entries: const [SplitEntry('h'), SplitEntry('b'), SplitEntry('c')]);
  final nets = computeNetBalances(expenses: [
    ExpenseRecord(payerId: 'h', currency: 'INR', totalMinor: 300000, shares: ex)
  ], settlements: const []);
  check(nets['INR']!['h'] == 200000 && nets['INR']!['b'] == -100000, 'hardik example');

  // 3. Validation.
  check(throwsApp(() => computeSplit(totalMinor: 0, method: SplitMethod.equal, entries: const [SplitEntry('a')])), 'zero total');
  check(throwsApp(() => computeSplit(totalMinor: 100, method: SplitMethod.percentage, entries: const [SplitEntry('a', 5000), SplitEntry('b', 4000)])), 'pct != 100');
  check(throwsApp(() => computeSplit(totalMinor: 100, method: SplitMethod.exact, entries: const [SplitEntry('a', 40), SplitEntry('b', 50)])), 'exact != total');
  check(throwsApp(() => computeSplit(totalMinor: 100, method: SplitMethod.equal, entries: const [SplitEntry('a'), SplitEntry('a')])), 'dup');

  // 4. Randomized ledger: simplification preserves every net balance.
  for (var n = 0; n < 2000; n++) {
    final members = List.generate(2 + rnd.nextInt(8), (i) => 'u$i');
    final expenses = <ExpenseRecord>[];
    final settlements = <SettlementRecord>[];
    for (var e = 0; e < 1 + rnd.nextInt(12); e++) {
      final total = 1 + rnd.nextInt(500000);
      final parts = (List.of(members)..shuffle(rnd)).take(1 + rnd.nextInt(members.length)).toList();
      final shares = computeSplit(
          totalMinor: total,
          method: SplitMethod.equal,
          entries: parts.map(SplitEntry.new).toList());
      expenses.add(ExpenseRecord(
          payerId: members[rnd.nextInt(members.length)],
          currency: 'INR',
          totalMinor: total,
          shares: shares));
    }
    for (var s = 0; s < rnd.nextInt(4); s++) {
      final a = members[rnd.nextInt(members.length)];
      final b = members.where((m) => m != a).toList()[rnd.nextInt(members.length - 1)];
      settlements.add(SettlementRecord(fromId: a, toId: b, currency: 'INR', amountMinor: 1 + rnd.nextInt(10000)));
    }
    final net = computeNetBalances(expenses: expenses, settlements: settlements)['INR']!;
    check(net.values.fold(0, (a, b) => a + b) == 0, 'net sums to zero');
    final t = simplifyDebts(net);
    final after = Map<String, int>.from(net);
    for (final x in t) {
      after[x.fromId] = after[x.fromId]! + x.amountMinor;
      after[x.toId] = after[x.toId]! - x.amountMinor;
      check(x.amountMinor > 0, 'positive transfer');
    }
    check(after.values.every((v) => v == 0), 'simplification clears all balances');
    final nonZero = net.values.where((v) => v != 0).length;
    check(t.length <= max(0, nonZero - 1), 'transfer count bound');
  }

  // 5. Money parsing.
  check(parseToMinor('1,250.5', 'INR') == 125050, 'parse 1');
  check(parseToMinor('10.123', 'INR') == null, 'parse too many decimals');
  check(parseToMinor('5.5', 'JPY') == null, 'parse jpy');
  check(formatMinor(12345678, 'INR') == '₹1,23,456.78', 'format INR');
  check(formatMinor(-5, 'USD') == '-\$0.05', 'format neg');
  check(parsePercentToBps('33.33') == 3333, 'bps');

  print(failures == 0 ? 'ALL CHECKS PASSED' : '$failures FAILURES');
}
