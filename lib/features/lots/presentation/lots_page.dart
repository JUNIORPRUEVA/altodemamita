import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../features/auth/domain/permission_model.dart';
import '../../../features/auth/presentation/auth_provider.dart';
import '../../../shared/widgets/base_layout.dart';
import '../../../shared/widgets/recovery_experience.dart';
import '../data/lot_repository.dart';
import '../domain/lot.dart';
import 'lot_form_dialog.dart';
import 'lots_controller.dart';

class LotsPage extends StatefulWidget {
  const LotsPage({super.key, required this.repository});

  final LotRepository repository;

  @override
  State<LotsPage> createState() => _LotsPageState();
}

class _LotsPageState extends State<LotsPage> {
  late final LotsController _controller;
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _controller = LotsController(repository: widget.repository);
    _searchController = TextEditingController();
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canCreate = auth.canAccess(
      PermissionCatalog.lots,
      PermissionAction.create,
    );
    final canUpdate = auth.canAccess(
      PermissionCatalog.lots,
      PermissionAction.update,
    );
    final canDelete = auth.canAccess(
      PermissionCatalog.lots,
      PermissionAction.delete,
    );

    return BaseLayout(
      title: 'Solares',
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => Column(
          children: [
            _buildToolbar(canCreate: canCreate),
            Expanded(
              child: _buildBody(
                canCreate: canCreate,
                canUpdate: canUpdate,
                canDelete: canDelete,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar({required bool canCreate}) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE4EAF2))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 42,
              child: TextField(
                controller: _searchController,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Buscar por manzana, solar o estado…',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFD0D7E4)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFD0D7E4)),
                  ),
                ),
                onSubmitted: (_) => _runSearch(),
              ),
            ),
          ),
          const SizedBox(width: 16),
          if (canCreate) ...[
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 38),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onPressed: _createLot,
              icon: const Icon(Icons.add_location_alt_outlined, size: 18),
              label: const Text('Nuevo solar', style: TextStyle(fontSize: 14)),
            ),
            const SizedBox(width: 8),
          ],
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            onPressed: _runSearch,
            child: const Text('Buscar', style: TextStyle(fontSize: 14)),
          ),
          const SizedBox(width: 6),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            onPressed: _clearSearch,
            child: const Text('Limpiar', style: TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }

  Widget _buildBody({
    required bool canCreate,
    required bool canUpdate,
    required bool canDelete,
  }) {
    if (_controller.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_controller.loadError != null) {
      final failure = _controller.loadError!;
      return InlineModuleRecoveryCard(
        title: failure.title,
        message: failure.message,
        details: failure.details,
        suggestions: failure.suggestions,
        onRetry: _runSearch,
      );
    }

    if (_controller.lots.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Icon(
                    Icons.map_outlined,
                    size: 36,
                    color: Color(0xFF3B5BDB),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Todavía no hay solares registrados.',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A2235),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Agrega solares al inventario para asociarlos a ventas y realizar seguimiento de disponibilidad.',
                  style: TextStyle(fontSize: 14, color: Color(0xFF6B7494)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                if (canCreate)
                  FilledButton.icon(
                    onPressed: _createLot,
                    icon: const Icon(Icons.add),
                    label: const Text('Crear primer solar'),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      color: Colors.white,
      child: ListView.separated(
        itemCount: _controller.lots.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 64),
        itemBuilder: (context, index) {
          final lot = _controller.lots[index];
          final statusColor = _lotStatusColor(lot.status);
          final badge = lot.displayCode.length >= 2
              ? lot.displayCode.substring(0, 2).toUpperCase()
              : lot.displayCode.toUpperCase();

          return InkWell(
            onTap: canUpdate ? () => _editLot(lot) : null,
            child: SizedBox(
              height: 72,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8EFF8),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        badge,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1E3A5F),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      flex: 2,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            lot.displayCode,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1A2235),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Manz. ${lot.blockNumber}  ·  Solar ${lot.lotNumber}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF8893AA),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${lot.area.toStringAsFixed(2)} m²',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF1A2235),
                            ),
                          ),
                          Text(
                            'RD\$${_formatPrice(lot.pricePerSquareMeter)} /m²',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF8893AA),
                            ),
                          ),
                          Text(
                            'Total RD\$${_formatPrice(lot.totalPrice)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF8893AA),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        lot.status,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    if (canUpdate)
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        color: const Color(0xFF6B7494),
                        onPressed: () => _editLot(lot),
                      ),
                    if (canDelete)
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        color: const Color(0xFF6B7494),
                        onPressed: () => _confirmDelete(lot),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _createLot() async {
    final lot = await LotFormDialog.show(context);
    if (!mounted || lot == null) {
      return;
    }

    await _saveLot(lot, created: true);
  }

  Future<void> _editLot(Lot lot) async {
    final updatedLot = await LotFormDialog.show(context, initialLot: lot);
    if (!mounted || updatedLot == null) {
      return;
    }

    await _saveLot(updatedLot, created: false);
  }

  Future<void> _saveLot(Lot lot, {required bool created}) async {
    final error = await _controller.save(lot);
    if (!mounted) {
      return;
    }

    if (error != null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Theme.of(context).colorScheme.error,
          duration: const Duration(seconds: 6),
        ),
      );
      return;
    }

    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          created
              ? 'Solar creado correctamente.'
              : 'Solar actualizado correctamente.',
        ),
      ),
    );
  }

  Future<void> _confirmDelete(Lot lot) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Eliminar solar'),
          content: Text('Se eliminara el solar ${lot.displayCode}.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || lot.id == null) {
      return;
    }

    final error = await _controller.delete(lot.id!);
    if (!mounted) {
      return;
    }
    if (error != null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Theme.of(context).colorScheme.error,
          duration: const Duration(seconds: 6),
        ),
      );
      return;
    }

    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Solar eliminado correctamente.')),
    );
  }

  void _runSearch() {
    _controller.load(query: _searchController.text.trim());
  }

  void _clearSearch() {
    _searchController.clear();
    _controller.load(query: '');
  }

  Color _lotStatusColor(String status) => switch (status) {
    'disponible' => const Color(0xFF2E7D32),
    'reservado' => const Color(0xFFE67E00),
    _ => const Color(0xFF1565C0),
  };

  String _formatPrice(double price) {
    final formatter = RegExp(r'\B(?=(\d{3})+(?!\d))');
    final integerPart = price.toStringAsFixed(2);
    final parts = integerPart.split('.');
    final formatted = parts[0].replaceAll(formatter, ',');
    return '$formatted.${parts[1]}';
  }
}
