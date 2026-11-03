import 'package:flutter_test/flutter_test.dart';
import 'package:splitcircle/core/errors/app_exception.dart';
import 'package:splitcircle/core/utils/money.dart';
import 'package:splitcircle/features/expenses/domain/split_engine.dart';

int sum(Map<String, int> m) => m.values.fold(0, (a, b) => a + b);

void main() {
  group('equal split', () {
    test('3000 / 3', () {
      final r = computeSplit(
          totalMinor: 300000,
          method: SplitMethod.equal,
          entries: const [SplitEntry('a'), SplitEntry('b'), SplitEntry('c')]);
      expect(r, {'a': 100000, 'b': 100000, 'c': 100000});
    });
    test('100.00 / 3 sums exactly with remainder spread', () {
      final r = computeSplit(
          totalMinor: 10000,
          method: SplitMethod.equal,
          entries: const [SplitEntry('a'), SplitEntry('b'), SplitEntry('c')]);
      expect(sum(r), 10000);
      expect(r.values.toSet(), {3334, 3333});
    });
    test('0.01 / 3 gives the paisa to exactly one person', () {
      final r = computeSplit(
          totalMinor: 1,
          method: SplitMethod.equal,
          entries: const [SplitEntry('a'), SplitEntry('b'), SplitEntry('c')]);
      expect(sum(r), 1);
    });
  });

  group('shares', () {
    test('2:1 of 90.00', () {
      final r = computeSplit(
          totalMinor: 9000,
          method: SplitMethod.shares,
          entries: const [SplitEntry('a', 2), SplitEntry('b', 1)]);
      expect(r, {'a': 6000, 'b': 3000});
    });
    test('uneven shares still sum exactly', () {
      final r = computeSplit(
          totalMinor: 10001,
          method: SplitMethod.shares,
          entries: const [SplitEntry('a', 3), SplitEntry('b', 2), SplitEntry('c', 2)]);
      expect(sum(r), 10001);
    });
    test('zero share rejected', () {
      expect(
          () => computeSplit(
              totalMinor: 100,
              method: SplitMethod.shares,
              entries: const [SplitEntry('a', 0), SplitEntry('b', 1)]),
          throwsA(isA<AppException>()));
    });
  });

  group('percentage', () {
    test('50/30/20', () {
      final r = computeSplit(
          totalMinor: 10000,
          method: SplitMethod.percentage,
          entries: const [
            SplitEntry('a', 5000),
            SplitEntry('b', 3000),
            SplitEntry('c', 2000)
          ]);
      expect(r, {'a': 5000, 'b': 3000, 'c': 2000});
    });
    test('must total 100%', () {
      expect(
          () => computeSplit(
              totalMinor: 10000,
              method: SplitMethod.percentage,
              entries: const [SplitEntry('a', 5000), SplitEntry('b', 4000)]),
          throwsA(isA<AppException>()));
    });
    test('33.33 x3 is rejected, 33.34/33.33/33.33 accepted', () {
      expect(
          () => computeSplit(
              totalMinor: 10000,
              method: SplitMethod.percentage,
              entries: const [
                SplitEntry('a', 3333),
                SplitEntry('b', 3333),
                SplitEntry('c', 3333)
              ]),
          throwsA(isA<AppException>()));
      final r = computeSplit(
          totalMinor: 10000,
          method: SplitMethod.percentage,
          entries: const [
            SplitEntry('a', 3334),
            SplitEntry('b', 3333),
            SplitEntry('c', 3333)
          ]);
      expect(sum(r), 10000);
    });
  });

  group('exact / custom', () {
    test('exact must equal total', () {
      expect(
          () => computeSplit(
              totalMinor: 1000,
              method: SplitMethod.exact,
              entries: const [SplitEntry('a', 400), SplitEntry('b', 500)]),
          throwsA(isA<AppException>()));
    });
    test('exact rejects zero, custom allows zero', () {
      expect(
          () => computeSplit(
              totalMinor: 1000,
              method: SplitMethod.exact,
              entries: const [SplitEntry('a', 1000), SplitEntry('b', 0)]),
          throwsA(isA<AppException>()));
      final r = computeSplit(
          totalMinor: 1000,
          method: SplitMethod.custom,
          entries: const [SplitEntry('a', 1000), SplitEntry('b', 0)]);
      expect(r, {'a': 1000, 'b': 0});
    });
  });

  group('validation', () {
    test('zero / negative amount', () {
      for (final amt in [0, -5]) {
        expect(
            () => computeSplit(
                totalMinor: amt,
                method: SplitMethod.equal,
                entries: const [SplitEntry('a')]),
            throwsA(isA<AppException>()));
      }
    });
    test('duplicate and empty participants', () {
      expect(
          () => computeSplit(
              totalMinor: 100,
              method: SplitMethod.equal,
              entries: const [SplitEntry('a'), SplitEntry('a')]),
          throwsA(isA<AppException>()));
      expect(
          () => computeSplit(
              totalMinor: 100, method: SplitMethod.equal, entries: const []),
          throwsA(isA<AppException>()));
    });
  });

  group('money parsing', () {
    test('parse and format without floats', () {
      expect(parseToMinor('1,250.5', 'INR'), 125050);
      expect(parseToMinor('0.1', 'INR'), 10);
      expect(parseToMinor('10.123', 'INR'), isNull);
      expect(parseToMinor('abc', 'INR'), isNull);
      expect(parseToMinor('500', 'JPY'), 500);
      expect(parseToMinor('5.5', 'JPY'), isNull);
      expect(formatMinor(12345678, 'INR'), '₹1,23,456.78');
      expect(formatMinor(-5, 'USD'), '-\$0.05');
      expect(parsePercentToBps('33.33'), 3333);
    });
  });
}
