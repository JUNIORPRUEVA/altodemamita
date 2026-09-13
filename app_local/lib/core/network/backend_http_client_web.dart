// Implementación WEB de la configuración del cliente HTTP del backend.
//
// El navegador no permite `IOClient`, ni `badCertificateCallback`, ni timeouts
// de conexión a nivel de socket. La validación TLS la realiza el navegador y
// los timeouts se aplican a nivel de petición en el código compartido.
//
// No se cambian endpoints, cabeceras, serialización ni contratos.
import 'package:http/http.dart' as http;

// Se importa la implementación web DIRECTAMENTE: este archivo sólo se compila
// para web, y desde el análisis estático la fachada resuelve a `dart:io`.
// ignore: implementation_imports
import 'platform_http_web.dart';

HttpClient createBackendHttpClient({
  Duration connectionTimeout = const Duration(seconds: 10),
  Duration idleTimeout = const Duration(seconds: 15),
}) {
  final client = HttpClient(inner: http.Client());
  return configureBackendHttpClient(
    client,
    connectionTimeout: connectionTimeout,
    idleTimeout: idleTimeout,
  );
}

HttpClient configureBackendHttpClient(
  HttpClient client, {
  Duration connectionTimeout = const Duration(seconds: 10),
  Duration idleTimeout = const Duration(seconds: 15),
}) {
  client.connectionTimeout = connectionTimeout;
  client.idleTimeout = idleTimeout;
  // El navegador decide la confianza del certificado; este callback queda sin
  // uso para no alterar el código compartido de configuración.
  client.badCertificateCallback = (certificate, host, port) => false;
  return client;
}

/// En web el cliente de `package:http` ya usa `fetch` del navegador.
http.Client createBackendPackageHttpClient({
  Duration connectionTimeout = const Duration(seconds: 10),
  Duration idleTimeout = const Duration(seconds: 15),
}) {
  return http.Client();
}
