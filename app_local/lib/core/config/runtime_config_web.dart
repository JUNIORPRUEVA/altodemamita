import 'dart:js_interop';
import 'dart:js_interop_unsafe';

String runtimeConfigString(String key, String fallback) {
  final value = _readRuntimeValue(key);
  if (value == null || value.trim().isEmpty) {
    return fallback.trim();
  }
  return value.trim();
}

bool runtimeConfigBool(String key, bool fallback) {
  final value = _readRuntimeValue(key);
  if (value == null || value.trim().isEmpty) {
    return fallback;
  }
  switch (value.trim().toLowerCase()) {
    case '1':
    case 'true':
    case 'yes':
    case 'y':
    case 'on':
      return true;
    case '0':
    case 'false':
    case 'no':
    case 'n':
    case 'off':
      return false;
    default:
      return fallback;
  }
}

String? _readRuntimeValue(String key) {
  final config = globalContext.getProperty<JSObject?>(
    '__SISTEMA_SOLARES_CONFIG__'.toJS,
  );
  if (config == null || config.isUndefinedOrNull) {
    return null;
  }

  final value = config.getProperty<JSAny?>(key.toJS);
  if (value == null || value.isUndefinedOrNull) {
    return null;
  }
  if (value.isA<JSString>()) {
    return (value as JSString).toDart;
  }
  if (value.isA<JSBoolean>()) {
    return (value as JSBoolean).toDart.toString();
  }
  if (value.isA<JSNumber>()) {
    return (value as JSNumber).toDartDouble.toString();
  }
  return value.toString();
}
