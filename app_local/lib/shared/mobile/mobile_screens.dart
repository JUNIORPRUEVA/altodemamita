import 'package:flutter/material.dart';

import 'mobile_ui.dart';

/// ============================================================================
/// PANTALLAS COMPARTIDAS DEL LAYOUT COMPACTO (patrón maestro = Ventas)
/// ============================================================================
///
/// Estas piezas se usan en TODOS los módulos (Clientes, Solares, Pagos, Cuotas,
/// Vendedores) para que la PWA se vea uniforme. No contienen lógica de negocio:
/// reciben datos y callbacks.
///
/// El header/título lo aporta el shell móvil (`MobileNavigationShell`), por eso
/// estas vistas NO crean su propia AppBar.

// ══════════════════════════════════════════════════════════════════════════════
// LISTA
// ══════════════════════════════════════════════════════════════════════════════

/// Campo de búsqueda compacto (idéntico al buscador de Ventas).
class MobileSearchRow extends StatelessWidget {
  const MobileSearchRow({
    super.key,
    required this.controller,
    required this.hintText,
    this.onSubmitted,
    this.onClear,
    this.onOpenFilter,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;
  final VoidCallback? onOpenFilter;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 40,
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                final hasText = value.text.trim().isNotEmpty;
                return TextField(
                  controller: controller,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: MobileUi.textPrimary,
                  ),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: hintText,
                    hintStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: MobileUi.textMuted,
                    ),
                    prefixIcon: IconButton(
                      tooltip: 'Buscar',
                      splashRadius: 18,
                      icon: const Icon(
                        Icons.search_rounded,
                        size: 20,
                        color: Color(0xFF5B6B80),
                      ),
                      onPressed: () => onSubmitted?.call(controller.text.trim()),
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 38,
                      minHeight: 38,
                    ),
                    suffixIcon: hasText && onClear != null
                        ? IconButton(
                            tooltip: 'Limpiar',
                            splashRadius: 18,
                            icon: const Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: Color(0xFF5B6B80),
                            ),
                            onPressed: onClear,
                          )
                        : null,
                    suffixIconConstraints: const BoxConstraints(
                      minWidth: 34,
                      minHeight: 34,
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF6F8FB),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(MobileUi.radiusField),
                      borderSide: const BorderSide(color: Color(0xFFD8DFE9)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(MobileUi.radiusField),
                      borderSide: const BorderSide(color: Color(0xFFD8DFE9)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(MobileUi.radiusField),
                      borderSide: const BorderSide(
                        color: MobileUi.primary,
                        width: 1.4,
                      ),
                    ),
                  ),
                  onSubmitted: onSubmitted,
                );
              },
            ),
          ),
        ),
        if (onOpenFilter != null)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: IconButton(
              tooltip: 'Filtros',
              icon: const Icon(Icons.tune_rounded),
              onPressed: onOpenFilter,
            ),
          ),
      ],
    );
  }
}

/// Vista de lista del layout compacto (mismo comportamiento que Ventas:
/// cache-first con refresh no bloqueante, skeleton y estados simples).
class MobileModuleListView<T> extends StatefulWidget {
  const MobileModuleListView({
    super.key,
    required this.searchHint,
    required this.items,
    required this.itemBuilder,
    required this.onSearch,
    required this.onClearSearch,
    required this.onRetry,
    required this.isLoading,
    required this.isRefreshing,
    required this.refreshFailed,
    required this.searchFailed,
    required this.hasVisibleData,
    required this.query,
    this.loadErrorTitle,
    this.emptyTitle = 'Todavía no hay registros',
    this.emptyMessage,
    this.emptyIcon = Icons.inbox_outlined,
    this.emptyActionLabel,
    this.onEmptyAction,
    this.searchEmptyMessage = 'No se encontraron resultados para tu búsqueda.',
    this.fabTooltip,
    this.fabIcon = Icons.add,
    this.onFabPressed,
    this.filterPanel,
    this.chips = const [],
  });

  final String searchHint;
  final List<T> items;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final ValueChanged<String> onSearch;
  final VoidCallback onClearSearch;
  final VoidCallback onRetry;
  final bool isLoading;
  final bool isRefreshing;
  final bool refreshFailed;
  final bool searchFailed;
  final bool hasVisibleData;
  final String query;
  final String? loadErrorTitle;
  final String emptyTitle;
  final String? emptyMessage;
  final IconData emptyIcon;
  final String? emptyActionLabel;
  final VoidCallback? onEmptyAction;
  final String searchEmptyMessage;
  final String? fabTooltip;
  final IconData fabIcon;
  final VoidCallback? onFabPressed;
  final Widget? filterPanel;
  final List<Widget> chips;

  @override
  State<MobileModuleListView<T>> createState() =>
      _MobileModuleListViewState<T>();
}

class _MobileModuleListViewState<T> extends State<MobileModuleListView<T>> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.query;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchController.clear();
    widget.onClearSearch();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MobileUi.background,
      endDrawer: widget.filterPanel,
      body: Column(
        children: [
          Container(
            color: MobileUi.surface,
            padding: const EdgeInsets.fromLTRB(
              10,
              8,
              10,
              8,
            ),
            child: Builder(
              builder: (buttonContext) => MobileSearchRow(
                controller: _searchController,
                hintText: widget.searchHint,
                onSubmitted: widget.onSearch,
                onClear: _clearSearch,
                onOpenFilter: widget.filterPanel == null
                    ? null
                    : () => Scaffold.of(buttonContext).openEndDrawer(),
              ),
            ),
          ),
          if (widget.chips.isNotEmpty)
            Container(
              color: MobileUi.surface,
              padding: const EdgeInsets.only(bottom: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: MobileUi.listPadding,
                ),
                child: Row(
                  children: [
                    for (var index = 0; index < widget.chips.length; index++) ...[
                      if (index > 0) const SizedBox(width: 8),
                      widget.chips[index],
                    ],
                  ],
                ),
              ),
            ),
          if (widget.refreshFailed)
            MobileRefreshFailedBanner(onRetry: widget.onRetry)
          else if (widget.isRefreshing)
            const MobileRefreshingBar(),
          Expanded(child: _buildBody()),
        ],
      ),
      floatingActionButton: widget.onFabPressed == null
          ? null
          : FloatingActionButton(
              tooltip: widget.fabTooltip,
              onPressed: widget.onFabPressed,
              child: Icon(widget.fabIcon),
            ),
    );
  }

  Widget _buildBody() {
    if (widget.loadErrorTitle != null) {
      return MobileSearchFailedView(
        title: widget.loadErrorTitle!,
        onRetry: widget.onRetry,
      );
    }

    if (!widget.hasVisibleData) {
      if (widget.isLoading) {
        return const MobileLoadingView(label: 'Cargando…');
      }
      if (widget.searchFailed) {
        return MobileSearchFailedView(
          title: 'No pudimos completar la búsqueda.',
          message: 'Revisa tu conexión e inténtalo nuevamente.',
          onRetry: widget.onRetry,
        );
      }
      if (widget.query.trim().isNotEmpty) {
        return MobileEmptySearchView(
          message: widget.searchEmptyMessage,
          onClear: _clearSearch,
        );
      }
      return MobileEmptyState(
        title: widget.emptyTitle,
        message: widget.emptyMessage,
        icon: widget.emptyIcon,
        actionLabel: widget.emptyActionLabel,
        onAction: widget.onEmptyAction,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        MobileUi.listPadding,
        8,
        MobileUi.listPadding,
        88,
      ),
      itemCount: widget.items.length,
      separatorBuilder: (_, _) => const SizedBox(height: MobileUi.rowGap),
      itemBuilder: (context, index) =>
          widget.itemBuilder(context, widget.items[index]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// DETALLE (pantalla completa, patrón maestro = detalle de Venta)
// ══════════════════════════════════════════════════════════════════════════════

/// Scaffold de detalle compacto: `[←] Título [⋮]` + scroll vertical completo.
class MobileDetailScaffold extends StatelessWidget {
  const MobileDetailScaffold({
    super.key,
    required this.title,
    required this.children,
    this.menu,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 32),
  });

  final String title;
  final List<Widget> children;
  final Widget? menu;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: const Border(bottom: BorderSide(color: MobileUi.divider)),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: MobileUi.textPrimary,
          ),
        ),
        iconTheme: const IconThemeData(color: MobileUi.textPrimary),
        actions: [
          ?menu,
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: padding,
        children: children,
      ),
    );
  }
}

/// Título de sección (idéntico al del detalle de Venta).
class MobileSectionTitle extends StatelessWidget {
  const MobileSectionTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
      child: Text(
        title.toUpperCase(),
        style: MobileUi.sectionTitle,
      ),
    );
  }
}

/// Par label/valor de una sección de detalle.
class MobileInfoItem {
  const MobileInfoItem(this.label, this.value);

  final String label;
  final String value;
}

/// Fila label/valor (idéntica a la del detalle de Venta).
class MobileInfoRow extends StatelessWidget {
  const MobileInfoRow({
    super.key,
    required this.label,
    required this.value,
    this.showDivider = true,
  });

  final String label;
  final String value;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 4,
                child: Text(label, style: MobileUi.detailLabel),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 5,
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: MobileUi.detailValue,
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          const Divider(
            height: 1,
            thickness: 1,
            color: MobileUi.divider,
            indent: 16,
            endIndent: 16,
          ),
      ],
    );
  }
}

/// Bloque de sección con tarjeta + filas (idéntico al del detalle de Venta).
class MobileSection extends StatelessWidget {
  const MobileSection({
    super.key,
    required this.title,
    required this.rows,
    this.footer,
  });

  final String title;
  final List<MobileInfoItem> rows;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MobileSectionTitle(title),
        Container(
          decoration: mobileCardDecoration(),
          padding: EdgeInsets.symmetric(vertical: rows.isEmpty ? 0 : 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < rows.length; index++)
                MobileInfoRow(
                  label: rows[index].label,
                  value: rows[index].value,
                  showDivider: index != rows.length - 1,
                ),
              ?footer,
            ],
          ),
        ),
      ],
    );
  }
}

/// Tarjeta de identidad del detalle: título grande + subtítulo + chip.
class MobileDetailIdentityCard extends StatelessWidget {
  const MobileDetailIdentityCard({
    super.key,
    required this.title,
    this.subtitle,
    this.chip,
  });

  final String title;
  final String? subtitle;
  final Widget? chip;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: mobileCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: MobileUi.textPrimary,
              height: 1.2,
            ),
          ),
          if ((subtitle ?? '').trim().isNotEmpty || chip != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    (subtitle ?? '').trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF667085),
                    ),
                  ),
                ),
                if (chip != null) ...[
                  const SizedBox(width: 8),
                  Flexible(child: chip!),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Acción del detalle (fila con icono + chevron).
class MobileDetailActionTile extends StatelessWidget {
  const MobileDetailActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = MobileUi.textPrimary,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: MobileUi.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

/// Cargando detalle (dentro de la pantalla, sin bloquear la navegación).
class MobileDetailLoadingView extends StatelessWidget {
  const MobileDetailLoadingView({super.key, this.label = 'Cargando detalle…'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 16),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7494),
            ),
          ),
        ],
      ),
    );
  }
}

/// Error de detalle recuperable (sin detalles técnicos).
class MobileDetailErrorView extends StatelessWidget {
  const MobileDetailErrorView({
    super.key,
    required this.title,
    this.message = 'Revisa tu conexión e inténtalo nuevamente.',
    this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 40,
              color: MobileUi.textMuted,
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: MobileUi.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13.5,
                color: Color(0xFF667085),
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  backgroundColor: MobileUi.primary,
                  minimumSize: const Size(160, 46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Reintentar'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
