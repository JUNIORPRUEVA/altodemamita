import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/core/utils/dominican_formatters.dart';

void main() {
  test('formats while typing with RD accounting style', () {
    final formatter = RdCurrencyInputFormatter();

    var oldValue = const TextEditingValue(text: '');

    var nextValue = formatter.formatEditUpdate(
      oldValue,
      const TextEditingValue(
        text: '1000',
        selection: TextSelection.collapsed(offset: 4),
      ),
    );
    expect(nextValue.text, '1,000.00');

    oldValue = nextValue;
    nextValue = formatter.formatEditUpdate(
      oldValue,
      const TextEditingValue(
        text: '625000',
        selection: TextSelection.collapsed(offset: 6),
      ),
    );
    expect(nextValue.text, '625,000.00');

    oldValue = nextValue;
    nextValue = formatter.formatEditUpdate(
      oldValue,
      const TextEditingValue(
        text: '1,000.00',
        selection: TextSelection.collapsed(offset: 8),
      ),
    );
    expect(nextValue.text, '1,000.00');
  });
}
