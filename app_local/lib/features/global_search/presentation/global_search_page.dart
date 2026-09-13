import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/responsive/app_breakpoints.dart';
import '../../../core/resilience/friendly_error_messages.dart';
import '../../../core/utils/dominican_formatters.dart';
import '../../../shared/widgets/base_layout.dart';
import '../../clients/data/client_repository.dart';
import '../../installments/data/installments_repository.dart';
import '../../lots/data/lot_repository.dart';
import '../../sales/data/sales_repository.dart';
import '../data/global_search_repository.dart';
import '../domain/search_result.dart';
import 'global_search_mobile.dart';
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
  late final FocusNode _searchFocusNode;
  late final GlobalSearchRepository _searchRepository;

  bool _isLoading = false;
  bool _searchFailed = false;
  String _query = '';
  List<GlobalSearchResult> _results = const [];
  int _searchGeneration = 0;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode();
    _searchRepository = GlobalSearchRepository(
      clientRepository: widget._clientRepository,
      lotRepository: widget._lotRepository,
      salesRepository: widget._salesRepository,
      installmentsRepository: widget._installmentsRepository,
    );
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Layout compacto (PWA / móvil / tableta): buscador en una sola linea y
    // detalle a pantalla completa. El escritorio (>=1024 px) no cambia.
    if (AppBreakpoints.usesCompactNavigation(context)) {
      return GlobalSearchMobileView(
        controller: _searchController,
        query: _query,
        results: _results,
        isLoading: _isLoading,
        searchFailed: _searchFailed,
        onSearch: _search,
        onClear: _clearSearch,
        onRetry: _search,
        onOpenClients: widget.onOpenClients,
        onOpenLots: widget.onOpenLots,
        onOpenSales: widget.onOpenSales,
        onOpenInstallments: widget.onOpenInstallments,
        onOpenPayments: widget.onOpenPayments,
      );
    }

    return BaseLayout(title: 'Búsqueda Global', child: _buildDesktopView());
  }

  Widget _buildDesktopView() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasQuery = _query.isNotEmpty;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () {
          _searchFocusNode.requestFocus();
        },
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_searchController.text.isNotEmpty || _query.isNotEmpty) {
            _clearSearch();
            _searchFocusNode.requestFocus();
            return;
          }
          _searchFocusNode.unfocus();
        },
      },
      child: Focus(
        autofocus: true,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorScheme.surface,
                colorScheme.secondaryContainer.withValues(alpha: 0.18),
                theme.scaffoldBackgroundColor,
              ],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: -90,
                right: -50,
                child: _buildDesktopGlow(
                  colorScheme.primary.withValues(alpha: 0.10),
                  280,
                ),
              ),
              Positioned(
                left: -80,
                bottom: -120,
                child: _buildDesktopGlow(
                  colorScheme.secondary.withValues(alpha: 0.12),
                  320,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      padding: EdgeInsets.only(top: hasQuery ? 0 : 68),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: hasQuery ? 1080 : 860,
                          ),
                          child: _buildDesktopSearchPanel(compact: hasQuery),
                        ),
                      ),
                    ),
                    if (hasQuery) ...[
                      const SizedBox(height: 18),
                      Expanded(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1180),
                            child: _buildDesktopResultsPanel(),
                          ),
                        ),
                      ),
                    ] else
                      const Spacer(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopGlow(Color color, double size) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(color: color, blurRadius: 70, spreadRadius: 34),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopSearchPanel({required bool compact}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      color: colorScheme.surface.withValues(alpha: 0.94),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compact ? 22 : 28),
        side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.68)),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 22 : 34),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!compact) ...[
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.16),
                  ),
                ),
                child: Icon(
                  Icons.travel_explore_rounded,
                  color: colorScheme.primary,
                  size: 30,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Encuentra lo que necesitas',
                style: theme.textTheme.headlineSmall?.copyWith(fontSize: 30),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Busca clientes, solares, ventas, cuotas y pagos desde un solo lugar.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 26),
            ],
            Row(
              children: [
                Expanded(child: _buildDesktopSearchField()),
                const SizedBox(width: 12),
                SizedBox(
                  height: 62,
                  child: FilledButton.icon(
                    onPressed: _search,
                    icon: const Icon(Icons.search_rounded),
                    label: const Text('Buscar'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: const [
                _DesktopSearchChip(
                  icon: Icons.person_outline,
                  label: 'Clientes',
                ),
                _DesktopSearchChip(icon: Icons.map_outlined, label: 'Solares'),
                _DesktopSearchChip(
                  icon: Icons.receipt_long_outlined,
                  label: 'Ventas',
                ),
                _DesktopSearchChip(
                  icon: Icons.event_note_outlined,
                  label: 'Cuotas',
                ),
                _DesktopSearchChip(
                  icon: Icons.payments_outlined,
                  label: 'Pagos',
                ),
              ],
            ),
            if (!compact) ...[
              const SizedBox(height: 16),
              Text(
                'Ctrl + K enfoca el buscador · Esc limpia la búsqueda',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopSearchField() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.08),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: TextField(
        focusNode: _searchFocusNode,
        controller: _searchController,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          hintText: 'Buscar cliente, cédula, teléfono, solar, venta o cuota...',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Limpiar',
                  onPressed: _clearSearch,
                  icon: const Icon(Icons.close_rounded),
                ),
          filled: true,
          fillColor: colorScheme.surface,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 21,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: colorScheme.outline),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: colorScheme.outline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
          ),
        ),
        onSubmitted: (_) => _search(),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _buildDesktopResultsPanel() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      color: colorScheme.surface.withValues(alpha: 0.96),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.72)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.manage_search_rounded, color: colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _results.isEmpty
                        ? 'Resultados de búsqueda'
                        : '${_results.length} resultado(s) encontrados',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (_isLoading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(child: _buildResults()),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_isLoading && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_searchFailed) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 46,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 14),
              Text(
                'No pudimos completar la búsqueda.',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Revisa la conexión e intenta nuevamente.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _search,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
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
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 48,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                'No se encontraron resultados',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Prueba con otro nombre, cédula, teléfono o código de solar.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        if (_isLoading) const LinearProgressIndicator(minHeight: 3),
        Expanded(
          child: ListView.separated(
            itemCount: _results.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final result = _results[index];
              return _buildResultCard(context, result);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildResultCard(BuildContext context, GlobalSearchResult result) {
    final hasPendingInstallments = result.pendingInstallmentsCount > 0;
    final latestSale = result.relatedSales.isNotEmpty
        ? result.relatedSales.first
        : null;

    return Card(
      child: InkWell(
        onTap: () => _openDetail(result),
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
                        'Pendiente: ${formatRdMoney(result.totalPendingAmount)}',
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
                  onPressed: () => _openDetail(result),
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

  void _clearSearch() {
    _searchController.clear();
    _searchGeneration++;
    setState(() {
      _query = '';
      _results = [];
      _searchFailed = false;
    });
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      _clearSearch();
      return;
    }

    final generation = ++_searchGeneration;
    setState(() {
      _isLoading = true;
      _searchFailed = false;
      _query = query;
    });

    try {
      final results = await _searchRepository.search(query);

      if (!mounted || generation != _searchGeneration) {
        return;
      }

      setState(() {
        _results = results;
      });
    } catch (error) {
      if (!mounted || generation != _searchGeneration) {
        return;
      }
      FriendlyErrorMessages.forOperation(
        'realizar la búsqueda',
        error,
        module: 'busqueda global',
      );
      setState(() {
        _searchFailed = true;
      });
    } finally {
      if (mounted && generation == _searchGeneration) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Abre el detalle del resultado.
  ///
  /// En compacto (PWA / movil / tableta) empuja una PANTALLA COMPLETA: el
  /// dialogo quedaba como una columna angosta flotante en pantallas pequenas.
  /// En escritorio se conserva el dialogo actual.
  Future<void> _openDetail(GlobalSearchResult result) async {
    if (AppBreakpoints.usesCompactNavigation(context)) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SearchResultDetailPage(
            result: result,
            onOpenClients: widget.onOpenClients,
            onOpenLots: widget.onOpenLots,
            onOpenSales: widget.onOpenSales,
            onOpenInstallments: widget.onOpenInstallments,
            onOpenPayments: widget.onOpenPayments,
          ),
        ),
      );
      return;
    }

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

    // Sin datos de manzana/solar no se expone el id interno del solar.
    return 'No especificado';
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

class _DesktopSearchChip extends StatelessWidget {
  const _DesktopSearchChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: colorScheme.secondary.withValues(alpha: 0.16),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colorScheme.secondary),
          const SizedBox(width: 7),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
