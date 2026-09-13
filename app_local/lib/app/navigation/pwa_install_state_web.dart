import 'dart:js_interop';
import 'dart:js_interop_unsafe';

bool shouldShowPwaInstallButton() {
  try {
    if (_isStandaloneDisplayMode() || _isIosStandalone()) {
      return false;
    }
    return true;
  } catch (_) {
    return false;
  }
}

bool _isStandaloneDisplayMode() {
  final window = globalContext.getProperty<JSObject?>('window'.toJS);
  if (window == null || window.isUndefinedOrNull) {
    return false;
  }
  final query = window.callMethod<JSObject?>(
    'matchMedia'.toJS,
    '(display-mode: standalone)'.toJS,
  );
  if (query == null || query.isUndefinedOrNull) {
    return false;
  }
  final matches = query.getProperty<JSBoolean?>('matches'.toJS);
  return matches?.toDart ?? false;
}

bool _isIosStandalone() {
  final navigator = globalContext.getProperty<JSObject?>('navigator'.toJS);
  if (navigator == null || navigator.isUndefinedOrNull) {
    return false;
  }
  final standalone = navigator.getProperty<JSBoolean?>('standalone'.toJS);
  return standalone?.toDart ?? false;
}
