import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:sistema_solares_ui/core/network/api_client.dart';
import 'package:sistema_solares_ui/core/realtime/realtime_controller.dart';
import 'package:sistema_solares_ui/features/global_search/global_search_service.dart';
import 'package:sistema_solares_ui/shared/desktop_ui.dart';

class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final _searchController = TextEditingController();
  Future<List<GlobalSearchSummary>>? _future;
  int _lastTick = -1;
  String _lastSubmittedQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reload() {
    final query = _searchController.text.trim();
    setState(() {
      _lastSubmittedQuery = query;
      _future = query.isEmpty
          ? null
          : GlobalSearchService(context.read<ApiClient>()).search(query);
    });
  }

  @override
  Widget build(BuildContext context) {
    final refreshTick = context.watch<RealtimeController>().refreshTick;
    if (
      _future != null &&
      _lastSubmittedQuery.isNotEmpty &&
      refreshTick != _lastTick
    ) {
      _lastTick = refreshTick;
      _future = GlobalSearchService(
        context.read<ApiClient>(),
      ).search(_lastSubmittedQuery);
    }

    return DesktopPageScaffold(
      title: 'Buscador global',
      subtitle: 'Busca por cliente, contrato o solar para ver todo su historial en la nube.',
      toolbar: DesktopFieldToolbar(
        child: DesktopToolbar(
          searchField: DesktopSearchField(
            controller: _searchController,
            hintText: 'Nombre, cedula, telefono, contrato o solar',
            onSubmitted: (_) => _reload(),
          ),
          actions: [
            OutlinedButton.icon(
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _future = null;
                  _lastSubmittedQuery = '';
                });
              },
              icon: const Icon(Icons.cleaning_services_outlined),
              label: const Text('Limpiar'),
            ),
            FilledButton.icon(
              onPressed: _reload,
              icon: const Icon(Icons.search_rounded),
              label: const Text('Buscar'),
            ),
          ],
          compactActions: [
            OutlinedButton.icon(
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _future = null;
                  _lastSubmittedQuery = '';
                });
              },
              icon: const Icon(Icons.cleaning_services_outlined),
              label: const Text('Limpiar'),
            ),
            FilledButton.icon(
              onPressed: _reload,
              icon: const Icon(Icons.search_rounded),
              label: const Text('Buscar'),
            ),
          ],
        ),
      ),
      child: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_future == null) {
      return const DesktopEmptyState(
        icon: Icons.travel_explore_outlined,
        title: 'Escribe un criterio de busqueda',
        message:
            'Puedes buscar por nombre, cedula, telefono, contrato o solar para reunir el expediente del cliente.',
      );
    }

    return FutureBuilder<List<GlobalSearchSummary>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return DesktopPageError(
            message: snapshot.error.toString(),
            onRetry: _reload,
          );
        }

        final results = snapshot.data ?? const <GlobalSearchSummary>[];
        final compact = MediaQuery.sizeOf(context).width < 760;
        if (results.isEmpty) {
          return const DesktopEmptyState(
            icon: Icons.search_off_rounded,
            title: 'No hubo coincidencias',
            message:
                'Prueba otro termino. El buscador cruza clientes y ventas para devolverte todo lo relacionado en la nube.',
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DesktopInfoStrip(
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  DesktopTag(
                    label: 'Resultados: ${results.length}',
                    background: const Color(0xFFF1F4FA),
                  ),
                  DesktopTag(
                    label: 'Consulta: $_lastSubmittedQuery',
                    background: const Color(0xFFF6EFE3),
                    foreground: const Color(0xFF8C5A2C),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: DesktopModuleList(
                children: results.map((result) {
                  final client = result.client;
                  final fullName = _fullName(client);
                  final phone = client['phone']?.toString() ?? 'Sin telefono';
                  final document = client['documentId']?.toString() ?? 'Sin cedula';
                  final email = client['email']?.toString() ?? 'Sin correo';
                  final subtitle = compact
                      ? '$document  •  $phone\n$email'
                      : '$document  •  $phone  •  $email';
                  final totalOutstanding = result.sales.fold<double>(
                    0,
                    (sum, sale) => sum + _asNum(sale['outstandingBalance']),
                  );

                  return DesktopListRow(
                    height: compact ? 124 : 88,
                    onTap: () => _openDetail(result.clientId),
                    leading: CircleAvatar(
                      radius: compact ? 18 : 22,
                      backgroundColor: const Color(0xFFEFF3FB),
                      child: Text(
                        fullName.isEmpty ? 'C' : fullName[0].toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xFF223048),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    title: Text(
                      fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      subtitle,
                      maxLines: compact ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF6E7791)),
                    ),
                    trailing: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        DesktopTag(
                          label: '${result.sales.length} venta(s)',
                          background: const Color(0xFFEAF0F7),
                        ),
                        DesktopTag(
                          label: _matchLabel(result.matchTypes),
                          background: const Color(0xFFE7F5EF),
                          foreground: const Color(0xFF2F6F5C),
                        ),
                        DesktopTag(
                          label: _currency.format(totalOutstanding),
                          background: const Color(0xFFF6EFE3),
                          foreground: const Color(0xFF8C5A2C),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openDetail(String clientId) async {
    if (clientId.trim().isEmpty) {
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final detail = await GlobalSearchService(
        context.read<ApiClient>(),
      ).fetchDetail(clientId);
      if (!mounted) {
        return;
      }
      Navigator.of(context, rootNavigator: true).pop();
      await showDialog<void>(
        context: context,
        builder: (context) => _GlobalSearchDetailDialog(detail: detail),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

class _GlobalSearchDetailDialog extends StatelessWidget {
  const _GlobalSearchDetailDialog({required this.detail});

  final GlobalSearchDetail detail;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    final sales = detail.sales;
    final installments = sales
        .expand(
          (sale) => (sale['installments'] as List<dynamic>? ?? const <dynamic>[])
              .map(_asMap),
        )
        .toList();
    final payments = sales
        .expand(
          (sale) => (sale['payments'] as List<dynamic>? ?? const <dynamic>[])
              .map(_asMap),
        )
        .toList();

    return Dialog(
      insetPadding: EdgeInsets.all(compact ? 10 : 18),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: compact ? 420 : 920,
          maxHeight: compact ? MediaQuery.sizeOf(context).height - 20 : 820,
        ),
        child: Padding(
          padding: EdgeInsets.all(compact ? 16 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _fullName(detail.client),
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        DesktopStackedStat(
                          label: 'Cedula',
                          value: detail.client['documentId']?.toString() ?? '-',
                        ),
                        DesktopStackedStat(
                          label: 'Telefono',
                          value: detail.client['phone']?.toString() ?? '-',
                        ),
                        DesktopStackedStat(
                          label: 'Correo',
                          value: detail.client['email']?.toString() ?? '-',
                        ),
                        DesktopStackedStat(
                          label: 'Ventas',
                          value: '${sales.length}',
                        ),
                        DesktopStackedStat(
                          label: 'Cuotas',
                          value: '${installments.length}',
                        ),
                        DesktopStackedStat(
                          label: 'Pagos',
                          value: '${payments.length}',
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    DesktopPlainSection(
                      title: 'Ventas relacionadas',
                      child: sales.isEmpty
                          ? const DesktopEmptyState(
                              icon: Icons.point_of_sale_outlined,
                              title: 'Sin ventas relacionadas',
                              message: 'El cliente aparece en la nube, pero todavia no tiene ventas registradas.',
                            )
                          : Column(
                              children: sales.map((sale) {
                                final product = _readNested(sale, ['product', 'name']) ?? 'Sin solar';
                                final seller = _readNested(sale, ['seller', 'name']) ?? 'Sin vendedor';
                                final status = sale['status']?.toString() ?? '-';
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: DesktopCompactSurface(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            DesktopTag(
                                              label: sale['contractNumber']?.toString() ?? 'Sin contrato',
                                              background: const Color(0xFFEAF0F7),
                                            ),
                                            DesktopTag(
                                              label: status,
                                              background: const Color(0xFFE7F5EF),
                                              foreground: const Color(0xFF2F6F5C),
                                            ),
                                            DesktopTag(
                                              label: _currency.format(_asNum(sale['totalAmount'])),
                                              background: const Color(0xFFF6EFE3),
                                              foreground: const Color(0xFF8C5A2C),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          '$product  •  $seller',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF223048),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'Fecha ${_formatDate(sale['saleDate'])}  •  Saldo ${_currency.format(_asNum(sale['outstandingBalance']))}',
                                          style: const TextStyle(color: Color(0xFF6E7791)),
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          'Cuotas: ${((sale['installments'] as List<dynamic>?) ?? const <dynamic>[]).length}  •  Pagos: ${((sale['payments'] as List<dynamic>?) ?? const <dynamic>[]).length}',
                                          style: const TextStyle(color: Color(0xFF6E7791)),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                    ),
                    const SizedBox(height: 18),
                    DesktopPlainSection(
                      title: 'Historial de pagos',
                      child: payments.isEmpty
                          ? const Text(
                              'No hay pagos registrados para este cliente.',
                              style: TextStyle(color: Color(0xFF6E7791)),
                            )
                          : Column(
                              children: payments.take(30).map((payment) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: DesktopCompactSurface(
                                    child: ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(
                                        _currency.format(_asNum(payment['amount'])),
                                        style: const TextStyle(fontWeight: FontWeight.w800),
                                      ),
                                      subtitle: Text(
                                        '${payment['method'] ?? 'Metodo no indicado'}  •  ${_formatDate(payment['paymentDate'])}',
                                      ),
                                      trailing: Text(
                                        payment['reference']?.toString() ?? '-',
                                        style: const TextStyle(color: Color(0xFF6E7791)),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final NumberFormat _currency = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$ ');

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, val) => MapEntry(key.toString(), val));
  }
  return const <String, dynamic>{};
}

String _fullName(Map<String, dynamic> client) {
  final firstName = client['firstName']?.toString() ?? '';
  final lastName = client['lastName']?.toString() ?? '';
  final fullName = '$firstName $lastName'.trim();
  return fullName.isEmpty ? 'Sin nombre' : fullName;
}

String _matchLabel(Set<String> matchTypes) {
  if (matchTypes.contains('client') && matchTypes.contains('sale')) {
    return 'Cliente y venta';
  }
  if (matchTypes.contains('sale')) {
    return 'Venta o solar';
  }
  return 'Cliente';
}

double _asNum(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

String _formatDate(Object? value) {
  final raw = value?.toString();
  if (raw == null || raw.trim().isEmpty) {
    return 'Sin fecha';
  }
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    return raw;
  }
  return DateFormat('dd/MM/yyyy').format(parsed.toLocal());
}

String? _readNested(Object? value, List<String> keys) {
  Object? current = value;
  for (final key in keys) {
    if (current is! Map) {
      return null;
    }
    current = current[key];
  }
  return current?.toString();
}