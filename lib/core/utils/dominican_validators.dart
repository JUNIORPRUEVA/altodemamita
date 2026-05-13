/// Validadores y formateadores para datos dominicanos
class DominicanValidators {
  // Expresión regular para nombres válidos (solo letras y espacios)
  static final RegExp _nameRegex = RegExp(
    r"^[a-záéíóúñ\s]{3,}$",
    caseSensitive: false,
  );

  // Códigos de teléfono para República Dominicana
  static const List<String> _dominicanaPhonePrefixes = ['809', '829', '849'];

  // Validar y formatear nombre
  static String? validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'El nombre es obligatorio.';
    }
    final trimmed = value.trim();
    if (trimmed.length < 3) {
      return 'El nombre debe tener al menos 3 caracteres.';
    }
    if (!_nameRegex.hasMatch(trimmed)) {
      return 'El nombre solo debe contener letras y espacios.';
    }
    return null;
  }

  /// Validar formato de cédula dominicana: XXX-XXXXXXX-X o XXXXXXXXXXX
  /// Retorna mensaje de error o null si es válido
  static String? validateDominicanId(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'La cédula es obligatoria.';
    }

    if (RegExp(r'[^\d\s-]').hasMatch(value)) {
      return 'La cédula solo debe contener números.';
    }

    final cleaned = _normalizeDominicanIdDigits(value);

    if (cleaned == null) {
      return 'La cédula solo debe contener números.';
    }

    if (cleaned.length != 11) {
      return 'La cédula debe tener 11 dígitos.';
    }

    if (!_isValidDominicanIdChecksum(cleaned)) {
      return 'La cédula no es válida.';
    }

    return null;
  }

  /// Validar cédula SOLO por cantidad de dígitos (11).
  ///
  /// Útil para flujos donde no importa si la cédula es “real”,
  /// pero sí que tenga un formato mínimo consistente.
  static String? validateDominicanIdLengthOnly(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'La cédula es obligatoria.';
    }

    if (RegExp(r'[^\d\s-]').hasMatch(value)) {
      return 'La cédula solo debe contener números.';
    }

    final cleaned = _normalizeDominicanIdDigits(value);
    if (cleaned == null) {
      return 'La cédula solo debe contener números.';
    }

    if (cleaned.length != 11) {
      return 'La cédula debe tener 11 dígitos.';
    }

    return null;
  }

  static String? validateFlexibleDocumentId(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'La cédula es obligatoria.';
    }

    if (_containsLetters(value)) {
      return 'Digite solo números. Puede ser cédula, pasaporte u otro documento numérico.';
    }

    final digits = digitsOnly(value);
    if (digits.isEmpty) {
      return 'Digite solo números. Puede ser cédula, pasaporte u otro documento numérico.';
    }

    return null;
  }

  /// Formatear cédula al formato dominicano: XXX-XXXXXXX-X
  static String formatDominicanId(String value) {
    final cleaned = _normalizeDominicanIdDigits(value);
    if (cleaned == null || cleaned.length != 11) {
      return value.trim();
    }
    return '${cleaned.substring(0, 3)}-${cleaned.substring(3, 10)}-${cleaned.substring(10)}';
  }

  static String? _normalizeDominicanIdDigits(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    if (RegExp(r'[^\d\s-]').hasMatch(trimmed)) {
      return null;
    }

    return trimmed.replaceAll(RegExp(r'[^\d]'), '');
  }

  /// Verificar checksum de cédula dominicana
  static bool _isValidDominicanIdChecksum(String id) {
    if (id.length != 11) return false;

    const List<int> weights = [1, 2, 1, 2, 1, 2, 1, 2, 1, 2];
    int sum = 0;

    for (int i = 0; i < 10; i++) {
      int digit = int.parse(id[i]);
      int product = digit * weights[i];

      if (product >= 10) {
        product = (product ~/ 10) + (product % 10);
      }

      sum += product;
    }

    final verifier = (10 - (sum % 10)) % 10;
    return verifier == int.parse(id[10]);
  }

  /// Validar teléfono dominicano
  /// Retorna mensaje de error o null si es válido
  static String? validateDominicanPhone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null; // El teléfono es opcional
    }

    final cleaned = _normalizeDominicanPhoneDigits(value);

    if (cleaned == null) {
      return 'El teléfono debe contener solo números.';
    }

    if (cleaned.length != 10) {
      return 'El teléfono debe tener 10 dígitos.';
    }

    final prefix = cleaned.substring(0, 3);
    if (!_dominicanaPhonePrefixes.contains(prefix)) {
      return 'El teléfono debe iniciar con 809, 829 o 849.';
    }

    return null;
  }

  static String? validateFlexiblePhone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    if (_containsLetters(value)) {
      return 'Digite solo números. Puede ser un número local o extranjero.';
    }

    final digits = digitsOnly(value);
    if (digits.isEmpty) {
      return 'Digite solo números. Puede ser un número local o extranjero.';
    }

    if (digits.length < 10) {
      return 'El teléfono debe tener al menos 10 dígitos.';
    }

    return null;
  }

  /// Formatear teléfono dominicano al formato: (XXX) XXX-XXXX
  static String formatDominicanPhone(String value) {
    final cleaned = _normalizeDominicanPhoneDigits(value);
    if (cleaned == null) {
      return value.trim();
    }

    // Tomar últimos 10 dígitos o todos los dígitos
    final phoneNumber = cleaned.length >= 10
        ? cleaned.substring(cleaned.length - 10)
        : cleaned;

    if (phoneNumber.length != 10) {
      return cleaned;
    }

    // Formato: (XXX) XXX-XXXX
    return '(${phoneNumber.substring(0, 3)}) ${phoneNumber.substring(3, 6)}-${phoneNumber.substring(6)}';
  }

  /// Limpiar número telefónico removiendo caracteres especiales
  static String _cleanPhoneNumber(String value) {
    return value.replaceAll(RegExp(r'\D'), '').trim();
  }

  static String digitsOnly(String value) {
    return value.replaceAll(RegExp(r'\D'), '').trim();
  }

  static bool _containsLetters(String value) {
    return RegExp(r'[A-Za-zÁÉÍÓÚÜÑáéíóúüñ]').hasMatch(value);
  }

  static String? _normalizeDominicanPhoneDigits(String value) {
    final cleaned = _cleanPhoneNumber(value);

    if (cleaned.isEmpty) {
      return '';
    }

    if (!RegExp(r'^\d+$').hasMatch(cleaned)) {
      return null;
    }

    if (cleaned.length == 11 && cleaned.startsWith('1')) {
      return cleaned.substring(1);
    }

    return cleaned;
  }

  /// Validar y formatear dirección (básico)
  static String? validateAddress(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null; // La dirección es opcional
    }

    final trimmed = value.trim();

    if (trimmed.length < 5) {
      return 'La dirección debe tener al menos 5 caracteres.';
    }

    if (trimmed.length > 200) {
      return 'La dirección no puede exceder 200 caracteres.';
    }

    return null;
  }

  /// Normalizar dirección (capitalize first letter of each word)
  static String normalizeAddress(String value) {
    final trimmed = value.trim();
    return trimmed
        .split(' ')
        .map(
          (word) => word.isEmpty
              ? ''
              : word[0].toUpperCase() + word.substring(1).toLowerCase(),
        )
        .join(' ');
  }
}
