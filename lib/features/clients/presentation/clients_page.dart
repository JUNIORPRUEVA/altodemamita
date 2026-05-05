import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../features/auth/domain/permission_model.dart';
import '../../../features/auth/presentation/auth_provider.dart';
import '../../../shared/sync/row_sync_badge_policy.dart';
import '../../../shared/widgets/base_layout.dart';
import '../../../shared/widgets/recovery_experience.dart';
import '../data/client_repository.dart';
import '../domain/client.dart';
import 'client_form_dialog.dart';
import 'clients_controller.dart';

class ClientsPage extends StatefulWidget {
  const ClientsPage({super.key, required this.repository});

  final ClientRepository repository;

  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends State<ClientsPage> {
  late final ClientsController _controller;
  late final TextEditingController _searchController;
  bool _hasInternet = true;
  int _internetProbeFailures = 0;
  StreamSubscription<List<ConnectivityResult>>? _internetSubscription;

  @override
  void initState() {
    super.initState();
    _controller = ClientsController(repository: widget.repository);
    _searchController = TextEditingController();
    _internetSubscription = Connectivity().onConnectivityChanged.listen((_) {
      unawaited(_refreshInternetStatus());
    });
    unawaited(_refreshInternetStatus());
    _controller.load();
  }

  @override
  void dispose() {
    unawaited(_internetSubscription?.cancel());
    _internetSubscription = null;
    _controller.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refreshInternetStatus() async {
    try {
      final connectivityResults = await Connectivity().checkConnectivity();
      final hasNetworkInterface = connectivityResults.any(
        (result) => result != ConnectivityResult.none,
      );
      if (!hasNetworkInterface) {
        _internetProbeFailures = 0;
        _setInternetStatus(false);
        return;
      }

      final lookup = await InternetAddress.lookup(
        'one.one.one.one',
      ).timeout(const Duration(seconds: 2));
      _internetProbeFailures = 0;
      _setInternetStatus(
        lookup.isNotEmpty && lookup.first.rawAddress.isNotEmpty,
      );
    } on TimeoutException {
      _internetProbeFailures += 1;
      if (_internetProbeFailures >= 2) {
        _setInternetStatus(false);
      }
    } on SocketException {
      _internetProbeFailures += 1;
      if (_internetProbeFailures >= 2) {
        _setInternetStatus(false);
      }
    } catch (_) {
      _internetProbeFailures = 0;
      _setInternetStatus(true);
    }
  }

  void _setInternetStatus(bool value) {
    if (!mounted || _hasInternet == value) {
      return;
    }
    setState(() {
      _hasInternet = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canCreate = auth.canAccess(
      PermissionCatalog.clients,
      PermissionAction.create,
    );
    final canUpdate = auth.canAccess(
      PermissionCatalog.clients,
      PermissionAction.update,
    );
    final canDelete = auth.canAccess(
      PermissionCatalog.clients,
      PermissionAction.delete,
    );

    return BaseLayout(
      title: 'Clientes',
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => Column(
          children: [
            _buildToolbar(context, canCreate: canCreate),
            Expanded(
              child: _buildBody(
                context,
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

  Widget _buildToolbar(BuildContext context, {required bool canCreate}) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE4EAF2))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 900;

          final searchField = SizedBox(
            height: 42,
            child: TextField(
              controller: _searchController,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Buscar por nombre, cédula o teléfono…',
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
          );

          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canCreate) ...[
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onPressed: _createClient,
                  icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                  label: const Text(
                    'Nuevo cliente',
                    style: TextStyle(fontSize: 14),
                  ),
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
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [searchField, const SizedBox(height: 10), actions],
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

  Widget _buildBody(
    BuildContext context, {
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

    if (_controller.clients.isEmpty) {
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
                    Icons.people_outline,
                    size: 36,
                    color: Color(0xFF3B5BDB),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Todavía no hay clientes registrados.',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A2235),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Comienza creando tu primer cliente para gestionar ventas, pagos y seguimiento desde una sola pantalla.',
                  style: TextStyle(fontSize: 14, color: Color(0xFF6B7494)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                if (canCreate)
                  FilledButton.icon(
                    onPressed: _createClient,
                    icon: const Icon(Icons.add),
                    label: const Text('Crear primer cliente'),
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
        itemCount: _controller.clients.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 64),
        itemBuilder: (context, index) {
          final client = _controller.clients[index];
          final initials = client.fullName.isEmpty
              ? '?'
              : client.fullName[0].toUpperCase();
          final meta = [
            client.documentId,
            if (client.phone != null && client.phone!.isNotEmpty) client.phone!,
          ].where((s) => s.isNotEmpty).join('  ·  ');
          final showSyncBadge = shouldShowRowSyncBadge(
            hasInternet: _hasInternet,
            syncStatus: client.syncStatus.storageValue,
            isFailed: client.syncStatus.isFailed,
          );
          final syncBadgeLabel = rowSyncBadgeLabel(
            syncStatus: client.syncStatus.storageValue,
            isFailed: client.syncStatus.isFailed,
          );

          return InkWell(
            onTap: canUpdate ? () => _editClient(client) : null,
            child: SizedBox(
              height: 62,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
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
                            client.fullName,
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
                                color: Color(0xFF8893AA),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          if (showSyncBadge && syncBadgeLabel != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: RowSyncListBadge(label: syncBadgeLabel),
                            ),
                        ],
                      ),
                    ),
                    if (client.address != null &&
                        client.address!.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          client.address!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF8893AA),
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    if (canUpdate)
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        color: const Color(0xFF6B7494),
                        onPressed: () => _editClient(client),
                      ),
                    if (canDelete)
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        color: const Color(0xFF6B7494),
                        onPressed: () => _confirmDelete(client),
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

  Future<void> _createClient() async {
    final client = await ClientFormDialog.show(context);
    if (!mounted || client == null) {
      return;
    }

    await _saveClient(client, created: true);
  }

  Future<void> _editClient(Client client) async {
    final updatedClient = await ClientFormDialog.show(
      context,
      initialClient: client,
    );
    if (!mounted || updatedClient == null) {
      return;
    }

    await _saveClient(updatedClient, created: false);
  }

  Future<void> _saveClient(Client client, {required bool created}) async {
    debugPrint('DATA ENVIADA (clientes.toMap): ${jsonEncode(client.toMap())}');
    debugPrint(
      'DATA ENVIADA (clientes.toSyncPayload): ${jsonEncode(client.toSyncPayload())}',
    );

    final error = await _controller.save(client);
    if (!mounted) {
      return;
    }

    if (error != null) {
      debugPrint('ERROR AL GUARDAR CLIENTE (mensaje): $error');
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(error)),
      );
      return;
    }

    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          created
              ? 'Cliente creado correctamente.'
              : 'Cliente actualizado correctamente.',
        ),
      ),
    );
  }

  Future<void> _confirmDelete(Client client) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Eliminar cliente'),
          content: Text('Se eliminara el cliente ${client.fullName}.'),
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

    if (confirmed != true || client.id == null) {
      return;
    }

    final error = await _controller.delete(client.id!);
    if (!mounted) {
      return;
    }

    if (error != null) {
      debugPrint('ERROR AL ELIMINAR CLIENTE (mensaje): $error');
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(error)),
      );
      return;
    }

    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Cliente eliminado correctamente.')),
    );
  }

  void _runSearch() {
    _controller.load(query: _searchController.text.trim());
  }

  void _clearSearch() {
    _searchController.clear();
    _controller.load(query: '');
  }
}
