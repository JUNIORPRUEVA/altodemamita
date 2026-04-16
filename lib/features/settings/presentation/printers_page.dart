import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../features/auth/domain/admin_override_scope.dart';
import '../../../features/auth/domain/permission_model.dart';
import '../../../features/auth/presentation/admin_override_prompt.dart';
import '../../../features/auth/presentation/auth_provider.dart';
import '../../../core/system/system_config_service.dart';
import '../../../core/resilience/friendly_error_messages.dart';
import '../../../shared/widgets/recovery_experience.dart';
import '../data/printer_repository.dart';
import '../domain/printer_config.dart';
import 'printer_form_dialog.dart';
import '../../../shared/widgets/base_layout.dart';

class PrintersPage extends StatefulWidget {
  const PrintersPage({super.key, PrinterRepository? printerRepository})
    : _printerRepository = printerRepository;

  final PrinterRepository? _printerRepository;

  @override
  State<PrintersPage> createState() => _PrintersPageState();
}

class _PrintersPageState extends State<PrintersPage> {
  late final PrinterRepository _printerRepository;
  List<PrinterConfig> printers = const [];
  bool _isLoading = true;
  bool _supportsPrinterListing = false;
  FriendlyErrorMessage? _loadError;

  @override
  void initState() {
    super.initState();
    _printerRepository = widget._printerRepository ?? PrinterRepository();
    _loadPrinters();
  }

  @override
  Widget build(BuildContext context) {
    final isReadOnly = context.watch<SystemConfigService>().isReadOnly;

    return BaseLayout(
      title: 'Impresoras',
      child: Column(
              children: [
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _loadError != null
                    ? _buildErrorState()
                    : printers.isEmpty
                    ? _buildEmptyState(isReadOnly: isReadOnly)
                    : RefreshIndicator(
                        onRefresh: _loadPrinters,
                        child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            _buildSummaryCard(),
                            const SizedBox(height: 16),
                            ...printers.map(
                              (printer) => _PrinterCard(
                                printer: printer,
                                readOnly: isReadOnly,
                                onEdit: () => _editPrinter(printer),
                                onDelete: () => _deletePrinter(printer),
                                onSetDefault: () => _setDefaultPrinter(printer),
                              ),
                            ),
                          ],
                        ),
                      ),
              ],
            ),
    );
  }

  bool _canManageSettings(AuthProvider auth) {
    return auth.hasScopedAccess(
      scope: AdminOverrideScope.settingsPrinters,
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
      scope: AdminOverrideScope.settingsPrinters,
      title: 'Autorización administrativa requerida',
      message:
          'Necesitas la clave de un administrador para administrar impresoras.',
    );
  }

  Widget _buildSummaryCard() {
    final defaultPrinter = printers
        .where((printer) => printer.esPredeterminada)
        .firstOrNull;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Impresión rápida',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              defaultPrinter == null
                  ? 'Todavía no hay una impresora predeterminada guardada.'
                  : 'La impresora predeterminada actual es ${defaultPrinter.nombre}. Los módulos de recibos la usarán para imprimir rápido.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('${printers.length} configuradas')),
                Chip(
                  label: Text(
                    _supportsPrinterListing
                        ? 'Selección del sistema disponible'
                        : 'Selección nativa no disponible',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState({required bool isReadOnly}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.print_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 24),
          Text(
            'No hay impresoras configuradas',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Configura tu primera impresora y déjala guardada para impresión rápida.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: isReadOnly ? null : _addPrinter,
            icon: const Icon(Icons.add_outlined),
            label: const Text('Agregar impresora'),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    final failure = _loadError!;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InlineModuleRecoveryCard(
              title: failure.title,
              message: failure.message,
              details: failure.details,
              suggestions: failure.suggestions,
              onRetry: _loadPrinters,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadPrinters,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadPrinters() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final loadedPrinters = await _printerRepository.getAllPrinters();
      final systemPrinters = await _printerRepository.getSystemPrinters();
      if (!mounted) {
        return;
      }
      setState(() {
        printers = loadedPrinters;
        _supportsPrinterListing = systemPrinters.isNotEmpty;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = FriendlyErrorMessages.moduleLoad('impresoras', error);
        _isLoading = false;
      });
    }
  }

  Future<void> _addPrinter() async {
    if (!await _ensureAuthorized()) {
      return;
    }

    final printer = await PrinterFormDialog.show(
      context,
      printerRepository: _printerRepository,
    );
    if (printer == null) {
      return;
    }

    try {
      await _printerRepository.createPrinter(printer);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Impresora guardada correctamente.')),
      );
      await _loadPrinters();
    } catch (error) {
      if (!mounted) {
        return;
      }
      FriendlyErrorMessages.forOperation(
        'guardar la impresora',
        error,
        module: 'configuracion',
      );
    }
  }

  Future<void> _editPrinter(PrinterConfig printer) async {
    if (!await _ensureAuthorized()) {
      return;
    }

    final updatedPrinter = await PrinterFormDialog.show(
      context,
      initialPrinter: printer,
      printerRepository: _printerRepository,
    );
    if (updatedPrinter == null) {
      return;
    }

    try {
      await _printerRepository.updatePrinter(updatedPrinter);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Configuración de impresora actualizada.'),
        ),
      );
      await _loadPrinters();
    } catch (error) {
      if (!mounted) {
        return;
      }
      FriendlyErrorMessages.forOperation(
        'actualizar la impresora',
        error,
        module: 'configuracion',
      );
    }
  }

  Future<void> _deletePrinter(PrinterConfig printer) async {
    if (!await _ensureAuthorized()) {
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar impresora'),
        content: Text(
          '¿Eliminar "${printer.nombre}"? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm == true && printer.id != null) {
      try {
        await _printerRepository.deletePrinter(printer.id!);
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(const SnackBar(content: Text('Impresora eliminada.')));
        await _loadPrinters();
      } catch (error) {
        if (!mounted) {
          return;
        }
        FriendlyErrorMessages.forOperation(
          'eliminar la impresora',
          error,
          module: 'configuracion',
        );
      }
    }
  }

  Future<void> _setDefaultPrinter(PrinterConfig printer) async {
    if (!await _ensureAuthorized()) {
      return;
    }

    if (printer.id == null) {
      return;
    }

    try {
      await _printerRepository.setDefaultPrinter(printer.id!);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            '${printer.nombre} ahora es la impresora predeterminada.',
          ),
        ),
      );
      await _loadPrinters();
    } catch (error) {
      if (!mounted) {
        return;
      }
      FriendlyErrorMessages.forOperation(
        'definir la impresora predeterminada',
        error,
        module: 'configuracion',
      );
    }
  }
}

/// Tarjeta para mostrar una impresora
class _PrinterCard extends StatelessWidget {
  const _PrinterCard({
    required this.printer,
    required this.readOnly,
    required this.onEdit,
    required this.onDelete,
    required this.onSetDefault,
  });

  final PrinterConfig printer;
  final bool readOnly;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onSetDefault;

  @override
  Widget build(BuildContext context) {
    final isDefault = printer.esPredeterminada;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  Icons.print_outlined,
                  size: 32,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        printer.nombre,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        printer.modelo,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                if (isDefault)
                  Chip(
                    label: const Text('Predeterminada'),
                    backgroundColor: Colors.blue.withValues(alpha: 0.2),
                    labelStyle: TextStyle(
                      color: Colors.blue[700],
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Tipo
            Row(
              children: [
                Icon(
                  Icons.category_outlined,
                  size: 18,
                  color: Colors.grey[600],
                ),
                const SizedBox(width: 8),
                Text(
                  'Tipo: ${printer.tipo}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            if ((printer.printerLocation ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.place_outlined, size: 18, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Ubicación: ${printer.printerLocation}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
            if (!printer.hasSystemSelection) ...[
              const SizedBox(height: 8),
              Text(
                'Configuración manual: esta impresora no tiene una selección nativa guardada.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.orange[800]),
              ),
            ],
            const SizedBox(height: 16),

            // Botones
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!isDefault) ...[
                  FilledButton.tonalIcon(
                    onPressed: readOnly ? null : onSetDefault,
                    icon: const Icon(Icons.done_outlined),
                    label: const Text('Predeterminada'),
                  ),
                  const SizedBox(width: 8),
                ],
                IconButton(
                  onPressed: readOnly ? null : onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Editar',
                ),
                IconButton(
                  onPressed: readOnly ? null : onDelete,
                  icon: const Icon(Icons.delete_outline),
                  color: Colors.red,
                  tooltip: 'Eliminar',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
