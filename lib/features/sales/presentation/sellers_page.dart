import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../features/auth/domain/permission_model.dart';
import '../../../features/auth/presentation/auth_provider.dart';
import '../../../core/resilience/friendly_error_messages.dart';
import '../../../shared/widgets/base_layout.dart';
import '../../../shared/widgets/recovery_experience.dart';
import '../data/sales_repository.dart';
import '../data/seller_repository.dart';
import '../domain/seller.dart';
import 'seller_detail_dialog.dart';
import 'seller_form_dialog.dart';

class SellersPage extends StatefulWidget {
  const SellersPage({
    super.key,
    required this.repository,
    required this.salesRepository,
  });

  final SellerRepository repository;
  final SalesRepository salesRepository;

  @override
  State<SellersPage> createState() => _SellersPageState();
}

class _SellersPageState extends State<SellersPage> {
  late final TextEditingController _searchController;

  List<Seller> _sellers = const [];
  bool _isLoading = true;
  FriendlyErrorMessage? _loadError;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({String query = ''}) async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final sellers = query.trim().isEmpty
          ? await widget.repository.getAll()
          : await widget.repository.search(query.trim());
      if (!mounted) {
        return;
      }
      setState(() {
        _sellers = sellers;
      });
    } catch (error) {
      setState(() {
        _loadError = FriendlyErrorMessages.moduleLoad('vendedores', error);
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _createSeller() async {
    final seller = await SellerFormDialog.show(context);
    if (!mounted || seller == null) {
      return;
    }

    await _saveSeller(seller, created: true);
  }

  Future<void> _editSeller(Seller seller) async {
    final updatedSeller = await SellerFormDialog.show(
      context,
      initialSeller: seller,
    );
    if (!mounted || updatedSeller == null) {
      return;
    }

    await _saveSeller(updatedSeller, created: false);
  }

  Future<void> _openSellerDetail(Seller seller) async {
    if (seller.id == null) {
      return;
    }

    await SellerDetailDialog.show(
      context,
      seller: seller,
      salesRepository: widget.salesRepository,
    );
  }

  Future<void> _saveSeller(Seller seller, {required bool created}) async {
    try {
      if (seller.id == null) {
        await widget.repository.insert(seller);
      } else {
        await widget.repository.update(
          seller.copyWith(updatedAt: DateTime.now()),
        );
      }
      await _load(query: _searchController.text);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            created
                ? 'Vendedor creado correctamente.'
                : 'Vendedor actualizado correctamente.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      FriendlyErrorMessages.forOperation(
        'guardar el vendedor',
        error,
        module: 'ventas',
      );
    }
  }

  Future<void> _confirmDelete(Seller seller) async {
    if (seller.id == null) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Eliminar vendedor'),
          content: Text('Se eliminara el vendedor ${seller.name}.'),
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

    if (confirmed != true) {
      return;
    }

    try {
      await widget.repository.delete(seller.id!);
      await _load(query: _searchController.text);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Vendedor eliminado correctamente.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      FriendlyErrorMessages.forOperation(
        'eliminar el vendedor',
        error,
        module: 'ventas',
      );
    }
  }

  void _runSearch() {
    _load(query: _searchController.text);
  }

  void _clearSearch() {
    _searchController.clear();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canCreate = auth.canAccess(
      PermissionCatalog.sellers,
      PermissionAction.create,
    );
    final canUpdate = auth.canAccess(
      PermissionCatalog.sellers,
      PermissionAction.update,
    );
    final canDelete = auth.canAccess(
      PermissionCatalog.sellers,
      PermissionAction.delete,
    );

    return BaseLayout(
      title: 'Vendedores',
      child: Column(
        children: [
          _buildToolbar(context, canCreate: canCreate),
          Expanded(
            child: _buildBody(
              canCreate: canCreate,
              canUpdate: canUpdate,
              canDelete: canDelete,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(BuildContext context, {required bool canCreate}) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
            bottom: BorderSide(color: Color(0xFFE4EAF2))),
      ),
      padding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 920;

          final searchField = SizedBox(
            height: 42,
            child: TextField(
              controller: _searchController,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Buscar por nombre, cédula o teléfono…',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: Color(0xFFD0D7E4)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: Color(0xFFD0D7E4)),
                ),
              ),
              onSubmitted: (_) => _runSearch(),
            ),
          );

          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canCreate) ...[
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 38),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onPressed: _createSeller,
                  icon: const Icon(Icons.person_add_alt_1_outlined,
                      size: 18),
                  label: const Text('Nuevo vendedor',
                      style: TextStyle(fontSize: 14)),
                ),
                const SizedBox(width: 8),
              ],
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 38),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14),
                ),
                onPressed: _runSearch,
                child: const Text('Buscar',
                    style: TextStyle(fontSize: 14)),
              ),
              const SizedBox(width: 6),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 38),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14),
                ),
                onPressed: _clearSearch,
                child: const Text('Limpiar',
                    style: TextStyle(fontSize: 14)),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                searchField,
                const SizedBox(height: 10),
                actions,
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: searchField),
              const SizedBox(width: 16),
              actions,
            ],
          );
        },
      ),
    );
  }

  Widget _buildBody({
    required bool canCreate,
    required bool canUpdate,
    required bool canDelete,
  }) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_loadError != null) {
      final failure = _loadError!;
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: InlineModuleRecoveryCard(
            title: failure.title,
            message: failure.message,
            details: failure.details,
            suggestions: failure.suggestions,
            onRetry: _load,
          ),
        ),
      );
    }

    if (_sellers.isEmpty) {
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
                    Icons.badge_outlined,
                    size: 36,
                    color: Color(0xFF3B5BDB),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Todavía no hay vendedores registrados.',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A2235),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Agrega vendedores para tenerlos disponibles en el proceso de ventas y seguimiento comercial.',
                  style: TextStyle(
                      fontSize: 14, color: Color(0xFF6B7494)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                if (canCreate)
                  FilledButton.icon(
                    onPressed: _createSeller,
                    icon: const Icon(Icons.add),
                    label: const Text('Crear vendedor'),
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
        itemCount: _sellers.length,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, indent: 64),
        itemBuilder: (context, index) {
          final seller = _sellers[index];
          final initials = seller.name.isEmpty
              ? '?'
              : seller.name[0].toUpperCase();
          final meta = [
            seller.documentId,
            if (seller.phone.isNotEmpty) seller.phone,
          ].where((s) => s.isNotEmpty).join('  ·  ');

          return InkWell(
            onTap: () => _openSellerDetail(seller),
            child: SizedBox(
              height: 62,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: const Color(0xFFE8EFF8),
                      child: Text(
                        initials,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E3A5F),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            seller.name,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1A2235),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (meta.isNotEmpty)
                            Text(
                              meta,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF8893AA)),
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (canUpdate)
                      IconButton(
                        icon: const Icon(Icons.edit_outlined,
                            size: 18),
                        color: const Color(0xFF6B7494),
                        onPressed: () => _editSeller(seller),
                      ),
                    if (canDelete)
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            size: 18),
                        color: const Color(0xFF6B7494),
                        onPressed: () => _confirmDelete(seller),
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
}
