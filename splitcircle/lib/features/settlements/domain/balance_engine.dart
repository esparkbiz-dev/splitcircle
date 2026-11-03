import '../../../core/errors/app_exception.dart';

class ExpenseRecord {
  final String payerId;
  final String currency;
  final int totalMinor;
  final Map<String, int> shares;
  const ExpenseRecord({
    required this.payerId,
    required this.currency,
    required this.totalMinor,
    required this.shares,
  });
}

/// [fromId] paid [toId]. Only confirmed settlements should be passed in.
class SettlementRecord {
  final String fromId;
  final String toId;
  final String currency;
  final int amountMinor;
  const SettlementRecord({
    required this.fromId,
    required this.toId,
    required this.currency,
    required this.amountMinor,
  });
}

class Transfer {
  final String fromId;
  final String toId;
  final int amountMinor;
  const Transfer(this.fromId, this.toId, this.amountMinor);

  @override
  bool operator ==(Object o) =>
      o is Transfer &&
      o.fromId == fromId &&
      o.toId == toId &&
      o.amountMinor == amountMinor;
  @override
  int get hashCode => Object.hash(fromId, toId, amountMinor);
  @override
  String toString() => 'Transfer($fromId -> $toId, $amountMinor)';
}

/// currency -> memberId -> net minor units.
/// Positive = the member is owed money. Negative = the member owes money.
Map<String, Map<String, int>> computeNetBalances({
  required Iterable<ExpenseRecord> expenses,
  required Iterable<SettlementRecord> settlements,
}) {
  final out = <String, Map<String, int>>{};
  void add(String cur, String id, int v) {
    final m = out.putIfAbsent(cur, () => <String, int>{});
    m[id] = (m[id] ?? 0) + v;
  }

  for (final e in expenses) {
    final shareSum = e.shares.values.fold<int>(0, (a, b) => a + b);
    if (shareSum != e.totalMinor) {
      throw AppException('Corrupt expense: shares ($shareSum) != total (${e.totalMinor}).');
    }
    add(e.currency, e.payerId, e.totalMinor);
    e.shares.forEach((id, s) => add(e.currency, id, -s));
  }
  for (final s in settlements) {
    add(s.currency, s.fromId, s.amountMinor);
    add(s.currency, s.toId, -s.amountMinor);
  }

  for (final entry in out.entries) {
    final sum = entry.value.values.fold<int>(0, (a, b) => a + b);
    if (sum != 0) {
      throw AppException('Ledger imbalance in ${entry.key}: $sum');
    }
  }
  return out;
}

/// Greedy debt simplification for ONE currency. Matches the largest debtor
/// with the largest creditor repeatedly. Every member's net balance is
/// preserved exactly, and the number of transfers is at most (non-zero members - 1).
List<Transfer> simplifyDebts(Map<String, int> net) {
  final creditors = <MapEntry<String, int>>[];
  final debtors = <MapEntry<String, int>>[];
  final keys = net.keys.toList()..sort();
  for (final k in keys) {
    final v = net[k]!;
    if (v > 0) creditors.add(MapEntry(k, v));
    if (v < 0) debtors.add(MapEntry(k, -v));
  }
  int byAmount(MapEntry<String, int> a, MapEntry<String, int> b) {
    final c = b.value.compareTo(a.value);
    return c != 0 ? c : a.key.compareTo(b.key);
  }

  final result = <Transfer>[];
  while (creditors.isNotEmpty && debtors.isNotEmpty) {
    creditors.sort(byAmount);
    debtors.sort(byAmount);
    final c = creditors.first;
    final d = debtors.first;
    final amt = c.value < d.value ? c.value : d.value;
    result.add(Transfer(d.key, c.key, amt));
    creditors.removeAt(0);
    debtors.removeAt(0);
    if (c.value - amt > 0) creditors.add(MapEntry(c.key, c.value - amt));
    if (d.value - amt > 0) debtors.add(MapEntry(d.key, d.value - amt));
  }
  return result;
}
