import 'package:flutter/material.dart';

import '../../../core/network/backend_api_client.dart';
import '../../../core/network/backend_entity_id_registry.dart';
import '../../../core/system/system_config_service.dart';

/// FASE 04 — Resultado de la previsualización administrativa.
class EntityAdminPreview {
  const EntityAdminPreview({
    required this.allowed,
    required this.code,
    required this.message,
    required this.version,
  });

  final bool allowed;
  final String code;
  final String message;
  final int version;

  factory EntityAdminPreview.blocked(String message) => EntityAdminPreview(
    allowed: false,
    code: 'PREVIEW_UNAVAILABLE',
    message: message,
    version: 0,
  );

  factory EntityAdminPreview.fromMap(Map<String, dynamic> map) {
    return EntityAdminPreview(
      allowed: map['allowed'] != false,
      code: (map['code'] ?? 'OK').toString(),
      message: (map['message'] ?? '').toString(),
      version: map['entityVersion'] is num
          ? (map['entityVersion'] as num).toInt()
          : int.tryParse(map['entityVersion']?.toString() ?? '') ?? 0,
    );
  }
}

/// FASE 04 — Acceso a los endpoints OWNER de clientes y solares.
///
/// Se envía el uuid autoritativo: cliente → `Client.syncId`;
/// solar → registro de ids remotos (namespace `products`).
class EntityAdminRepository {
  EntityAdminRepository({
    BackendApiClient? apiClient,
    SystemConfigService? systemConfigService,
  }) : _apiClient = apiClient ?? BackendApiClient(),
       _systemConfigService =
           systemConfigService ?? SystemConfigService.instance;

  final BackendApiClient _apiClient;
  final SystemConfigService _systemConfigService;

  String? clientRemoteId(String? syncId) {
    final value = (syncId ?? '').trim();
    return value.isEmpty ? null : value;
  }

  String? lotRemoteId(int? lotId) =>
      BackendEntityIdRegistry.instance.resolveRemoteId('products', lotId);

  String _path(String kind, String entityId, String suffix) =>
      '/authoritative/${kind == 'client' ? 'clients' : 'lots'}/$entityId/$suffix';

  Future<EntityAdminPreview> preview({
    required String kind,
    required String entityId,
    required String action,
    Map<String, String> values = const {},
    String? status,
    String? mergeSourceId,
  }) async {
    if (entityId.trim().isEmpty) {
      return EntityAdminPreview.blocked(
        'Este registro aún no está sincronizado con el servidor.',
      );
    }
    final query = <String, String>{'action': action, ...values};
    if (status != null) query['status'] = status;
    if (mergeSourceId != null) query['mergeSourceId'] = mergeSourceId;
    try {
      final response = await _apiClient.get(
        _path(kind, entityId, 'admin-preview'),
        queryParameters: query,
      );
      final data = response is Map ? response['data'] : null;
      final map = data is Map
          ? data.map((key, value) => MapEntry(key.toString(), value))
          : <String, dynamic>{};
      return EntityAdminPreview.fromMap(map);
    } catch (error) {
      return EntityAdminPreview.blocked(
        'No se pudo validar con el servidor: ${error.toString()}',
      );
    }
  }

  Future<Map<String, dynamic>> apply({
    required String kind,
    required String entityId,
    required String action,
    required String reason,
    required int expectedVersion,
    Map<String, String> values = const {},
    String? status,
    String? mergeSourceId,
    String? idempotencyKey,
  }) async {
    _systemConfigService.ensureWritable();
    if (entityId.trim().isEmpty) {
      throw const BackendApiException(
        'Este registro aún no está sincronizado con el servidor.',
      );
    }
    final numeric = <String, double>{};
    for (final entry in values.entries) {
      final parsed = double.tryParse(entry.value.replaceAll(',', '.'));
      if (parsed != null) numeric[entry.key] = parsed;
    }
    final response = await _apiClient.post(
      _path(kind, entityId, 'admin'),
      idempotencyKey:
          idempotencyKey ??
          'desktop-admin-$kind-$entityId-$action-'
              '${DateTime.now().microsecondsSinceEpoch}',
      body: {
        'action': action,
        'reason': reason,
        'expectedVersion': expectedVersion,
        ...values,
        ...numeric,
        'status': ?status,
        'mergeSourceId': ?mergeSourceId,
      },
    );
    final data = response is Map ? response['data'] : null;
    return data is Map
        ? data.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> fetchAudit({
    required String kind,
    required String entityId,
  }) async {
    final response = await _apiClient.get(_path(kind, entityId, 'admin-audit'));
    final data = response is Map ? response['data'] : null;
    return data is Map
        ? data.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};
  }
}

/// Campo editable del diálogo administrativo.
class EntityAdminField {
  const EntityAdminField({
    required this.key,
    required this.label,
    this.initial = '',
    this.numeric = false,
  });

  final String key;
  final String label;
  final String initial;
  final bool numeric;
}

/// FASE 04 — Diálogo único de administración de clientes y solares.
///
/// Muestra el resultado autoritativo del backend (permitido/bloqueado con su
/// motivo), exige motivo escrito y deshabilita la confirmación si el backend no
/// autoriza la operación.
class EntityAdminDialog extends StatefulWidget {
  const EntityAdminDialog({
    super.key,
    required this.title,
    required this.loadPreview,
    required this.apply,
    this.fields = const [],
    this.summaryLines = const [],
  });

  final String title;
  final Future<EntityAdminPreview> Function(Map<String, String> values)
  loadPreview;
  final Future<Map<String, dynamic>> Function(
    String reason,
    Map<String, String> values,
  )
  apply;
  final List<EntityAdminField> fields;
  final List<String> summaryLines;

  @override
  State<EntityAdminDialog> createState() => _EntityAdminDialogState();
}

class _EntityAdminDialogState extends State<EntityAdminDialog> {
  late final Map<String, TextEditingController> _controllers = {
    for (final field in widget.fields)
      field.key: TextEditingController(text: field.initial),
  };
  final TextEditingController _reasonController = TextEditingController();
  EntityAdminPreview? _preview;
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _reasonController.dispose();
    super.dispose();
  }

  Map<String, String> get _values => {
    for (final entry in _controllers.entries)
      if (entry.value.text.trim().isNotEmpty) entry.key: entry.value.text.trim(),
  };

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final preview = await widget.loadPreview(_values);
    if (!mounted) return;
    setState(() {
      _preview = preview;
      _loading = false;
    });
  }

  Future<void> _submit() async {
    final reason = _reasonController.text.trim();
    if (reason.length < 5) {
      setState(() => _error = 'Indica el motivo (mín. 5 caracteres).');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.apply(reason, _values);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final canSubmit =
        (preview?.allowed ?? false) &&
        !_loading &&
        !_submitting &&
        _reasonController.text.trim().length >= 5;

    return AlertDialog(
      title: Text(widget.title, style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final line in widget.summaryLines)
                Text(
                  line,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                ),
              if (widget.fields.isNotEmpty) const SizedBox(height: 8),
              for (final field in widget.fields) ...[
                TextField(
                  controller: _controllers[field.key],
                  keyboardType: field.numeric
                      ? const TextInputType.numberWithOptions(decimal: true)
                      : TextInputType.text,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    labelText: field.label,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 6),
              ],
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (preview != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: preview.allowed
                        ? const Color(0xFFECFDF5)
                        : const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: preview.allowed
                          ? const Color(0xFFA7F3D0)
                          : const Color(0xFFFECACA),
                    ),
                  ),
                  child: Text(
                    preview.message.isEmpty
                        ? (preview.allowed
                              ? 'Cambio permitido.'
                              : 'El servidor no autoriza este cambio.')
                        : preview.message,
                    style: TextStyle(
                      fontSize: 11,
                      color: preview.allowed
                          ? const Color(0xFF065F46)
                          : const Color(0xFF991B1B),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _submitting ? null : _reload,
                    child: const Text(
                      'Calcular impacto',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 6),
              TextField(
                controller: _reasonController,
                maxLength: 200,
                style: const TextStyle(fontSize: 12),
                decoration: const InputDecoration(
                  labelText: 'Motivo',
                  hintText: 'Ej.: dato mal capturado',
                  isDense: true,
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() => _error = null),
              ),
              if (_error != null) ...[
                const SizedBox(height: 6),
                Text(
                  _error!,
                  style: const TextStyle(fontSize: 11, color: Color(0xFFB91C1C)),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: canSubmit ? _submit : null,
          child: _submitting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(widget.title),
        ),
      ],
    );
  }
}
