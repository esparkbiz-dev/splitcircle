import '../../../core/errors/app_exception.dart';

enum SplitMethod { equal, exact, percentage, shares, custom }

/// One participant's input.
/// - equal: value ignored
/// - exact / custom: minor units
/// - percentage: basis points (100% = 10000)
/// - shares: whole shares (e.g. 2, 1)
class SplitEntry {
  final String memberId;
  final int value;
  const SplitEntry(this.memberId, [this.value = 0]);
}

/// Distributes [total] across [weights] using the largest-remainder method.
/// The result always sums to exactly [total]. Ties are broken by input order,
/// so the result is deterministic.
Map<String, int> allocateProportionally(int total, Map<String, int> weights) {
  final sumW = weights.values.fold<int>(0, (a, b) => a + b);
  if (sumW <= 0) throw const AppException('Total weight must be positive.');
  final ids = weights.keys.toList();
  final base = <int>[];
  final rem = <int>[];
  for (final id in ids) {
    final w = weights[id]!;
    base.add(total * w ~/ sumW);
    rem.add(total * w % sumW);
  }
  var leftover = total - base.fold<int>(0, (a, b) => a + b);
  final order = List<int>.generate(ids.length, (i) => i)
    ..sort((a, b) {
      final c = rem[b].compareTo(rem[a]);
      return c != 0 ? c : a.compareTo(b);
    });
  for (final i in order) {
    if (leftover == 0) break;
    base[i] += 1;
    leftover--;
  }
  return {for (var i = 0; i < ids.length; i++) ids[i]: base[i]};
}

/// Computes each participant's owed share in minor units.
/// Throws [AppException] for any invalid input.
Map<String, int> computeSplit({
  required int totalMinor,
  required SplitMethod method,
  required List<SplitEntry> entries,
}) {
  if (totalMinor <= 0) {
    throw const AppException('Amount must be greater than zero.');
  }
  if (entries.isEmpty) {
    throw const AppException('Select at least one participant.');
  }
  final seen = <String>{};
  for (final e in entries) {
    if (!seen.add(e.memberId)) {
      throw const AppException('Duplicate participant in split.');
    }
  }

  switch (method) {
    case SplitMethod.equal:
      return allocateProportionally(
          totalMinor, {for (final e in entries) e.memberId: 1});

    case SplitMethod.shares:
      for (final e in entries) {
        if (e.value <= 0) {
          throw const AppException('Every share must be at least 1.');
        }
      }
      return allocateProportionally(
          totalMinor, {for (final e in entries) e.memberId: e.value});

    case SplitMethod.percentage:
      var sum = 0;
      for (final e in entries) {
        if (e.value <= 0) {
          throw const AppException('Every percentage must be above 0.');
        }
        sum += e.value;
      }
      if (sum != 10000) {
        throw const AppException('Percentages must add up to 100%.');
      }
      return allocateProportionally(
          totalMinor, {for (final e in entries) e.memberId: e.value});

    case SplitMethod.exact:
    case SplitMethod.custom:
      final allowZero = method == SplitMethod.custom;
      var sum = 0;
      var anyPositive = false;
      for (final e in entries) {
        if (e.value < 0 || (!allowZero && e.value == 0)) {
          throw const AppException('Amounts must be positive.');
        }
        if (e.value > 0) anyPositive = true;
        sum += e.value;
      }
      if (!anyPositive || sum != totalMinor) {
        throw const AppException('Amounts must add up to the expense total.');
      }
      return {for (final e in entries) e.memberId: e.value};
  }
}
