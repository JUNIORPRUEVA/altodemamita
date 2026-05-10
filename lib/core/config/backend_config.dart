const String BASE_URL =
  'https://altodemanita-altodemamita-backent.onqyr1.easypanel.host/';

const String LEGACY_BASE_URL =
  'https://altodemanita-altodemamita-backend.onqyr1.easypanel.host/';

const String serverConnectionErrorMessage = 'Error de conexion con el servidor';

String normalizeBackendBaseUrl(String baseUrl) {
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

bool isOfficialBackendHost(String hostOrUrl) {
  final value = hostOrUrl.trim().toLowerCase();
  if (value.isEmpty) {
    return false;
  }

  final parsed = Uri.tryParse(value);
  final host = parsed?.host.trim().toLowerCase().isNotEmpty == true
      ? parsed!.host.trim().toLowerCase()
      : value
            .replaceFirst(RegExp(r'^https?://'), '')
            .split('/')
            .first
            .split(':')
            .first
            .trim()
            .toLowerCase();

  return host == 'altodemanita-altodemamita-backend.onqyr1.easypanel.host' ||
      host == 'altodemanita-altodemamita-backent.onqyr1.easypanel.host';
}
