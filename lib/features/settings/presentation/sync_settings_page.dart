import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/system/system_config_service.dart';
import '../../../features/auth/presentation/auth_provider.dart';
import '../../../services/sync/sync_config_repository.dart';
import '../../../shared/widgets/base_layout.dart';

class SyncSettingsPage extends StatefulWidget {
  const SyncSettingsPage({super.key});

  @override
  State<SyncSettingsPage> createState() => _SyncSettingsPageState();
}

class _SyncSettingsPageState extends State<SyncSettingsPage> {
  late final TextEditingController _baseUrlController;
  final HttpClient _httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..idleTimeout = const Duration(seconds: 10);
  final SyncConfigRepository _syncConfigRepository = SyncConfigRepository();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isProbing = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _httpClient.close(force: true);
    _baseUrlController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    try {
      final authService = context.read<AuthProvider>().authService;
      final current = await authService.loadBackendBaseUrl();
      _baseUrlController.text = current;
    } finally {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  String _normalizeDisplayUrl(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.replaceAll(RegExp(r'/$'), '');
  }

  bool _isLocalhostHost(String host) {
    final lower = host.trim().toLowerCase();
    return lower == 'localhost' ||
        lower == '127.0.0.1' ||
        lower == '0.0.0.0' ||
        lower == '::1';
  }

  bool _isLocalhostUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null) return false;
    return _isLocalhostHost(uri.host);
  }

  Future<void> _save() async {
    final raw = _baseUrlController.text;
    final normalized = _normalizeDisplayUrl(raw);

    if (normalized.isEmpty) {
      setState(() {
        _statusMessage = 'La URL del backend no puede estar vacía.';
      });
      return;
    }

    // Avoid shipping a desktop build configured to localhost.
    if (!kDebugMode && _isLocalhostUrl(normalized)) {
      setState(() {
        _statusMessage =
            'No se permite usar localhost/127.0.0.1 como backend en producción.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _statusMessage = null;
    });

    try {
      final authService = context.read<AuthProvider>().authService;
      await authService.saveBackendBaseUrl(normalized);
      await SystemConfigService.instance.refresh();

      if (!mounted) return;
      setState(() {
        _statusMessage = 'Guardado: ${_baseUrlController.text.trim()}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'No se pudo guardar la URL: $error';
      });
    } finally {
      if (!mounted) return;
      setState(() => _isSaving = false);
    }
  }

  Future<void> _probe() async {
    final raw = _baseUrlController.text;
    final normalized = _normalizeDisplayUrl(raw);

    if (normalized.isEmpty) {
      setState(() => _statusMessage = 'Configura una URL antes de probar.');
      return;
    }

    setState(() {
      _isProbing = true;
      _statusMessage = null;
    });

    try {
      // Build two base URLs:
      // - rootBase: used for GET /health (no /api)
      // - apiBase: used for API calls (ensures /api suffix)
      final uri = Uri.parse(normalized);
      final inputSegments = uri.pathSegments
          .where((segment) => segment.trim().isNotEmpty)
          .toList();
      final inputHasApi =
          inputSegments.isNotEmpty && inputSegments.last.toLowerCase() == 'api';

      final rootSegments = inputHasApi
          ? inputSegments.sublist(0, inputSegments.length - 1)
          : inputSegments;
      final rootBase = uri.replace(pathSegments: rootSegments);

      final apiSegments = inputHasApi ? inputSegments : [...inputSegments, 'api'];
      final apiBase = uri.replace(pathSegments: apiSegments);

      if (!kDebugMode && _isLocalhostHost(uri.host)) {
        setState(() {
          _statusMessage =
              'No se permite probar localhost/127.0.0.1 como backend en producción.';
        });
        return;
      }

      final healthUri = rootBase.replace(
        pathSegments: [
          ...rootBase.pathSegments.where((s) => s.isNotEmpty),
          'health',
        ],
      );

      final healthRequest = await _httpClient.getUrl(healthUri);
      healthRequest.headers.set(
        HttpHeaders.acceptHeader,
        ContentType.json.mimeType,
      );
      final healthResponse = await healthRequest.close();
      final healthBody = await utf8.decoder.bind(healthResponse).join();
      final healthLooksLikeJson =
          healthBody.trimLeft().startsWith('{') ||
          healthBody.trimLeft().startsWith('[');

      final healthOk =
          healthResponse.statusCode == HttpStatus.ok && healthLooksLikeJson;

      final statusUri = apiBase.replace(
        pathSegments: [
          ...apiBase.pathSegments.where((s) => s.isNotEmpty),
          'system',
          'status',
        ],
      );

      final statusRequest = await _httpClient.getUrl(statusUri);
      statusRequest.headers.set(
        HttpHeaders.acceptHeader,
        ContentType.json.mimeType,
      );
      final statusResponse = await statusRequest.close();
      final statusBody = await utf8.decoder.bind(statusResponse).join();

      final trimmed = statusBody.trimLeft();
      final statusLooksLikeJson =
          trimmed.startsWith('{') || trimmed.startsWith('[');
      if (!statusLooksLikeJson) {
        final contentType =
            statusResponse.headers.contentType?.mimeType ?? 'unknown';
        setState(() {
          _statusMessage =
              'La URL no parece ser un backend JSON. status=${statusResponse.statusCode}, content-type=$contentType.';
        });
        return;
      }

      final decoded = jsonDecode(statusBody);
      final payload = decoded is Map<String, dynamic>
          ? decoded
          : (decoded is Map
              ? decoded.map((key, value) => MapEntry(key.toString(), value))
              : const <String, dynamic>{});
      final data = payload['data'];
      final effective = data is Map
          ? data.map((key, value) => MapEntry(key.toString(), value))
          : payload;

      final initialized = effective['initialized'] == true;

      final storedSettings = await _syncConfigRepository.loadSettings();
      final token = storedSettings.jwtToken.trim();
      if (token.isEmpty) {
        setState(() {
          _statusMessage =
              '${healthOk ? 'Health OK.' : 'Health NO OK (status=${healthResponse.statusCode}). '}Conexión API OK. initialized=$initialized. Para sincronizar necesitas iniciar sesión en línea (token no encontrado).';
        });
        return;
      }

      final meUri = apiBase.replace(
        pathSegments: [
          ...apiBase.pathSegments.where((s) => s.isNotEmpty),
          'auth',
          'me',
        ],
      );

      final meRequest = await _httpClient.getUrl(meUri);
      meRequest.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
      meRequest.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final meResponse = await meRequest.close();
      final meBody = await utf8.decoder.bind(meResponse).join();
      final meTrimmed = meBody.trimLeft();
      final meLooksLikeJson =
          meTrimmed.startsWith('{') || meTrimmed.startsWith('[');
      if (!meLooksLikeJson) {
        final contentType = meResponse.headers.contentType?.mimeType ?? 'unknown';
        setState(() {
          _statusMessage =
              'Conexión OK. initialized=$initialized. Pero /auth/me no devolvió JSON (status=${meResponse.statusCode}, content-type=$contentType).';
        });
        return;
      }

      final meDecoded = jsonDecode(meBody);
      final mePayload = meDecoded is Map<String, dynamic>
          ? meDecoded
          : (meDecoded is Map
              ? meDecoded.map((key, value) => MapEntry(key.toString(), value))
              : const <String, dynamic>{});
      final meData = mePayload['data'];
      final meEffective = meData is Map
          ? meData.map((key, value) => MapEntry(key.toString(), value))
          : mePayload;

      if (meResponse.statusCode == HttpStatus.unauthorized) {
        setState(() {
          _statusMessage =
              'Conexión OK. initialized=$initialized. Pero el token fue rechazado (401). Inicia sesión en línea nuevamente.';
        });
        return;
      }

      final type = (meEffective['type']?.toString() ?? '').trim();
      final roles = (meEffective['roles'] is List)
          ? (meEffective['roles'] as List).map((e) => e.toString()).toList()
          : const <String>[];
      final permissions = (meEffective['permissions'] is List)
          ? (meEffective['permissions'] as List)
              .map((e) => e.toString())
              .toList()
          : const <String>[];

      final isPanelActor = type == 'panel' ||
          roles.contains('PANEL_ADMIN') ||
          roles.contains('PANEL_VIEWER');
      if (isPanelActor) {
        setState(() {
          _statusMessage =
              'Conexión OK. initialized=$initialized. Pero estás autenticado como PANEL y la sincronización operativa está bloqueada. Inicia sesión desde el cliente escritorio.';
        });
        return;
      }

      final canSync = permissions.contains('sync.manage') ||
          roles.contains('SUPER_ADMIN') ||
          roles.contains('ADMIN');

      if (!canSync) {
        setState(() {
          _statusMessage =
              'Conexión OK. initialized=$initialized. Sesión OK, pero tu usuario no tiene permiso sync.manage. Asigna un rol con sync.manage (por ejemplo SUPER_ADMIN) y vuelve a intentar.';
        });
        return;
      }

      setState(() {
        _statusMessage =
            '${healthOk ? 'Health OK.' : 'Health NO OK (status=${healthResponse.statusCode}). '}Conexión API OK. initialized=$initialized. Sesión OK y permisos OK (sync.manage).';
      });
    } catch (error) {
      setState(() {
        _statusMessage = 'No se pudo conectar al backend: $error';
      });
    } finally {
      if (!mounted) return;
      setState(() => _isProbing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BaseLayout(
      title: 'Backend y sincronización',
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'URL del backend',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'La URL se usa para login en línea y sincronización. Puedes pegar el dominio base y el sistema agregará "/api" si hace falta.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFormField(
                            controller: _baseUrlController,
                            decoration: const InputDecoration(
                              labelText: 'Backend base URL',
                              hintText: 'https://tu-dominio.com',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.url,
                            textInputAction: TextInputAction.done,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              ElevatedButton.icon(
                                onPressed: _isSaving ? null : _save,
                                icon: _isSaving
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.save_outlined),
                                label: const Text('Guardar'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _isProbing ? null : _probe,
                                icon: _isProbing
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.wifi_tethering),
                                label: const Text('Probar conexión'),
                              ),
                              TextButton.icon(
                                onPressed: _isSaving || _isProbing
                                    ? null
                                    : _load,
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('Recargar'),
                              ),
                            ],
                          ),
                          if (_statusMessage != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _statusMessage!,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: Colors.grey[700]),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
