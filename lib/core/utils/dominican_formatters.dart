import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class DecimalNumberParser {
  static double? tryParse(String? value) {
    if (value == null) {
      return null;
    }

    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final normalized = trimmed
        .replaceAll(RegExp(r'[^0-9,.-]'), '')
        .replaceAll(',', '');

    if (normalized.isEmpty || normalized == '-' || normalized == '.') {
      return null;
    }

    return double.tryParse(normalized);
  }
}

class CurrencyTextFormatter extends TextInputFormatter {
  CurrencyTextFormatter({this.decimalDigits = 2})
    : _numberFormat = NumberFormat(
        decimalDigits <= 0 ? '#,##0' : '#,##0.${'0' * decimalDigits}',
        'en_US',
      );

  final int decimalDigits;
  final NumberFormat _numberFormat;

  String formatValue(num value) {
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

    final normalized = _normalizeDecimalInput(rawText);
    if (normalized == null) {
      return oldValue;
    }

    final parsed = double.tryParse(normalized);
    if (parsed == null) {
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

  String? _normalizeDecimalInput(String value) {
    final buffer = StringBuffer();
    bool hasDecimalSeparator = false;
    bool hasMinus = false;

    for (final rune in value.runes) {
      final character = String.fromCharCode(rune);
      if (RegExp(r'\d').hasMatch(character)) {
        buffer.write(character);
        continue;
      }

      if (character == '.' && !hasDecimalSeparator) {
        hasDecimalSeparator = true;
        buffer.write(character);
        continue;
      }

      if (character == '-' && !hasMinus && buffer.isEmpty) {
        hasMinus = true;
        buffer.write(character);
      }
    }

    final normalized = buffer.toString();
    if (normalized.isEmpty || normalized == '-' || normalized == '.') {
      return '0';
    }

    return normalized;
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

/// Formatter para nombre (solo letras y espacios)
class NameFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    // Permitir solo letras, acentos y espacios
    final allowedChars = RegExp(r"[a-záéíóúñ\s]", caseSensitive: false);
    
    String filtered = '';
    for (int i = 0; i < newValue.text.length; i++) {
      final char = newValue.text[i];
      if (allowedChars.hasMatch(char)) {
        filtered += char;
      }
    }

    if (filtered != newValue.text) {
      return TextEditingValue(
        text: filtered,
        selection: TextSelection.collapsed(offset: filtered.length),
      );
    }

    return newValue;
  }
}
