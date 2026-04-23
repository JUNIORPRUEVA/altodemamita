import 'dart:convert';
import 'dart:io';

String _normalizeBackendBaseUrl(String baseUrl) {
  final trimmed = baseUrl.trim();
  if (trimmed.isEmpty) {
    return '';
  }

  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.host.trim().isEmpty) {
    return trimmed.replaceAll(RegExp(r'/$'), '');
  }

  final pathSegments = uri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList();
  if (pathSegments.isEmpty || pathSegments.last.toLowerCase() != 'api') {
    pathSegments.add('api');
  }

  return uri
      .replace(pathSegments: pathSegments)
      .toString()
      .replaceAll(RegExp(r'/$'), '');
}

String _previewBody(String body) {
  final trimmed = body.trim();
  if (trimmed.isEmpty) return '<empty>';
  final normalizedWhitespace = trimmed.replaceAll(RegExp(r'\s+'), ' ');
  if (normalizedWhitespace.length <= 260) return normalizedWhitespace;
  return '${normalizedWhitespace.substring(0, 260)}...';
}

Future<void> _probe(HttpClient client, Uri uri) async {
  stdout.writeln('GET $uri');
  try {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close();

    final bytes = await response.fold<List<int>>(
      <int>[],
      (acc, chunk) => acc..addAll(chunk),
    );

    final body = utf8.decode(bytes, allowMalformed: true);
    stdout.writeln('  status: ${response.statusCode}');
    stdout.writeln('  content-type: ${response.headers.contentType}');
    stdout.writeln('  body: ${_previewBody(body)}');

    // Best-effort JSON check.
    if (body.trim().startsWith('{') || body.trim().startsWith('[')) {
      try {
        jsonDecode(body);
        stdout.writeln('  json: OK');
      } catch (_) {
        stdout.writeln('  json: INVALID');
      }
    } else {
      stdout.writeln('  json: (not-json)');
    }
  } catch (e) {
    stdout.writeln('  error: $e');
  }
}

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.first.trim().isEmpty) {
    stderr.writeln('Usage: dart run tool/probe_backend_url.dart <baseUrl>');
    stderr.writeln('Example: dart run tool/probe_backend_url.dart https://<your-domain>');
    stderr.writeln('Note: "/api" is appended automatically if missing.');
    exitCode = 64;
    return;
  }

  final normalizedBaseUrl = _normalizeBackendBaseUrl(args.first);
  if (normalizedBaseUrl.isEmpty) {
    stderr.writeln('Error: baseUrl is empty after normalization.');
    exitCode = 64;
    return;
  }

  final baseUri = Uri.parse(normalizedBaseUrl);
  final statusUri = baseUri.replace(
    pathSegments: [...baseUri.pathSegments.where((s) => s.isNotEmpty), 'system', 'status'],
  );
  final configUri = baseUri.replace(
    pathSegments: [...baseUri.pathSegments.where((s) => s.isNotEmpty), 'system', 'config'],
  );

  stdout.writeln('Base URL: $normalizedBaseUrl');

  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8);

  try {
    await _probe(client, statusUri);
    await _probe(client, configUri);
  } finally {
    client.close(force: true);
  }
}
