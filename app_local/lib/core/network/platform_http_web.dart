// Implementación WEB de los tipos de red que el sistema usa desde `dart:io`.
//
// El navegador no puede usar `HttpClient`, `IOClient`, `InternetAddress.lookup`
// ni las excepciones de `dart:io`. Este archivo ofrece los MISMOS nombres y las
// MISMAS firmas que usa el código compartido, implementados sobre
// `package:http` (que en web usa `fetch`).
//
// Objetivo: que `auth_service.dart`, `sync_api_client.dart`,
// `cloud_api_client.dart`, etc. NO necesiten ramificaciones `kIsWeb`.
//
// NO cambia endpoints, serialización, cabeceras ni contratos de la API.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Códigos de estado HTTP equivalentes a `dart:io` `HttpStatus`.
class HttpStatus {
  const HttpStatus._();

  static const int ok = 200;
  static const int created = 201;
  static const int accepted = 202;
  static const int noContent = 204;
  static const int movedPermanently = 301;
  static const int found = 302;
  static const int notModified = 304;
  static const int temporaryRedirect = 307;
  static const int permanentRedirect = 308;
  static const int badRequest = 400;
  static const int unauthorized = 401;
  static const int forbidden = 403;
  static const int notFound = 404;
  static const int methodNotAllowed = 405;
  static const int conflict = 409;
  static const int gone = 410;
  static const int unprocessableEntity = 422;
  static const int tooManyRequests = 429;
  static const int internalServerError = 500;
  static const int badGateway = 502;
  static const int serviceUnavailable = 503;
  static const int gatewayTimeout = 504;
}

/// Equivalente mínimo de `dart:io` `ContentType`.
class ContentType {
  ContentType(
    this.primaryType,
    this.subType, {
    this.charset,
    Map<String, String>? parameters,
  }) : parameters = parameters ?? const {};

  final String primaryType;
  final String subType;
  final String? charset;
  final Map<String, String> parameters;

  static final ContentType json = ContentType(
    'application',
    'json',
    charset: 'utf-8',
  );

  static final ContentType text = ContentType('text', 'plain', charset: 'utf-8');

  static final ContentType binary = ContentType('application', 'octet-stream');

  String get mimeType => '$primaryType/$subType';

  @override
  String toString() {
    final buffer = StringBuffer(mimeType);
    if (charset != null) {
      buffer.write('; charset=$charset');
    }
    parameters.forEach((key, value) => buffer.write('; $key=$value'));
    return buffer.toString();
  }
}

/// Equivalente mínimo de `dart:io` `HttpHeaders`.
class HttpHeaders {
  static const String acceptHeader = 'accept';
  static const String authorizationHeader = 'authorization';
  static const String contentTypeHeader = 'content-type';
  static const String contentLengthHeader = 'content-length';
  static const String hostHeader = 'host';
  static const String userAgentHeader = 'user-agent';

  final Map<String, List<String>> _values = <String, List<String>>{};

  ContentType? contentType;

  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    final key = name.toLowerCase();
    if (key == contentTypeHeader) {
      _values[key] = <String>[value.toString()];
      return;
    }
    _values[key] = value is Iterable
        ? value.map((item) => item.toString()).toList(growable: false)
        : <String>[value.toString()];
  }

  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    final key = name.toLowerCase();
    _values.putIfAbsent(key, () => <String>[]).add(value.toString());
  }

  String? value(String name) {
    final values = _values[name.toLowerCase()];
    if (values == null || values.isEmpty) {
      return null;
    }
    return values.first;
  }

  List<String> operator [](String name) =>
      _values[name.toLowerCase()] ?? const <String>[];

  void remove(String name, Object value) {
    _values.remove(name.toLowerCase());
  }

  void removeAll(String name) {
    _values.remove(name.toLowerCase());
  }

  void clear() => _values.clear();

  void forEach(void Function(String name, List<String> values) action) =>
      _values.forEach(action);

  Map<String, String> toRequestHeaders() {
    final result = <String, String>{};
    _values.forEach((key, values) {
      if (values.isNotEmpty) {
        result[key] = values.join(', ');
      }
    });
    final explicit = contentType;
    if (explicit != null && !result.containsKey(contentTypeHeader)) {
      result[contentTypeHeader] = explicit.toString();
    }
    return result;
  }

  static HttpHeaders fromResponseHeaders(Map<String, String> headers) {
    final result = HttpHeaders();
    headers.forEach((key, value) => result.set(key, value));
    final contentTypeRaw = headers[contentTypeHeader];
    if (contentTypeRaw != null) {
      final parts = contentTypeRaw.split(';');
      final mime = parts.first.trim().split('/');
      if (mime.length == 2) {
        result.contentType = ContentType(
          mime[0].trim(),
          mime[1].trim(),
          charset: parts.length > 1 && parts[1].contains('charset')
              ? parts[1].split('=').last.trim()
              : null,
        );
      }
    }
    return result;
  }
}

/// Equivalente mínimo de `dart:io` `X509Certificate`.
class X509Certificate {
  X509Certificate({this.subject = '', this.issuer = '', this.endValidity});

  final String subject;
  final String issuer;
  final DateTime? endValidity;
}

/// Equivalente de `dart:io` `HttpException`.
class HttpException extends IOException {
  HttpException(super.message, {this.uri});

  final Uri? uri;

  @override
  String toString() =>
      'HttpException: $message${uri == null ? '' : ', uri = $uri'}';
}

/// Equivalente de `dart:io` `IOException`.
class IOException implements Exception {
  IOException([this.message = '']);

  final String message;

  @override
  String toString() => 'IOException: $message';
}

/// Equivalente de `dart:io` `SocketException`.
class SocketException extends IOException {
  SocketException(super.message, {this.address, this.port});

  final String? address;
  final int? port;

  @override
  String toString() =>
      'SocketException: $message${address == null ? '' : ', address = $address'}';
}

/// Equivalente de `dart:io` `FileSystemException`.
///
/// En el navegador no existe sistema de archivos, pero el código compartido de
/// mensajes de error comprueba este tipo, por lo que se conserva el nombre.
class FileSystemException extends IOException {
  FileSystemException(super.message, {this.path, this.osError});

  final String? path;
  final String? osError;
}

@JS('navigator')
external JSObject? get _navigatorObject;

extension type _BrowserNavigator(JSObject _) implements JSObject {
  external bool get onLine;
}

/// Equivalente de `dart:io` `InternetAddress`.
///
/// El navegador no permite resolver DNS. `lookup` se usa en el sistema
/// únicamente como sonda de conectividad, por lo que aquí se responde con el
/// estado real que expone el navegador (`navigator.onLine`).
class InternetAddress {
  InternetAddress(this.address, {Uint8List? rawAddress})
    : rawAddress = rawAddress ?? Uint8List.fromList(const <int>[1]);

  final String address;
  final Uint8List rawAddress;

  static bool get browserReportsOnline {
    try {
      final navigator = _navigatorObject;
      if (navigator == null) {
        return true;
      }
      return _BrowserNavigator(navigator).onLine;
    } catch (_) {
      // Si el navegador no expone el estado, se asume conectado y se deja que
      // la petición real determine el resultado.
      return true;
    }
  }

  static Future<List<InternetAddress>> lookup(
    Object host, {
    InternetAddressType type = InternetAddressType.any,
  }) async {
    if (!browserReportsOnline) {
      throw SocketException('No hay conexion a Internet', address: '$host');
    }
    return <InternetAddress>[InternetAddress('$host')];
  }
}

/// Equivalente de `dart:io` `InternetAddressType`.
enum InternetAddressType { any, ipv4, ipv6 }

/// Equivalente de `dart:io` `HttpClientRequest`.
class HttpClientRequest {
  HttpClientRequest._(this.uri, this.method, HttpClient client)
    : headers = HttpHeaders(),
      _client = client;

  final Uri uri;
  final String method;
  final HttpClient _client;
  final HttpHeaders headers;

  final BytesBuilder _body = BytesBuilder(copy: false);

  bool followRedirects = true;
  int maxRedirects = 5;
  bool persistentConnection = true;
  int contentLength = -1;

  void write(Object? object) {
    _body.add(utf8.encode('${object ?? ''}'));
  }

  void add(List<int> data) {
    _body.add(data);
  }

  Future<HttpClientResponse> close() async {
    final body = _body.takeBytes();
    final request = http.Request(method, uri);
    request.followRedirects = followRedirects;
    request.maxRedirects = maxRedirects;
    request.headers.addAll(headers.toRequestHeaders());
    if (body.isNotEmpty) {
      request.bodyBytes = body;
    }

    final timeout = _client.connectionTimeout;
    try {
      final streamed = timeout == null
          ? await _client.inner.send(request)
          : await _client.inner.send(request).timeout(timeout);
      final bytes = await streamed.stream.toBytes();
      return HttpClientResponse(
        statusCode: streamed.statusCode,
        headers: HttpHeaders.fromResponseHeaders(streamed.headers),
        bytes: bytes,
      );
    } on TimeoutException {
      throw SocketException('Tiempo de espera agotado', address: uri.host);
    } on HttpException {
      rethrow;
    } catch (error) {
      // En el navegador un fallo de red aparece como ClientException o como
      // error de tipo no disponible en dart:io. Se normaliza a SocketException
      // para que el manejo de errores compartido siga funcionando igual.
      throw SocketException('$error', address: uri.host);
    }
  }
}

/// Equivalente de `dart:io` `HttpClientResponse`.
class HttpClientResponse extends Stream<List<int>> {
  HttpClientResponse({
    required this.statusCode,
    required this.headers,
    required Uint8List bytes,
  }) : _bytes = bytes;

  final int statusCode;
  final HttpHeaders headers;
  final Uint8List _bytes;

  bool get isRedirect => statusCode >= 300 && statusCode < 400;
  int get contentLength => _bytes.length;
  List<Object> get redirects => const <Object>[];

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(_bytes).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

/// Equivalente de `dart:io` `HttpClient` sobre `package:http`.
///
/// Mantiene la misma API usada por el sistema (`getUrl`, `postUrl`, `putUrl`,
/// `connectionTimeout`, `idleTimeout`, `badCertificateCallback`, `close`).
class HttpClient {
  HttpClient({http.Client? inner}) : inner = inner ?? http.Client();

  final http.Client inner;

  Duration? connectionTimeout;
  Duration? idleTimeout;
  bool autoUncompress = true;
  String? userAgent;

  /// En el navegador la validación TLS la realiza el propio navegador, por lo
  /// que este callback nunca se invoca. Se conserva para no cambiar el código
  /// compartido de configuración.
  bool Function(X509Certificate certificate, String host, int port)?
  badCertificateCallback;

  /// El navegador no soporta proxy a nivel de aplicación.
  String Function(Uri url)? findProxy;

  Future<HttpClientRequest> getUrl(Uri url) async =>
      HttpClientRequest._(url, 'GET', this);

  Future<HttpClientRequest> postUrl(Uri url) async =>
      HttpClientRequest._(url, 'POST', this);

  Future<HttpClientRequest> putUrl(Uri url) async =>
      HttpClientRequest._(url, 'PUT', this);

  Future<HttpClientRequest> deleteUrl(Uri url) async =>
      HttpClientRequest._(url, 'DELETE', this);

  Future<HttpClientRequest> patchUrl(Uri url) async =>
      HttpClientRequest._(url, 'PATCH', this);

  void close({bool force = false}) {
    inner.close();
  }
}
