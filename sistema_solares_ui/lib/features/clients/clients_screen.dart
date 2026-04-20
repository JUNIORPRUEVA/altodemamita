import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sistema_solares_ui/core/network/api_client.dart';
import 'package:sistema_solares_ui/core/realtime/realtime_controller.dart';
import 'package:sistema_solares_ui/features/clients/clients_service.dart';
import 'package:sistema_solares_ui/shared/desktop_ui.dart';

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  final _searchController = TextEditingController();
  Future<ClientsPage>? _future;
  int _lastTick = -1;
  int _page = 1;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reload({bool resetPage = false}) {
    if (resetPage) {
      _page = 1;
    }
    setState(() => _future = null);
  }

  @override
  Widget build(BuildContext context) {
    final refreshTick = context.watch<RealtimeController>().refreshTick;
    if (_future == null || refreshTick != _lastTick) {
      _lastTick = refreshTick;
      _future = ClientsService(
        context.read<ApiClient>(),
      ).fetch(search: _searchController.text, page: _page);
    }

    return FutureBuilder<ClientsPage>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return DesktopPageError(
            message: snapshot.error.toString(),
            onRetry: () => _reload(),
          );
        }

        final data = snapshot.data!;
        final compact = MediaQuery.sizeOf(context).width < 760;
        final hasFilter = _searchController.text.trim().isNotEmpty;
        return DesktopPageScaffold(
          title: 'Clientes',
          subtitle: compact
              ? null
              : 'Consulta y seguimiento de clientes registrados.',
          toolbar: DesktopFieldToolbar(
            child: DesktopToolbar(
              searchField: DesktopSearchField(
                controller: _searchController,
                hintText: 'Buscar por nombre, cedula, correo o telefono',
                onSubmitted: (_) => _reload(resetPage: true),
              ),
              actions: [
                OutlinedButton.icon(
                  onPressed: () {
                    _searchController.clear();
                    _reload(resetPage: true);
                  },
                  icon: const Icon(Icons.cleaning_services_outlined),
                  label: const Text('Limpiar'),
                ),
                FilledButton.icon(
                  onPressed: () => _reload(resetPage: true),
                  icon: const Icon(Icons.search_rounded),
                  label: const Text('Buscar'),
                ),
              ],
              compactActions: [
                DesktopToolbarIconAction(
                  icon: Icons.cleaning_services_outlined,
                  tooltip: 'Limpiar',
                  onPressed: () {
                    _searchController.clear();
                    _reload(resetPage: true);
                  },
                ),
                DesktopToolbarIconAction(
                  icon: Icons.search_rounded,
                  tooltip: 'Buscar',
                  tone: DesktopToolbarActionTone.filled,
                  onPressed: () => _reload(resetPage: true),
                ),
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DesktopInfoStrip(
                child: Wrap(
                  spacing: compact ? 8 : 10,
                  runSpacing: compact ? 8 : 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    DesktopTag(
                      label: compact
                          ? '${data.visibleFrom}-${data.visibleTo} de ${data.total}'
                          : 'Mostrando ${data.visibleFrom}-${data.visibleTo} de ${data.total}',
                      background: const Color(0xFFF1F4FA),
                    ),
                    DesktopTag(
                      label: 'Pagina ${data.page} de ${data.totalPages}',
                      background: const Color(0xFFEAF2EC),
                      foreground: const Color(0xFF2F6F5C),
                    ),
                    DesktopTag(
                      label: hasFilter ? 'Filtro activo' : 'Vista completa',
                      background: hasFilter
                          ? const Color(0xFFF6EFE3)
                          : const Color(0xFFE7F5EF),
                      foreground: hasFilter
                          ? const Color(0xFF8C5A2C)
                          : const Color(0xFF2F6F5C),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              compact
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: data.hasPreviousPage
                                ? () {
                                    _page = data.page - 1;
                                    _reload();
                                  }
                                : null,
                            icon: const Icon(
                              Icons.chevron_left_rounded,
                              size: 16,
                            ),
                            label: const Text('Anterior'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 34),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: data.hasNextPage
                                ? () {
                                    _page = data.page + 1;
                                    _reload();
                                  }
                                : null,
                            icon: const Icon(
                              Icons.chevron_right_rounded,
                              size: 16,
                            ),
                            label: const Text('Siguiente'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 34),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      alignment: WrapAlignment.end,
                      children: [
                        OutlinedButton.icon(
                          onPressed: data.hasPreviousPage
                              ? () {
                                  _page = data.page - 1;
                                  _reload();
                                }
                              : null,
                          icon: const Icon(Icons.chevron_left_rounded),
                          label: const Text('Anterior'),
                        ),
                        FilledButton.icon(
                          onPressed: data.hasNextPage
                              ? () {
                                  _page = data.page + 1;
                                  _reload();
                                }
                              : null,
                          icon: const Icon(Icons.chevron_right_rounded),
                          label: const Text('Siguiente'),
                        ),
                      ],
                    ),
              const SizedBox(height: 16),
              Expanded(
                child: data.items.isEmpty
                    ? const DesktopEmptyState(
                        icon: Icons.people_outline_rounded,
                        title: 'No hay clientes para este filtro',
                        message:
                            'Prueba otro termino de busqueda o espera a la siguiente sincronizacion.',
                      )
                    : DesktopModuleList(
                        children: data.items.map((item) {
                          final fullName =
                              '${item['firstName'] ?? ''} ${item['lastName'] ?? ''}'
                                  .trim();
                          final documentId =
                              item['documentId']?.toString() ?? 'Sin documento';
                          final phone =
                              item['phone']?.toString() ?? 'Sin telefono';
                          final code = item['code']?.toString() ?? '-';
                          final email =
                              item['email']?.toString() ?? 'Sin correo';
                          final subtitleText = compact
                              ? '$documentId  •  $phone'
                              : '$documentId  •  $phone  •  $email';
                          return DesktopListRow(
                            height: compact ? 72 : 72,
                            leading: CircleAvatar(
                              radius: compact ? 15 : 22,
                              backgroundColor: const Color(0xFFEFF3FB),
                              child: Text(
                                (fullName.isNotEmpty ? fullName[0] : 'C')
                                    .toUpperCase(),
                                style: const TextStyle(
                                  color: Color(0xFF223048),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    fullName.isEmpty ? 'Sin nombre' : fullName,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: compact ? 12.5 : null,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (compact) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF6EFE3),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      code,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 10.5,
                                        color: Color(0xFF8C5A2C),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            subtitle: Text(
                              subtitleText,
                              style: TextStyle(
                                color: const Color(0xFF6E7791),
                                fontSize: compact ? 10.8 : null,
                                height: compact ? 1.1 : null,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: compact
                                ? null
                                : Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF6EFE3),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      code,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF8C5A2C),
                                      ),
                                    ),
                                  ),
                          );
                        }).toList(),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
