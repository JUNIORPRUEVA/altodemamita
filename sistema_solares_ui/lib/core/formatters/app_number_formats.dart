import 'package:intl/intl.dart';

class AppNumberFormats {
  AppNumberFormats._();

  static final NumberFormat accounting = NumberFormat('#,##0.00', 'en_US');

  static final NumberFormat currency = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'RD\$ ',
    decimalDigits: 2,
    customPattern: '\u00A4#,##0.00',
  );

  static String money(num? value, {bool withSymbol = true}) {
    final safeValue = value ?? 0;
    return withSymbol
        ? currency.format(safeValue).trimRight()
        : accounting.format(safeValue);
  }
}
