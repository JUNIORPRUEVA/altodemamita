import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:sistema_solares_ui/core/formatters/app_number_formats.dart';
import 'package:sistema_solares_ui/core/network/api_client.dart';
import 'package:sistema_solares_ui/core/realtime/realtime_controller.dart';
import 'package:sistema_solares_ui/features/sellers/sellers_service.dart';
import 'package:sistema_solares_ui/shared/desktop_ui.dart';

class SellersScreen extends StatefulWidget {
  const SellersScreen({super.key});

  @override
  State<SellersScreen> createState() => _SellersScreenState();
}

class _SellersScreenState extends State<SellersScreen> {
  final _searchController = TextEditingController();
  Future<SellersPageData>? _future;
  int _lastTick = -1;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() => _future = null);
  }

  @override
  Widget build(BuildContext context) {
    final refreshTick = context.select<RealtimeController, int>((realtime) => realtime.refreshTick);
    if (_future == null || refreshTick != _lastTick) {
      _lastTick = refreshTick;
      _future = SellersService(
        context.read<ApiClient>(),
      ).fetch(search: _searchController.text);
    }

    return FutureBuilder<SellersPageData>(
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

        final data = snapshot.data!;
        final compact = MediaQuery.sizeOf(context).width < 760;
        return DesktopPageScaffold(
          title: 'Vendedores',
          subtitle: compact
              ? null
              : 'Consulta la tabla de vendedores y sus ventas asociadas desde la nube.',
          toolbar: DesktopFieldToolbar(
            child: DesktopToolbar(
              searchField: DesktopSearchField(
                controller: _searchController,
                hintText: 'Buscar por nombre, cedula o telefono',
                onSubmitted: (_) => _reload(),
              ),
              actions: [
                OutlinedButton.icon(
                  onPressed: () {
                    _searchController.clear();
                    _reload();
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
                DesktopToolbarIconAction(
                  icon: Icons.cleaning_services_outlined,
                  tooltip: 'Limpiar',
                  onPressed: () {
                    _searchController.clear();
                    _reload();
                  },
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!compact) ...[
                DesktopInfoStrip(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      DesktopTag(
                        label: 'Total visibles: ${data.total}',
                        background: const Color(0xFFF1F4FA),
                      ),
                      DesktopTag(
                        label: 'Pag. ${data.page}/${data.totalPages}',
                        background: const Color(0xFFEAF0F7),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Expanded(
                child: data.items.isEmpty
                    ? const DesktopEmptyState(
                        icon: Icons.badge_outlined,
                        title: 'No hay vendedores para este filtro',
                        message:
                            'Prueba otra busqueda o espera a la siguiente sincronizacion desde el escritorio.',
                      )
                    : DesktopModuleList(
                        children: data.items.map((item) {
                          final name = item['name']?.toString() ?? 'Sin nombre';
                          final document =
                              item['documentId']?.toString() ?? 'Sin cedula';
                          final phone =
                              item['phone']?.toString() ?? 'Sin telefono';
                          final subtitle = '$document  •  $phone';
                          return DesktopListRow(
                            height: compact ? 62 : 76,
                            onTap: () =>
                                _openDetail(item['id']?.toString() ?? ''),
                            leading: CircleAvatar(
                              radius: compact ? 14 : 22,
                              backgroundColor: const Color(0xFFEAF0F7),
                              child: Text(
                                name.isEmpty ? 'V' : name[0].toUpperCase(),
                                style: const TextStyle(
                                  color: Color(0xFF223048),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            title: Text(
                              name,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: compact ? 12.2 : null,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              subtitle,
                              style: TextStyle(
                                color: const Color(0xFF6E7791),
                                fontSize: compact ? 10.6 : null,
                                height: compact ? 1.0 : null,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: compact
                                ? const Icon(
                                    Icons.chevron_right_rounded,
                                    size: 18,
                                    color: Color(0xFF9AA6B8),
                                  )
                                : const DesktopTag(
                                    label: 'Ver detalle',
                                    background: Color(0xFFF6EFE3),
                                    foreground: Color(0xFF8C5A2C),
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

  Future<void> _openDetail(String id) async {
    if (id.trim().isEmpty) {
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final detail = await SellersService(
        context.read<ApiClient>(),
      ).fetchDetail(id);
      if (!mounted) {
        return;
      }
      Navigator.of(context, rootNavigator: true).pop();
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => _SellerDetailPage(detail: detail),
        ),
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

class _SellerDetailPage extends StatelessWidget {
  const _SellerDetailPage({required this.detail});

  final Map<String, dynamic> detail;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    final sales = (detail['sales'] as List<dynamic>? ?? const <dynamic>[])
        .map(_asMap)
        .toList();
    final totalSold = sales.fold<double>(
      0,
      (sum, sale) => sum + _asNum(sale['totalAmount']),
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF0F3F8),
      appBar: AppBar(
        title: Text(detail['name']?.toString() ?? 'Detalle de vendedor'),
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF173450),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 10 : 18,
                compact ? 10 : 18,
                compact ? 10 : 18,
                compact ? 12 : 18,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  compact
                      ? _SellerCompactHeader(
                          documentId: detail['documentId']?.toString() ?? '-',
                          phone: detail['phone']?.toString() ?? '-',
                          salesCount: sales.length,
                          totalSold: _currency.format(totalSold),
                        )
                      : Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            DesktopStackedStat(
                              label: 'Cedula',
                              value: detail['documentId']?.toString() ?? '-',
                            ),
                            DesktopStackedStat(
                              label: 'Telefono',
                              value: detail['phone']?.toString() ?? '-',
                            ),
                            DesktopStackedStat(
                              label: 'Ventas',
                              value: '${sales.length}',
                            ),
                            DesktopStackedStat(
                              label: 'Monto vendido',
                              value: _currency.format(totalSold),
                            ),
                          ],
                        ),
                  SizedBox(height: compact ? 14 : 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ventas asociadas',
                          style: TextStyle(
                            fontSize: compact ? 16 : 20,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF173450),
                          ),
                        ),
                        SizedBox(height: compact ? 10 : 14),
                        Expanded(
                          child: sales.isEmpty
                              ? const DesktopEmptyState(
                                  icon: Icons.point_of_sale_outlined,
                                  title: 'Sin ventas asociadas',
                                  message:
                                      'Este vendedor todavia no tiene ventas visibles en la nube.',
                                )
                              : ListView.separated(
                                  itemCount: sales.length,
                                  separatorBuilder: (_, _) => Divider(
                                    height: compact ? 14 : 18,
                                    color: const Color(0xFFE6EBF2),
                                  ),
                                  itemBuilder: (context, index) {
                                    final sale = sales[index];
                                    final client = _fullName(
                                      _asMap(sale['client']),
                                    );
                                    final product =
                                        _readNested(sale, [
                                          'product',
                                          'name',
                                        ]) ??
                                        'Sin solar';
                                    final meta = compact
                                        ? '$product  •  ${_formatDate(sale['saleDate'])}'
                                        : '$product  •  ${sale['contractNumber'] ?? 'Sin contrato'}  •  ${_formatDate(sale['saleDate'])}';
                                    return Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: compact ? 2 : 4,
                                        vertical: compact ? 2 : 4,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  client,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: compact
                                                        ? 12.8
                                                        : 14,
                                                  ),
                                                ),
                                                const SizedBox(height: 3),
                                                Text(
                                                  meta,
                                                  maxLines: compact ? 2 : 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: const Color(
                                                      0xFF6E7791,
                                                    ),
                                                    height: compact
                                                        ? 1.15
                                                        : 1.3,
                                                    fontSize: compact
                                                        ? 10.8
                                                        : 12.5,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                _currency.format(
                                                  _asNum(sale['totalAmount']),
                                                ),
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  color: const Color(
                                                    0xFF8C5A2C,
                                                  ),
                                                  fontSize: compact
                                                      ? 12.2
                                                      : 13.5,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                sale['status']?.toString() ??
                                                    '-',
                                                style: TextStyle(
                                                  color: const Color(
                                                    0xFF6E7791,
                                                  ),
                                                  fontSize: compact ? 10.6 : 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SellerCompactHeader extends StatelessWidget {
  const _SellerCompactHeader({
    required this.documentId,
    required this.phone,
    required this.salesCount,
    required this.totalSold,
  });

  final String documentId;
  final String phone;
  final int salesCount;
  final String totalSold;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$documentId  •  $phone',
          style: const TextStyle(
            fontSize: 11.2,
            fontWeight: FontWeight.w700,
            color: Color(0xFF6E7791),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            DesktopTag(
              label: '$salesCount ventas',
              background: const Color(0xFFF1F4FA),
            ),
            DesktopTag(
              label: totalSold,
              background: const Color(0xFFF6EFE3),
              foreground: const Color(0xFF8C5A2C),
            ),
          ],
        ),
      ],
    );
  }
}

final NumberFormat _currency = AppNumberFormats.currency;

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
  return fullName.isEmpty ? 'Sin cliente' : fullName;
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


