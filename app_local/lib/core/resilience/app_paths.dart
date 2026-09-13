// Fachada de rutas del sistema con selección condicional por plataforma.
//
// - Nativo (Windows / Android / desktop) -> `app_paths_io.dart`
//   Comportamiento idéntico al histórico.
// - Web -> `app_paths_web.dart`
//   Rutas lógicas sin acceso a `dart:io`, `LOCALAPPDATA`, `D:\` ni
//   `Platform.environment`.
export 'app_paths_io.dart' if (dart.library.js_interop) 'app_paths_web.dart';
