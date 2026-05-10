import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:sistema_solares_ui/core/formatters/app_number_formats.dart';
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
  final Set<String> _expandedClientIds = <String>{};
  final Map<String, GlobalSearchDetail> _detailCache =
      <String, GlobalSearchDetail>{};
  final Set<String> _detailLoadingClientIds = <String>{};
  final Map<String, String> _detailErrors = <String, String>{};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _clear() {
    _searchController.clear();
    setState(() {
      _future = null;
      _lastSubmittedQuery = '';
      _expandedClientIds.clear();
      _detailCache.clear();
      _detailLoadingClientIds.clear();
      _detailErrors.clear();
    });
  }

  void _reload() {
    final query = _searchController.text.trim();
    setState(() {
      _lastSubmittedQuery = query;
      _expandedClientIds.clear();
      _detailCache.clear();
      _detailLoadingClientIds.clear();
      _detailErrors.clear();
      _future = query.isEmpty
          ? null
          : GlobalSearchService(context.read<ApiClient>()).search(query);
    });
  }

  Future<void> _toggleExpandedClient(String clientId) async {
    if (clientId.trim().isEmpty) return;

    final shouldExpand = !_expandedClientIds.contains(clientId);
    setState(() {
      if (shouldExpand) {
        _expandedClientIds.add(clientId);
      } else {
        _expandedClientIds.remove(clientId);
      }
    });

    if (!shouldExpand ||
        _detailCache.containsKey(clientId) ||
        _detailLoadingClientIds.contains(clientId)) {
      return;
    }

    setState(() {
      _detailLoadingClientIds.add(clientId);
      _detailErrors.remove(clientId);
    });

    try {
      final detail = await GlobalSearchService(
        context.read<ApiClient>(),
      ).fetchDetail(clientId);
      if (!mounted) return;
      setState(() {
        _detailCache[clientId] = detail;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _detailErrors[clientId] = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _detailLoadingClientIds.remove(clientId);
        });
      }
    }
  }

  Future<void> _retryDetail(String clientId) async {
    setState(() {
      _detailCache.remove(clientId);
      _detailErrors.remove(clientId);
      _expandedClientIds.remove(clientId);
    });
    await _toggleExpandedClient(clientId);
  }

  @override
  Widget build(BuildContext context) {
    final refreshTick = context.select<RealtimeController, int>((realtime) => realtime.refreshTick);
    if (_future != null &&
        _lastSubmittedQuery.isNotEmpty &&
        refreshTick != _lastTick) {
      _lastTick = refreshTick;
      _future = GlobalSearchService(
        context.read<ApiClient>(),
      ).search(_lastSubmittedQuery);
    }

    return DesktopPageScaffold(
      title: 'Buscador global',
      showMobileTitle: false,
      toolbar: DesktopFieldToolbar(
        child: DesktopToolbar(
          expandSearchField: false,
          searchField: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: DesktopSearchField(
                controller: _searchController,
                hintText: 'Nombre, cedula, telefono, contrato o solar',
                onSubmitted: (_) => _reload(),
              ),
            ),
          ),
          actions: [
            OutlinedButton.icon(
              onPressed: _clear,
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
            DesktopToolbarIconAction(
              icon: Icons.cleaning_services_outlined,
              tooltip: 'Limpiar',
              onPressed: _clear,
            ),
            DesktopToolbarIconAction(
              icon: Icons.search_rounded,
              tooltip: 'Buscar',
              tone: DesktopToolbarActionTone.filled,
              onPressed: _reload,
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
            const SizedBox(height: 4),
            Expanded(
              child: DesktopModuleList(
                children: results
                    .map((result) => _buildResultCard(result, compact))
                    .toList(),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildResultCard(GlobalSearchSummary result, bool compact) {
    final client = result.client;
    final fullName = _fullName(client);
    final rawPhone = client['phone']?.toString().trim() ?? '';
    final phone = rawPhone.isEmpty ? 'Sin telefono' : rawPhone;
    final clientId = result.clientId;
    final isExpanded = _expandedClientIds.contains(clientId);
    final detail = _detailCache[clientId];
    final isDetailLoading = _detailLoadingClientIds.contains(clientId);
    final detailError = _detailErrors[clientId];
    final totalOutstanding = result.sales.fold<double>(
      0,
      (total, sale) => total + _asNum(sale['outstandingBalance']),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DesktopCompactSurface(
        child: Padding(
          padding: EdgeInsets.all(compact ? 12 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _toggleExpandedClient(clientId),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: compact ? 16 : 20,
                      backgroundColor: const Color(0xFFEFF3FB),
                      child: Text(
                        fullName.isEmpty ? 'C' : fullName[0].toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xFF223048),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14.6,
                              color: Color(0xFF10263D),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              DesktopTag(
                                label: _matchLabel(result.matchTypes),
                                background: const Color(0xFFEAF0F7),
                              ),
                              DesktopTag(
                                label: phone,
                                background: const Color(0xFFEAF4ED),
                                foreground: const Color(0xFF2F6F5C),
                              ),
                              DesktopTag(
                                label: '${result.sales.length} venta(s)',
                                background: const Color(0xFFF5EEF8),
                                foreground: const Color(0xFF7A4A97),
                              ),
                              DesktopTag(
                                label: _currency.format(totalOutstanding),
                                background: const Color(0xFFF6EFE3),
                                foreground: const Color(0xFF8C5A2C),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F7FB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F1)),
                      ),
                      child: Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: const Color(0xFF173450),
                      ),
                    ),
                  ],
                ),
              ),
              if (isExpanded) ...[
                const SizedBox(height: 14),
                if (isDetailLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (detailError != null)
                  DesktopPageError(
                    message: detailError,
                    onRetry: () => _retryDetail(clientId),
                  )
                else if (detail != null)
                  _InlineClientDetail(detail: detail, compact: compact),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineClientDetail extends StatelessWidget {
  const _InlineClientDetail({required this.detail, required this.compact});

  final GlobalSearchDetail detail;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final sales = detail.sales;
    final installments = sales
        .expand(
          (sale) =>
              (sale['installments'] as List<dynamic>? ?? const <dynamic>[]).map(
                _asMap,
              ),
        )
        .toList();
    final payments = sales
        .expand(
          (sale) => (sale['payments'] as List<dynamic>? ?? const <dynamic>[])
              .map(_asMap),
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
            DesktopStackedStat(label: 'Ventas', value: '${sales.length}'),
            DesktopStackedStat(
              label: 'Cuotas',
              value: '${installments.length}',
            ),
            DesktopStackedStat(label: 'Pagos', value: '${payments.length}'),
          ],
        ),
        const SizedBox(height: 16),
        _InlineDestinationLinks(
          clientId: detail.client['id']?.toString() ?? '',
        ),
        const SizedBox(height: 16),
        DesktopPlainSection(
          title: 'Ventas relacionadas',
          child: sales.isEmpty
              ? const Text(
                  'No hay ventas registradas para este cliente.',
                  style: TextStyle(color: Color(0xFF6E7791)),
                )
              : Column(children: sales.map(_SaleSummaryCard.new).toList()),
        ),
        const SizedBox(height: 16),
        DesktopPlainSection(
          title: 'Historial de pagos',
          child: payments.isEmpty
              ? const Text(
                  'No hay pagos registrados para este cliente.',
                  style: TextStyle(color: Color(0xFF6E7791)),
                )
              : Column(
                  children: payments.take(compact ? 10 : 30).map((payment) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: DesktopCompactSurface(
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
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
    );
  }
}

class _SaleSummaryCard extends StatelessWidget {
  const _SaleSummaryCard(this.sale);

  final Map<String, dynamic> sale;

  @override
  Widget build(BuildContext context) {
    final product =
        _readNested(sale['product'], ['name']) ??
        sale['productName']?.toString() ??
        'Solar no indicado';
    final seller =
        _readNested(sale['seller'], ['fullName']) ??
        _readNested(sale['seller'], ['name']) ??
        sale['sellerName']?.toString() ??
        'Vendedor no indicado';
    final status = sale['status']?.toString() ?? 'Sin estado';
    final installmentsCount =
        ((sale['installments'] as List<dynamic>?) ?? const <dynamic>[]).length;
    final paymentsCount =
        ((sale['payments'] as List<dynamic>?) ?? const <dynamic>[]).length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DesktopCompactSurface(
        child: Padding(
          padding: const EdgeInsets.all(12),
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
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  DesktopTag(
                    label: '$installmentsCount cuota(s)',
                    background: const Color(0xFFF5EEF8),
                    foreground: const Color(0xFF7A4A97),
                  ),
                  DesktopTag(
                    label: '$paymentsCount pago(s)',
                    background: const Color(0xFFEAF4ED),
                    foreground: const Color(0xFF2F6F5C),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineDestinationLinks extends StatelessWidget {
  const _InlineDestinationLinks({required this.clientId});

  final String clientId;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _ArrowRouteButton(
          label: 'Clientes',
          onPressed: () => context.go('/clients'),
        ),
        _ArrowRouteButton(
          label: 'Ventas',
          onPressed: () => context.go('/sales'),
        ),
        _ArrowRouteButton(
          label: 'Pagos',
          onPressed: () => context.go('/payments'),
        ),
      ],
    );
  }
}

class _ArrowRouteButton extends StatelessWidget {
  const _ArrowRouteButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      iconAlignment: IconAlignment.end,
      icon: const Icon(Icons.arrow_forward_rounded, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }
}

final NumberFormat _currency = AppNumberFormats.currency;

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
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
  if (matchTypes.contains('sale')) return 'Venta o solar';
  return 'Cliente';
}

double _asNum(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

String _formatDate(Object? value) {
  final raw = value?.toString();
  if (raw == null || raw.trim().isEmpty) return 'Sin fecha';
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return raw;
  return DateFormat('dd/MM/yyyy').format(parsed.toLocal());
}

String? _readNested(Object? value, List<String> keys) {
  Object? current = value;
  for (final key in keys) {
    if (current is! Map) return null;
    current = current[key];
  }
  return current?.toString();
}


