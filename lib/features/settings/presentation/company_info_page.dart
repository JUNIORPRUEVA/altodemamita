import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/database/app_database.dart';
import '../../../core/resilience/friendly_error_messages.dart';
import '../../../core/system/system_config_service.dart';
import '../../../core/utils/dominican_formatters.dart';
import '../../../features/auth/domain/admin_override_scope.dart';
import '../../../features/auth/domain/permission_model.dart';
import '../../../features/auth/presentation/admin_override_prompt.dart';
import '../../../features/auth/presentation/auth_provider.dart';
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
  Uint8List? _logoBytes;
  bool _isLoading = true;
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
                      'La información guardada se utiliza en recibos y reportes de la aplicación.',
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
                              child: _logoBytes == null
                                  ? Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.image_outlined,
                                          size: 48,
                                          color: Colors.grey[600],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Subir logo',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.labelSmall,
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    )
                                  : ClipRRect(
                                      borderRadius: BorderRadius.circular(14),
                                      child: Image.memory(
                                        _logoBytes!,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
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
    try {
      final db = await AppDatabase.instance.database;
      final company = await CompanyRepository(db).getCompanyInfo();

      if (!mounted) {
        return;
      }

      setState(() {
        _company = company;
        _nombreController.text = company?.nombre ?? '';
        _telefonoController.text = company?.telefono ?? '';
        _direccionController.text = company?.direccion ?? '';
        _logoBase64 = company?.logoBytesBase64;
        _logoBytes = _logoBase64 == null || _logoBase64!.isEmpty
            ? null
            : base64Decode(_logoBase64!);
        _loadError = null;
        _isLoading = false;
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
      });
    }
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

      Uint8List? bytes = result.files.single.bytes;
      if ((bytes == null || bytes.isEmpty) &&
          result.files.single.path != null) {
        bytes = await File(result.files.single.path!).readAsBytes();
      }
      if (bytes == null || bytes.isEmpty) {
        throw StateError('No fue posible leer la imagen seleccionada.');
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _logoBytes = bytes;
        _logoBase64 = base64Encode(bytes!);
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
      final companyToSave = CompanyInfo(
        id: existing?.id,
        nombre: _nombreController.text.trim(),
        telefono: _telefonoController.text.trim(),
        direccion: _direccionController.text.trim(),
        logoBytesBase64: _logoBase64,
        fechaCreacion: existing?.fechaCreacion ?? now,
        fechaActualizacion: now,
      );

      _company = await repository.saveCompanyInfo(companyToSave);
      if (!mounted) {
        return;
      }

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
}
