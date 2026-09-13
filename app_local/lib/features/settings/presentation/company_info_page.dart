import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/cloud_foundation/cloud_api_client.dart';
import '../../../core/config/backend_config.dart' as backend_config;
import '../../../core/database/app_database.dart';
import '../../../core/resilience/friendly_error_messages.dart';
import '../../../core/system/system_config_service.dart';
import '../../../core/utils/dominican_formatters.dart';
import '../../../features/auth/domain/admin_override_scope.dart';
import '../../../features/auth/domain/permission_model.dart';
import '../../../features/auth/presentation/admin_override_prompt.dart';
import '../../../features/auth/presentation/auth_provider.dart';
import '../../../services/sync/sync_config_repository.dart';
import '../data/company_logo_storage.dart';
import '../data/company_repository.dart';
import '../domain/company_info.dart';
import '../../../shared/widgets/base_layout.dart';
import '../../../shared/widgets/recovery_experience.dart';

class CompanyInfoPage extends StatefulWidget {
  const CompanyInfoPage({super.key});

  @override
  State<CompanyInfoPage> createState() => _CompanyInfoPageState();
}

class _CompanyInfoPageState extends State<CompanyInfoPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombreController;
  late final TextEditingController _telefonoController;
  late final TextEditingController _direccionController;

  CompanyInfo? _company;
  String? _logoBase64;
  String? _logoLocalPath;
  String? _logoRemoteUrl;
  Uint8List? _logoBytes;
  String? _cloudLogoUrl;
  bool _cloudLogoPresent = false;
  bool _logoDirty = false;
  bool _isLoading = true;
  bool _isRefreshingCloud = false;
  bool _isSaving = false;
  FriendlyErrorMessage? _loadError;

  @override
  void initState() {
    super.initState();
    _nombreController = TextEditingController();
    _telefonoController = TextEditingController();
    _direccionController = TextEditingController();
    _loadCompanyInfo();
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _telefonoController.dispose();
    _direccionController.dispose();
    super.dispose();
  }

  bool _canManageSettings(AuthProvider auth) {
    return auth.hasScopedAccess(
      scope: AdminOverrideScope.settingsCompany,
      module: PermissionCatalog.settings,
      action: PermissionAction.update,
    );
  }

  Future<bool> _ensureAuthorized() async {
    final auth = context.read<AuthProvider>();
    if (_canManageSettings(auth)) {
      return true;
    }

    return requestAdminOverride(
      context,
      scope: AdminOverrideScope.settingsCompany,
      title: 'Autorización administrativa requerida',
      message:
          'Necesitas la clave de un administrador para modificar la información de la empresa.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isReadOnly = context.watch<SystemConfigService>().isReadOnly;

    return BaseLayout(
      title: 'Información de la Empresa',
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: InlineModuleRecoveryCard(
                  title: _loadError!.title,
                  message: _loadError!.message,
                  details: _loadError!.details,
                  suggestions: _loadError!.suggestions,
                  onRetry: _loadCompanyInfo,
                ),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Detalles de la empresa',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'La información se obtiene del perfil cloud de la empresa y se usa en recibos y reportes.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 24),

                    Center(
                      child: Column(
                        children: [
                          Container(
                            width: 130,
                            height: 130,
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Theme.of(
                                  context,
                                ).colorScheme.outline.withValues(alpha: 0.2),
                                width: 2,
                              ),
                            ),
                            child: InkWell(
                              onTap: isReadOnly ? null : _uploadLogo,
                              borderRadius: BorderRadius.circular(16),
                              child: _buildLogoPreview(context),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: isReadOnly ? null : _uploadLogo,
                                icon: const Icon(Icons.upload_file_outlined),
                                label: const Text('Cambiar logo'),
                              ),
                              if (_logoBytes != null)
                                OutlinedButton.icon(
                                  onPressed: isReadOnly ? null : _clearLogo,
                                  icon: const Icon(Icons.delete_outline),
                                  label: const Text('Quitar'),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _buildUploadStatusChip(),
                          if (_isRefreshingCloud) ...[
                            const SizedBox(height: 8),
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _nombreController,
                              enabled: !isReadOnly,
                              decoration: const InputDecoration(
                                labelText: 'Nombre de empresa *',
                                prefixIcon: Icon(Icons.business_outlined),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'El nombre es requerido';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _telefonoController,
                              enabled: !isReadOnly,
                              decoration: const InputDecoration(
                                labelText: 'Telefono *',
                                prefixIcon: Icon(Icons.phone_outlined),
                              ),
                              inputFormatters: [DominicanPhoneFormatter()],
                              keyboardType: TextInputType.phone,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'El telefono es requerido';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _direccionController,
                              enabled: !isReadOnly,
                              decoration: const InputDecoration(
                                labelText: 'Direccion *',
                                prefixIcon: Icon(Icons.location_on_outlined),
                                alignLabelWithHint: true,
                              ),
                              maxLines: 3,
                              minLines: 3,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'La direccion es requerida';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 24),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => Navigator.pop(context),
                                    icon: const Icon(Icons.close),
                                    label: const Text('Cancelar'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: _isSaving || isReadOnly
                                        ? null
                                        : _save,
                                    icon: const Icon(Icons.save_outlined),
                                    label: Text(
                                      _isSaving ? 'Guardando...' : 'Guardar',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Future<void> _loadCompanyInfo() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final db = await AppDatabase.instance.database;
      final repository = CompanyRepository(db);
      final cachedCompany = await repository.getCompanyInfo();

      if (!mounted) {
        return;
      }

      if (cachedCompany != null) {
        _applyCompanyInfo(cachedCompany);
        setState(() {
          _isLoading = false;
          _isRefreshingCloud = true;
        });
      }

      await _refreshCloudLogoAvailability();
      final cloudCompany = await _loadCloudCompanyInfo(repository);

      if (!mounted) {
        return;
      }

      if (cloudCompany != null) {
        _applyCompanyInfo(cloudCompany);
      }

      setState(() {
        _logoDirty = false;
        _loadError = null;
        _isLoading = false;
        _isRefreshingCloud = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = FriendlyErrorMessages.moduleLoad(
          'información de la empresa',
          error,
        );
        _isLoading = false;
        _isRefreshingCloud = false;
      });
    }
  }

  Future<void> _refreshCloudLogoAvailability() async {
    final response = await CloudApiClient().get(
      '/system/branding',
      accessToken: '',
    );
    if (!response.isSuccess) {
      return;
    }

    final data = response.body['data'];
    if (data is! Map) {
      return;
    }

    final present = data['present'] == true;
    final updatedAt = data['updatedAt']?.toString().trim();
    setState(() {
      _cloudLogoPresent = present;
      _cloudLogoUrl = present
          ? _brandingLogoUrl(
              version: updatedAt?.isEmpty == true ? null : updatedAt,
            )
          : null;
    });
  }

  Future<CompanyInfo?> _loadCloudCompanyInfo(
    CompanyRepository repository,
  ) async {
    final settings = await SyncConfigRepository().loadSettings();
    final token = settings.jwtToken.trim();
    if (token.isEmpty) {
      if (_company == null) {
        throw StateError('No hay una sesión cloud activa.');
      }
      return null;
    }

    final response = await CloudApiClient().getCompanyProfile(
      accessToken: token,
    );
    if (!response.isSuccess) {
      if (_company == null) {
        throw StateError('No pudimos cargar la información de la empresa.');
      }
      return null;
    }

    final data = response.body['data'];
    if (data is! Map) {
      return null;
    }
    final profile = data['profile'];
    if (profile is! Map) {
      return null;
    }

    final now = DateTime.now();
    final updatedAt =
        DateTime.tryParse(profile['updatedAt']?.toString() ?? '') ?? now;
    final createdAt =
        DateTime.tryParse(profile['createdAt']?.toString() ?? '') ?? updatedAt;
    final cloudCompany = CompanyInfo(
      nombre: profile['name']?.toString().trim() ?? '',
      telefono: _nullableCloudText(profile['phone']),
      direccion: _nullableCloudText(profile['address']),
      logoBytesBase64: _nullableCloudText(profile['logoBase64']),
      logoLocalPath: null,
      logoRemoteUrl: _nullableCloudText(profile['logoRemoteUrl']),
      logoUploadStatus:
          _nullableCloudText(profile['logoUploadStatus']) ?? 'uploaded',
      fechaCreacion: createdAt,
      fechaActualizacion: updatedAt,
    );

    return repository.cacheCloudCompanyInfo(cloudCompany);
  }

  void _applyCompanyInfo(CompanyInfo company) {
    _company = company;
    _nombreController.text = company.nombre;
    _telefonoController.text = company.telefono ?? '';
    _direccionController.text = company.direccion ?? '';
    _logoBase64 = company.logoBytesBase64;
    _logoLocalPath = company.logoLocalPath;
    _logoRemoteUrl = company.logoRemoteUrl;
    _logoBytes = null;

    final logoBase64 = _logoBase64?.trim();
    if (logoBase64 != null && logoBase64.isNotEmpty) {
      try {
        _logoBytes = base64Decode(logoBase64);
      } catch (_) {
        _logoBytes = null;
      }
    }

    if (!kIsWeb && _logoBytes == null) {
      readLogoBytesFromLocalPath(_logoLocalPath).then((bytes) {
        if (!mounted || bytes == null || bytes.isEmpty) {
          return;
        }
        setState(() => _logoBytes = bytes);
      });
    }
  }

  String? _nullableCloudText(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    return text;
  }

  String _brandingLogoUrl({String? version}) {
    final base = backend_config.backendEndpoint('/system/branding/logo');
    if (version == null || version.trim().isEmpty) {
      return base;
    }
    return Uri.parse(
      base,
    ).replace(queryParameters: {'v': version.trim()}).toString();
  }

  Future<void> _uploadLogo() async {
    if (!await _ensureAuthorized()) {
      return;
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final bytes = await readPickedLogoBytes(result.files.single);
      if (bytes == null || bytes.isEmpty) {
        throw StateError('No fue posible leer la imagen seleccionada.');
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _logoBytes = bytes;
        _logoBase64 = base64Encode(bytes);
        _logoDirty = true;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      FriendlyErrorMessages.forOperation(
        'cargar el logo',
        error,
        module: 'configuracion',
      );
    }
  }

  Future<void> _clearLogo() async {
    if (!await _ensureAuthorized()) {
      return;
    }

    setState(() {
      _logoBytes = null;
      _logoBase64 = null;
      _logoLocalPath = null;
      _logoRemoteUrl = null;
      _logoDirty = true;
    });
  }

  Future<void> _save() async {
    if (!await _ensureAuthorized()) {
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSaving = true);

    try {
      final db = await AppDatabase.instance.database;
      final repository = CompanyRepository(db);
      final now = DateTime.now();
      final existing = _company;
      final persistedLocalPath = _logoDirty
          ? await persistCompanyLogoLocally(_logoBytes)
          : (existing?.logoLocalPath ?? _logoLocalPath);
      final nextRemoteUrl = _logoDirty
          ? (_logoBytes == null ? null : null)
          : (existing?.logoRemoteUrl ?? _logoRemoteUrl);
      final nextUploadStatus = _logoDirty
          ? (_logoBytes == null ? 'uploaded' : 'pending_upload')
          : (existing?.logoUploadStatus ??
                (_logoBytes == null ? 'uploaded' : 'pending_upload'));
      final companyToSave = CompanyInfo(
        id: existing?.id,
        nombre: _nombreController.text.trim(),
        telefono: _telefonoController.text.trim(),
        direccion: _direccionController.text.trim(),
        logoBytesBase64: _logoBase64,
        logoLocalPath: persistedLocalPath,
        logoRemoteUrl: nextRemoteUrl,
        logoUploadStatus: nextUploadStatus,
        fechaCreacion: existing?.fechaCreacion ?? now,
        fechaActualizacion: now,
      );

      _company = await repository.saveCompanyInfo(companyToSave);
      if (!mounted) {
        return;
      }

      setState(() {
        _logoDirty = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Información guardada correctamente')),
      );

      Navigator.pop(context);
    } catch (error) {
      if (!mounted) {
        return;
      }
      FriendlyErrorMessages.forOperation(
        'guardar la información de la empresa',
        error,
        module: 'configuracion',
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Widget _buildUploadStatusChip() {
    final effectiveStatus = _logoDirty
        ? (_logoBytes == null ? 'uploaded' : 'pending_upload')
        : (_company?.logoUploadStatus ?? 'uploaded');
    final hasRenderableLogo =
        _logoBytes != null ||
        (_cloudLogoPresent && (_cloudLogoUrl?.trim().isNotEmpty ?? false));

    switch (effectiveStatus) {
      case 'pending_upload':
        return const Chip(
          avatar: Icon(Icons.cloud_upload_outlined, size: 18),
          label: Text('Logo pendiente de subir'),
        );
      case 'failed':
        return const Chip(
          avatar: Icon(Icons.error_outline, size: 18),
          label: Text('Error de subida, se reintentará'),
        );
      default:
        if (!hasRenderableLogo) {
          return const Chip(
            avatar: Icon(Icons.hide_image_outlined, size: 18),
            label: Text('Logo no publicado'),
          );
        }
        return const Chip(
          avatar: Icon(Icons.cloud_done_outlined, size: 18),
          label: Text('Logo disponible en cloud'),
        );
    }
  }

  Widget _buildLogoPreview(BuildContext context) {
    final cloudUrl = _cloudLogoUrl?.trim();
    if (_logoBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.memory(_logoBytes!, fit: BoxFit.cover),
      );
    }

    if (_cloudLogoPresent && cloudUrl != null && cloudUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.network(
          cloudUrl,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _buildLogoPlaceholder(context, label: 'Logo no disponible');
          },
        ),
      );
    }

    return _buildLogoPlaceholder(context, label: 'Subir logo');
  }

  Widget _buildLogoPlaceholder(BuildContext context, {required String label}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.image_outlined, size: 48, color: Colors.grey[600]),
        const SizedBox(height: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
