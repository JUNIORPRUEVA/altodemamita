import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/system/system_config_service.dart';
import '../../../features/auth/presentation/auth_provider.dart';
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

  Future<void> _save() async {
    final raw = _baseUrlController.text;
    final normalized = _normalizeDisplayUrl(raw);

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
      final uri = Uri.parse(normalized);
      final pathSegments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      final baseHasApi = pathSegments.isNotEmpty &&
          pathSegments.last.toLowerCase() == 'api';
      final normalizedBase = baseHasApi
          ? uri
          : uri.replace(pathSegments: [...pathSegments, 'api']);
      final statusUri = normalizedBase.replace(
        pathSegments: [
          ...normalizedBase.pathSegments.where((s) => s.isNotEmpty),
          'system',
          'status',
        ],
      );

      final request = await _httpClient.getUrl(statusUri);
      request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();

      final trimmed = body.trimLeft();
      final looksLikeJson = trimmed.startsWith('{') || trimmed.startsWith('[');
      if (!looksLikeJson) {
        final contentType = response.headers.contentType?.mimeType ?? 'unknown';
        setState(() {
          _statusMessage =
              'La URL no parece ser un backend JSON. status=${response.statusCode}, content-type=$contentType.';
        });
        return;
      }

      final decoded = jsonDecode(body);
      final payload = decoded is Map<String, dynamic>
          ? decoded
          : (decoded is Map
              ? decoded.map((key, value) => MapEntry(key.toString(), value))
              : const <String, dynamic>{});
      final data = payload['data'];
      final effective = data is Map
          ? data.map((key, value) => MapEntry(key.toString(), value))
          : payload;

      setState(() {
        _statusMessage =
            'Conexión OK. initialized=${effective['initialized'] == true}';
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
