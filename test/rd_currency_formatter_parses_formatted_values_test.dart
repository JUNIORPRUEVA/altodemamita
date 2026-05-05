import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/core/utils/dominican_formatters.dart';

void main() {
  test('parses formatted and raw values safely', () {
    expect(parseRdCurrency('1,000.00'), 1000.0);
    expect(parseRdCurrency('625,000.00'), 625000.0);
    expect(parseRdCurrency('625000'), 625000.0);
    expect(parseRdCurrency('RD\$ 15,000.00'), 15000.0);
    expect(parseRdCurrency(''), 0.0);
  });

  test('formats values with fixed decimals and separators', () {
    expect(formatRdCurrency(1000), '1,000.00');
    expect(formatRdCurrency(15000), '15,000.00');
    expect(formatRdCurrency(625000), '625,000.00');
  });
}
