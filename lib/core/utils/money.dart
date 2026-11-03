/// All money is an [int] in minor units (paise, cents). Never double.
class Currency {
  final String code;
  final int exponent;
  final String symbol;
  const Currency(this.code, this.exponent, this.symbol);
}

const Map<String, Currency> kCurrencies = {
  'INR': Currency('INR', 2, '₹'),
  'USD': Currency('USD', 2, '\$'),
  'EUR': Currency('EUR', 2, '€'),
  'GBP': Currency('GBP', 2, '£'),
  'JPY': Currency('JPY', 0, '¥'),
};

Currency currencyOf(String code) =>
    kCurrencies[code] ?? Currency(code, 2, '$code ');

int _pow10(int n) {
  var r = 1;
  for (var i = 0; i < n; i++) {
    r *= 10;
  }
  return r;
}

/// 150000 INR -> "₹1,500.00"
String formatMinor(int minor, String code) {
  final c = currencyOf(code);
  final neg = minor < 0;
  final abs = minor.abs();
  final div = _pow10(c.exponent);
  final whole = (abs ~/ div).toString();
  final grouped = _group(whole, code == 'INR');
  final frac = c.exponent == 0
      ? ''
      : '.${(abs % div).toString().padLeft(c.exponent, '0')}';
  return '${neg ? '-' : ''}${c.symbol}$grouped$frac';
}

String _group(String digits, bool indian) {
  if (digits.length <= 3) return digits;
  final last3 = digits.substring(digits.length - 3);
  var rest = digits.substring(0, digits.length - 3);
  final size = indian ? 2 : 3;
  final parts = <String>[];
  while (rest.length > size) {
    parts.insert(0, rest.substring(rest.length - size));
    rest = rest.substring(0, rest.length - size);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '${parts.join(',')},$last3';
}

/// Parses user text such as "1,250.5" into minor units without floating point.
/// Returns null when invalid or when it has more decimals than the currency allows.
int? parseToMinor(String text, String code) {
  final c = currencyOf(code);
  final t = text.trim().replaceAll(',', '');
  final m = RegExp(r'^(\d+)(?:\.(\d*))?$').firstMatch(t);
  if (m == null) return null;
  final whole = int.tryParse(m.group(1)!);
  if (whole == null) return null;
  final fracStr = m.group(2) ?? '';
  if (fracStr.length > c.exponent) return null;
  final frac =
      fracStr.isEmpty ? 0 : int.parse(fracStr.padRight(c.exponent, '0'));
  return whole * _pow10(c.exponent) + frac;
}

/// "33.33" -> 3333 basis points (100% = 10000).
int? parsePercentToBps(String text) {
  final m = RegExp(r'^(\d+)(?:\.(\d{0,2}))?$').firstMatch(text.trim());
  if (m == null) return null;
  final whole = int.parse(m.group(1)!);
  final f = (m.group(2) ?? '').padRight(2, '0');
  return whole * 100 + int.parse(f.isEmpty ? '0' : f);
}
