import 'package:flutter_test/flutter_test.dart';
import 'package:splitcircle/features/settlements/domain/balance_engine.dart';

void main() {
  test('Hardik example: 3000 paid by Hardik, split 3 ways', () {
    final nets = computeNetBalances(expenses: const [
      ExpenseRecord(
          payerId: 'h',
          currency: 'INR',
          totalMinor: 300000,
          shares: {'h': 100000, 'b': 100000, 'c': 100000})
    ], settlements: const []);
    expect(nets['INR'], {'h': 200000, 'b': -100000, 'c': -100000});
  });

  test('confirmed settlement reduces debt', () {
    final nets = computeNetBalances(expenses: const [
      ExpenseRecord(
          payerId: 'h',
          currency: 'INR',
          totalMinor: 300000,
          shares: {'h': 100000, 'b': 100000, 'c': 100000})
    ], settlements: const [
      SettlementRecord(fromId: 'b', toId: 'h', currency: 'INR', amountMinor: 100000)
    ]);
    expect(nets['INR'], {'h': 100000, 'b': 0, 'c': -100000});
  });

  test('corrupt expense is detected', () {
    expect(
        () => computeNetBalances(expenses: const [
              ExpenseRecord(
                  payerId: 'a',
                  currency: 'INR',
                  totalMinor: 100,
                  shares: {'a': 50, 'b': 40})
            ], settlements: const []),
        throwsA(anything));
  });

  test('simplify preserves every net balance and uses few transfers', () {
    final net = {'a': 5000, 'b': -3000, 'c': -2000, 'd': 1000, 'e': -1000};
    final t = simplifyDebts(net);
    final check = <String, int>{for (final k in net.keys) k: 0};
    for (final x in t) {
      check[x.fromId] = check[x.fromId]! + x.amountMinor;
      check[x.toId] = check[x.toId]! - x.amountMinor;
    }
    // Paying transfers raises debtors back to 0.
    for (final k in net.keys) {
      expect(net[k]! + check[k]!, 0);
    }
    expect(t.length, lessThanOrEqualTo(4));
  });

  test('simplify of a cycle collapses to nothing', () {
    expect(simplifyDebts({'a': 0, 'b': 0, 'c': 0}), isEmpty);
  });
}
