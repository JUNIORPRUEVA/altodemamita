// Fachada de red con selección condicional por plataforma.
//
// - Nativo: re-exporta literalmente los tipos de `dart:io`.
// - Web: shims equivalentes sobre `package:http` / `fetch`.
//
// Todos los consumidores importan este archivo en lugar de `dart:io`, de modo
// que NO necesitan ramificaciones `kIsWeb` y no hay riesgo de cambiar el
// comportamiento en Windows.
export 'platform_http_io.dart'
    if (dart.library.js_interop) 'platform_http_web.dart';
