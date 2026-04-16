import 'package:flutter/material.dart';

import '../../../core/resilience/friendly_error_messages.dart';
import '../../../shared/widgets/base_layout.dart';
import '../../clients/data/client_repository.dart';
import '../../installments/data/installments_repository.dart';
import '../../lots/data/lot_repository.dart';
import '../../sales/data/sales_repository.dart';
import '../data/global_search_repository.dart';
import '../domain/search_result.dart';
import 'search_result_dialog.dart';

class GlobalSearchPage extends StatefulWidget {
  const GlobalSearchPage({
    super.key,
    ClientRepository? clientRepository,
    LotRepository? lotRepository,
    SalesRepository? salesRepository,
    InstallmentsRepository? installmentsRepository,
    this.onOpenClients,
    this.onOpenLots,
    this.onOpenSales,
    this.onOpenInstallments,
    this.onOpenPayments,
  }) : _clientRepository = clientRepository,
       _lotRepository = lotRepository,
       _salesRepository = salesRepository,
       _installmentsRepository = installmentsRepository;

  final ClientRepository? _clientRepository;
  final LotRepository? _lotRepository;
  final SalesRepository? _salesRepository;
  final InstallmentsRepository? _installmentsRepository;
  final VoidCallback? onOpenClients;
  final VoidCallback? onOpenLots;
  final VoidCallback? onOpenSales;
  final void Function(int? saleId)? onOpenInstallments;
  final void Function(int? saleId)? onOpenPayments;

  @override
  State<GlobalSearchPage> createState() => _GlobalSearchPageState();
}

class _GlobalSearchPageState extends State<GlobalSearchPage> {
  late final TextEditingController _searchController;
  late final GlobalSearchRepository _searchRepository;

  bool _isLoading = false;
  String _query = '';
  List<GlobalSearchResult> _results = const [];

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchRepository = GlobalSearchRepository(
      clientRepository: widget._clientRepository,
      lotRepository: widget._lotRepository,
      salesRepository: widget._salesRepository,
      installmentsRepository: widget._installmentsRepository,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BaseLayout(
      title: 'Búsqueda Global',
      child: Column(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 980;

                  final searchField = TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText:
                          'Nombre, cédula, teléfono del cliente o número de solar',
                      prefixIcon: Icon(Icons.search),
                      helperText: 'Ejemplo: Juan Pérez, 123-4567890 o M5-S10',
                    ),
                    onSubmitted: (_) => _search(),
                    onChanged: (_) => setState(() {}),
                  );

                  final actions = Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: _search,
                        icon: const Icon(Icons.search_outlined),
                        label: const Text('Buscar'),
                      ),
                      if (_searchController.text.isNotEmpty)
                        OutlinedButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _query = '';
                              _results = [];
                            });
                          },
                          child: const Text('Limpiar'),
                        ),
                    ],
                  );

                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        searchField,
                        const SizedBox(height: 16),
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
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: _buildResults(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_query.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.travel_explore_outlined,
                size: 52,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Ingresa un término de búsqueda para comenzar.',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'Puedes buscar clientes, solares, ventas y cuotas desde una sola pantalla.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No se encontraron resultados para "$_query"',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final result = _results[index];
        return _buildResultCard(context, result);
      },
    );
  }

  Widget _buildResultCard(BuildContext context, GlobalSearchResult result) {
    final hasPendingInstallments = result.pendingInstallmentsCount > 0;
    final latestSale = result.relatedSales.isNotEmpty
        ? result.relatedSales.first
        : null;

    return Card(
      child: InkWell(
        onTap: () => _showDetailDialog(result),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Encabezado con nombre/código
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          result.displayName,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          result.displaySubtitle,
                          style: Theme.of(context).textTheme.labelSmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (hasPendingInstallments)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange),
                      ),
                      child: Text(
                        'Pendiente: RD\$${result.totalPendingAmount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // Info rápida
              Row(
                children: [
                  if (result.relatedSales.isNotEmpty) ...[
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            size: 16,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${result.relatedSales.length} venta(s)',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (result.relatedInstallments.isNotEmpty) ...[
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            Icons.event_note_outlined,
                            size: 16,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${result.relatedInstallments.length} cuota(s)',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),

              if (latestSale != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Última venta del cliente',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildJumpLine(
                        context,
                        label: 'Solar',
                        value: _buildLotCode(latestSale),
                        tooltip: 'Ir a Solares',
                        onTap: widget.onOpenLots,
                      ),
                      _buildJumpLine(
                        context,
                        label: 'Vendedor',
                        value: _readText(latestSale['vendedor_nombre']),
                        tooltip: 'Ir a Ventas',
                        onTap: widget.onOpenSales,
                      ),
                      _buildJumpLine(
                        context,
                        label: 'Usuario creador',
                        value: _readText(latestSale['usuario_nombre']),
                        tooltip: 'Ir a Ventas',
                        onTap: widget.onOpenSales,
                      ),
                      _buildJumpLine(
                        context,
                        label: 'Fecha y hora',
                        value: _formatDateTime(latestSale['fecha_venta']),
                        tooltip: 'Ir a Ventas',
                        onTap: widget.onOpenSales,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          _buildMiniAction(
                            context,
                            icon: Icons.person_outline,
                            label: 'Cliente',
                            tooltip: 'Ir a Clientes',
                            onTap: widget.onOpenClients,
                          ),
                          _buildMiniAction(
                            context,
                            icon: Icons.point_of_sale_outlined,
                            label: 'Ventas',
                            tooltip: 'Ir a Ventas',
                            onTap: widget.onOpenSales,
                          ),
                          _buildMiniAction(
                            context,
                            icon: Icons.event_note_outlined,
                            label: 'Cuotas',
                            tooltip: 'Ir a Cuotas',
                            onTap: () => widget.onOpenInstallments?.call(
                              _saleIdFromMap(latestSale),
                            ),
                          ),
                          _buildMiniAction(
                            context,
                            icon: Icons.payments_outlined,
                            label: 'Prestamo',
                            tooltip: 'Ir a Pagos/Préstamos',
                            onTap: () => widget.onOpenPayments?.call(
                              _saleIdFromMap(latestSale),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _showDetailDialog(result),
                  icon: const Icon(Icons.open_in_new_outlined, size: 18),
                  label: const Text('Ver detalles'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _query = '';
        _results = [];
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _query = query;
    });

    try {
      final results = await _searchRepository.search(query);

      if (!mounted) {
        return;
      }

      setState(() {
        _results = results;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      FriendlyErrorMessages.forOperation(
        'realizar la búsqueda',
        error,
        module: 'busqueda global',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showDetailDialog(GlobalSearchResult result) async {
    await showDialog(
      context: context,
      builder: (context) => SearchResultDialog(
        result: result,
        onOpenClients: widget.onOpenClients,
        onOpenLots: widget.onOpenLots,
        onOpenSales: widget.onOpenSales,
        onOpenInstallments: widget.onOpenInstallments,
        onOpenPayments: widget.onOpenPayments,
      ),
    );
  }

  Widget _buildJumpLine(
    BuildContext context, {
    required String label,
    required String value,
    required String tooltip,
    VoidCallback? onTap,
  }) {
    final textStyle = Theme.of(context).textTheme.labelMedium;
    return Row(
      children: [
        Expanded(
          child: Text(
            '$label: $value',
            style: textStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (onTap != null)
          Opacity(
            opacity: 0.58,
            child: IconButton(
              onPressed: onTap,
              tooltip: tooltip,
              icon: const Icon(Icons.open_in_new_outlined, size: 15),
              visualDensity: VisualDensity.compact,
              splashRadius: 16,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 20, height: 20),
            ),
          ),
      ],
    );
  }

  Widget _buildMiniAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String tooltip,
    VoidCallback? onTap,
  }) {
    final isEnabled = onTap != null;
    return Opacity(
      opacity: isEnabled ? 0.62 : 0.35,
      child: Tooltip(
        message: tooltip,
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 14),
          label: Text(label, style: const TextStyle(fontSize: 11)),
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          ),
        ),
      ),
    );
  }

  int? _saleIdFromMap(Map<String, dynamic> sale) {
    final raw = sale['id'];
    if (raw is int) {
      return raw;
    }
    return int.tryParse(raw?.toString() ?? '');
  }

  String _readText(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? 'No especificado' : text;
  }

  String _buildLotCode(Map<String, dynamic> sale) {
    final block = sale['manzana_numero']?.toString() ?? '';
    final lot = sale['solar_numero']?.toString() ?? '';
    if (block.isNotEmpty || lot.isNotEmpty) {
      return 'M$block-S$lot';
    }

    final lotId = sale['solar_id']?.toString() ?? '';
    return lotId.isEmpty ? 'No especificado' : 'Solar #$lotId';
  }

  String _formatDateTime(Object? value) {
    final raw = value?.toString();
    if (raw == null || raw.isEmpty) {
      return 'No especificada';
    }

    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      return raw;
    }

    final day = parsed.day.toString().padLeft(2, '0');
    final month = parsed.month.toString().padLeft(2, '0');
    final year = parsed.year.toString().padLeft(4, '0');
    final hour = parsed.hour.toString().padLeft(2, '0');
    final minute = parsed.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }
}
