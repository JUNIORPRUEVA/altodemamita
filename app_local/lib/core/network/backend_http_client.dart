// Fachada con selección condicional por plataforma.
//
// - Nativo: `backend_http_client_io.dart` (comportamiento histórico exacto).
// - Web: `backend_http_client_web.dart` (cliente del navegador).
//
// Los consumidores siguen importando `backend_http_client.dart`.
export 'backend_http_client_io.dart'
    if (dart.library.js_interop) 'backend_http_client_web.dart';
