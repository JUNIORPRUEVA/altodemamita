import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../config/backend_config.dart';

HttpClient createBackendHttpClient({
  Duration connectionTimeout = const Duration(seconds: 10),
  Duration idleTimeout = const Duration(seconds: 15),
}) {
  final client = HttpClient();
  configureBackendHttpClient(
    client,
    connectionTimeout: connectionTimeout,
    idleTimeout: idleTimeout,
  );
  return client;
}

HttpClient configureBackendHttpClient(
  HttpClient client, {
  Duration connectionTimeout = const Duration(seconds: 10),
  Duration idleTimeout = const Duration(seconds: 15),
}) {
  client.connectionTimeout = connectionTimeout;
  client.idleTimeout = idleTimeout;
  client.badCertificateCallback = (certificate, host, port) {
    final accepted = isOfficialBackendHost(host);
    if (accepted) {
      // ignore: avoid_print
      print(
        '[HTTP] Certificado TLS no confiable aceptado solo para host oficial: '
        '$host:$port',
      );
    }
    return accepted;
  };
  return client;
}

http.Client createBackendPackageHttpClient({
  Duration connectionTimeout = const Duration(seconds: 10),
  Duration idleTimeout = const Duration(seconds: 15),
}) {
  return IOClient(
    createBackendHttpClient(
      connectionTimeout: connectionTimeout,
      idleTimeout: idleTimeout,
    ),
  );
}
