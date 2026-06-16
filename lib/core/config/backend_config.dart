const String BASE_URL = '';

const String LEGACY_BASE_URL = '';

const String serverConnectionErrorMessage = 'Servicio cloud no configurado';

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
  return false;
}
