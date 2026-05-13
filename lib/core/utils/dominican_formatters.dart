import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

final NumberFormat _rdCurrencyFormat = NumberFormat('#,##0.00', 'en_US');

String formatRdCurrency(num value) {
  final safeValue = value.toDouble();
  if (!safeValue.isFinite) {
    return _rdCurrencyFormat.format(0);
  }
  return _rdCurrencyFormat.format(safeValue);
}

double parseRdCurrency(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || !RegExp(r'\d').hasMatch(trimmed)) {
    return 0;
  }

  final sanitized = trimmed.replaceAll(RegExp(r'[^0-9,.-]'), '');
  if (sanitized.isEmpty || sanitized == '-' || sanitized == '.' || sanitized == ',') {
    return 0;
  }

  String normalized = sanitized;
  final commaCount = ','.allMatches(normalized).length;
  final dotCount = '.'.allMatches(normalized).length;

  if (commaCount > 0 && dotCount == 0) {
    final lastComma = normalized.lastIndexOf(',');
    final decimalDigits = normalized.length - lastComma - 1;
    if (decimalDigits > 0 && decimalDigits <= 2) {
      normalized = normalized.replaceFirst(',', '.');
      normalized = normalized.replaceAll(',', '');
    } else {
      normalized = normalized.replaceAll(',', '');
    }
  } else {
    normalized = normalized.replaceAll(',', '');
  }

  if ('.'.allMatches(normalized).length > 1) {
    final lastDot = normalized.lastIndexOf('.');
    final integerPart = normalized.substring(0, lastDot).replaceAll('.', '');
    final decimalPart = normalized.substring(lastDot + 1);
    normalized = '$integerPart.$decimalPart';
  }

  return double.tryParse(normalized) ?? 0;
}

class DecimalNumberParser {
  static double? tryParse(String? value) {
    if (value == null) {
      return null;
    }

    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    if (!RegExp(r'\d').hasMatch(trimmed)) {
      return null;
    }

    return parseRdCurrency(trimmed);
  }
}

class RdCurrencyInputFormatter extends TextInputFormatter {
  RdCurrencyInputFormatter({this.decimalDigits = 2})
    : _numberFormat = NumberFormat(
        decimalDigits <= 0 ? '#,##0' : '#,##0.${'0' * decimalDigits}',
        'en_US',
      );

  final int decimalDigits;
  final NumberFormat _numberFormat;

  String formatValue(num value) {
    if (decimalDigits == 2) {
      return formatRdCurrency(value);
    }
    return _numberFormat.format(value);
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final rawText = newValue.text;
    if (rawText.trim().isEmpty) {
      return const TextEditingValue(text: '');
    }

    if (!RegExp(r'\d').hasMatch(rawText)) {
      return oldValue;
    }

    final parsed = parseRdCurrency(rawText);
    if (!parsed.isFinite) {
      return oldValue;
    }

    final formatted = _numberFormat.format(parsed);
    final targetCursor = _mapCursorPosition(
      sourceText: rawText,
      formattedText: formatted,
      sourceOffset: newValue.selection.baseOffset,
    );

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: targetCursor),
    );
  }

  int _mapCursorPosition({
    required String sourceText,
    required String formattedText,
    required int sourceOffset,
  }) {
    final clampedOffset = sourceOffset.clamp(0, sourceText.length);
    final sourceMeaningful = _countMeaningfulCharacters(
      sourceText.substring(0, clampedOffset),
    );

    if (sourceMeaningful <= 0) {
      return 0;
    }

    int seenMeaningful = 0;
    for (int index = 0; index < formattedText.length; index++) {
      if (_isMeaningfulCharacter(formattedText[index])) {
        seenMeaningful++;
        if (seenMeaningful >= sourceMeaningful) {
          return index + 1;
        }
      }
    }

    return formattedText.length;
  }

  int _countMeaningfulCharacters(String text) {
    return text.split('').where(_isMeaningfulCharacter).length;
  }

  bool _isMeaningfulCharacter(String character) {
    return RegExp(r'[0-9.]').hasMatch(character);
  }
}

class CurrencyTextFormatter extends RdCurrencyInputFormatter {
  CurrencyTextFormatter({int decimalDigits = 2})
    : super(decimalDigits: decimalDigits);
}

/// Formatter para cédula dominicana (XXX-XXXXXXX-X)
class DominicanIdFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final cleaned = newValue.text.replaceAll(RegExp(r'[^\d]'), '');

    if (cleaned.isEmpty) {
      return const TextEditingValue(text: '');
    }

    if (cleaned.length > 11) {
      return oldValue; // Limitar a 11 dígitos
    }

    // Aplicar formato automático: XXX-XXXXXXX-X
    String formatted = '';
    for (int i = 0; i < cleaned.length; i++) {
      if (i == 3 || i == 10) {
        formatted += '-';
      }
      formatted += cleaned[i];
    }

    final digitsBeforeCursor = _countDigitsBeforeCursor(
      newValue.text,
      newValue.selection.baseOffset,
    );
    final cursorOffset = _offsetForDigits(formatted, digitsBeforeCursor);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: cursorOffset),
    );
  }

  int _countDigitsBeforeCursor(String text, int offset) {
    final clampedOffset = offset.clamp(0, text.length);
    return text
        .substring(0, clampedOffset)
        .replaceAll(RegExp(r'[^\d]'), '')
        .length;
  }

  int _offsetForDigits(String formatted, int digitsBeforeCursor) {
    if (digitsBeforeCursor <= 0) {
      return 0;
    }

    int digitCount = 0;
    for (int index = 0; index < formatted.length; index++) {
      if (RegExp(r'\d').hasMatch(formatted[index])) {
        digitCount++;
        if (digitCount >= digitsBeforeCursor) {
          return index + 1;
        }
      }
    }

    return formatted.length;
  }
}

/// Formatter para teléfono dominicano (XXX) XXX-XXXX
class DominicanPhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final cleaned = newValue.text.replaceAll(RegExp(r'[^\d]'), '');

    if (cleaned.isEmpty) {
      return newValue;
    }

    if (cleaned.length > 10) {
      return oldValue; // Limitar a 10 dígitos
    }

    // Aplicar formato: (XXX) XXX-XXXX
    String formatted = '';
    
    if (cleaned.length <= 3) {
      formatted = '(${cleaned}';
    } else if (cleaned.length <= 6) {
      formatted = '(${cleaned.substring(0, 3)}) ${cleaned.substring(3)}';
    } else {
      formatted = '(${cleaned.substring(0, 3)}) ${cleaned.substring(3, 6)}-${cleaned.substring(6)}';
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

