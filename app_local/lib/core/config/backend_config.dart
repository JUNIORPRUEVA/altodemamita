import 'package:flutter/foundation.dart';

/// Configuración central del backend.
///
/// Regla profesional:
/// - Desarrollo: usar backend local.
/// - Producción: pasar URL real por --dart-define al compilar.
///
/// Desarrollo:
/// flutter run -d windows --dart-define=SYNC_API_BASE_URL=http://localhost:3000
///
/// Producción:
/// flutter build windows --dart-define=SYNC_API_BASE_URL=https://altodemanita-altodemamita-backent.onqyr1.easypanel.host
///
/// Importante:
/// No quemar aquí la URL de producción.
const String _defaultBackendBaseUrl = 'http://localhost:3000';

const String _backendBaseUrlFromEnv = String.fromEnvironment(
  'SYNC_API_BASE_URL',
  defaultValue: _defaultBackendBaseUrl,
);

/// Mantengo BASE_URL porque otros archivos probablemente ya lo usan.
///
/// Esta URL NO incluye /api de forma obligatoria.
/// Para construir endpoints seguros, usa:
/// - effectiveBackendBaseUrl
/// - backendEndpoint('/sync/upload')
const String BASE_URL = _backendBaseUrlFromEnv;

/// Mantener vacío para evitar que la app caiga accidentalmente
/// en un backend viejo o de producción.
const String LEGACY_BASE_URL = '';

const String companyTenantKey = 'alto-dona-mamita-sistema-solares';

const String serverConnectionErrorMessage = 'Servicio cloud no configurado';

/// Normaliza la URL base del backend.
///
/// Ejemplos:
/// http://localhost:3000
/// -> http://localhost:3000/api
///
/// http://localhost:3000/
/// -> http://localhost:3000/api
///
/// http://localhost:3000/api
/// -> http://localhost:3000/api
///
/// https://dominio.com
/// -> https://dominio.com/api
///
/// https://dominio.com/api/
/// -> https://dominio.com/api
String normalizeBackendBaseUrl(String baseUrl) {
  final trimmed = baseUrl.trim();

  if (trimmed.isEmpty) {
    return '';
  }

  final parsed = Uri.tryParse(trimmed);

  // Si no es una URL válida, devolvemos algo limpio sin slash final.
  // Esto evita que la app explote por una configuración mala.
  if (parsed == null || parsed.host.trim().isEmpty) {
    return trimmed.replaceAll(RegExp(r'/+$'), '');
  }

  final cleanSegments = parsed.pathSegments
      .where((segment) => segment.trim().isNotEmpty)
      .toList();

  final alreadyHasApi =
      cleanSegments.isNotEmpty && cleanSegments.last.toLowerCase() == 'api';

  if (!alreadyHasApi) {
    cleanSegments.add('api');
  }

  final normalized = parsed
      .replace(
        pathSegments: cleanSegments,
        query: parsed.query.isEmpty ? null : parsed.query,
        fragment: parsed.fragment.isEmpty ? null : parsed.fragment,
      )
      .toString()
      .replaceAll(RegExp(r'/+$'), '');

  return normalized;
}

/// URL final efectiva del backend, siempre normalizada con /api.
///
/// Ejemplo:
/// BASE_URL=http://localhost:3000
/// effectiveBackendBaseUrl=http://localhost:3000/api
String get effectiveBackendBaseUrl {
  final normalized = normalizeBackendBaseUrl(BASE_URL);

  if (kDebugMode) {
    debugPrint('[BackendConfig] SYNC_API_BASE_URL=$_backendBaseUrlFromEnv');
    debugPrint('[BackendConfig] effectiveBackendBaseUrl=$normalized');

    if (normalized.contains('easypanel.host')) {
      debugPrint(
        '[BackendConfig][WARNING] Estás en debug usando EasyPanel. '
        'Para desarrollo local ejecuta: '
        'flutter run -d windows --dart-define=SYNC_API_BASE_URL=http://localhost:3000',
      );
    }
  }

  return normalized;
}

/// Construye endpoints de forma segura.
///
/// Ejemplo:
/// backendEndpoint('/sync/upload')
/// -> http://localhost:3000/api/sync/upload
///
/// backendEndpoint('sync/upload')
/// -> http://localhost:3000/api/sync/upload
String backendEndpoint(String endpoint) {
  final base = effectiveBackendBaseUrl;

  if (base.isEmpty) {
    return '';
  }

  final cleanEndpoint = endpoint.trim().replaceFirst(RegExp(r'^/+'), '');

  if (cleanEndpoint.isEmpty) {
    return base;
  }

  return '$base/$cleanEndpoint';
}

/// Devuelve true si la URL actual parece ser localhost/desarrollo.
bool get isLocalBackend {
  final normalized = effectiveBackendBaseUrl.toLowerCase();

  return normalized.contains('localhost') ||
      normalized.contains('127.0.0.1') ||
      normalized.contains('10.0.2.2');
}

/// Devuelve true si la URL actual parece ser producción/EasyPanel.
bool get isProductionLikeBackend {
  final normalized = effectiveBackendBaseUrl.toLowerCase();

  return normalized.contains('easypanel.host') ||
      normalized.startsWith('https://');
}

/// Se deja en false para no amarrar la app a un host fijo.
/// La URL correcta debe venir por ambiente usando --dart-define.
bool isOfficialBackendHost(String hostOrUrl) {
  return false;
}