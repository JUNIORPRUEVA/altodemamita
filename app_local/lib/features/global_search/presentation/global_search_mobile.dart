import 'package:flutter/material.dart';

import '../../../shared/mobile/mobile_screens.dart';
import '../../../shared/mobile/mobile_ui.dart';
import '../../installments/domain/installment_detail.dart';
import '../../installments/presentation/installments_mobile.dart';
import '../domain/search_result.dart';

/// ============================================================================
/// BUSCADOR — LAYOUT COMPACTO (PWA / móvil / tableta)
/// ============================================================================
///
/// Sigue el patrón visual maestro aprobado en Ventas mobile:
///
/// - **Buscador superior**: una sola línea, lupa DENTRO del campo y acción de
///   limpiar alineada a la derecha (widget compartido [MobileSearchRow]).
/// - **Lista de resultados**: tarjetas ligeras, espaciado uniforme, jerarquía
///   clara (nombre → detalle → monto pendiente) y menú `⋮` para el resto de
///   acciones.
/// - **Detalle**: PANTALLA COMPLETA vía `Navigator.push` con secciones
///   ordenadas. Nunca modal/columna angosta flotante.
///
/// Reglas de producto que se respetan aquí:
/// - NUNCA se muestran identificadores técnicos (ID local, sync id, UUID,
///   versiones, ids remotos): solo información entendible para el cliente.
/// - Los montos se ven COMPLETOS con separador de miles (`RD$951,537.38`).
/// - No hay consultas aquí: el resultado ya viene cargado por el repositorio,
///   así que la navegación es instantánea (la carga ocurre dentro de cada
///   pantalla destino).
///
/// No contiene lógica de negocio: recibe datos y callbacks.
class GlobalSearchMobileView extends StatelessWidget {
  const GlobalSearchMobileView({
    super.key,
    required this.controller,
    required this.query,
    required this.results,
    required this.isLoading,
    required this.searchFailed,
    required this.onSearch,
    required this.onClear,
    required this.onRetry,
    this.onOpenClients,
    this.onOpenLots,
    this.onOpenSales,
    this.onOpenInstallments,
    this.onOpenPayments,
  });

  final TextEditingController controller;
  final String query;
  final List<GlobalSearchResult> results;
  final bool isLoading;
  final bool searchFailed;

  /// Ejecuta la búsqueda con el texto actual del campo.
  final VoidCallback onSearch;

  /// Limpia el campo y los resultados.
  final VoidCallback onClear;

  /// Reintenta la última búsqueda.
  final VoidCallback onRetry;

  final VoidCallback? onOpenClients;
  final VoidCallback? onOpenLots;
  final VoidCallback? onOpenSales;
  final void Function(int? saleId)? onOpenInstallments;
  final void Function(int? saleId)? onOpenPayments;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MobileUi.background,
      body: Column(
        children: [
          _buildSearchHeader(),
          Expanded(child: _buildResults(context)),
        ],
      ),
    );
  }

  Widget _buildSearchHeader() {
    return Container(
      decoration: const BoxDecoration(
        color: MobileUi.surface,
        border: Border(bottom: BorderSide(color: MobileUi.divider)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(MobileUi.radiusField),
              boxShadow: [
                BoxShadow(
                  color: MobileUi.primary.withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: SizedBox(
              height: 50,
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) {
                  final hasText = value.text.trim().isNotEmpty;
                  return TextField(
                    controller: controller,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: MobileUi.textPrimary,
                    ),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Buscar cliente, cédula, teléfono o solar...',
                      hintStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: MobileUi.textMuted,
                      ),
                      prefixIcon: IconButton(
                        tooltip: 'Buscar',
                        splashRadius: 20,
                        icon: const Icon(
                          Icons.search_rounded,
                          size: 22,
                          color: MobileUi.primary,
                        ),
                        onPressed: () => onSearch(),
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                      suffixIcon: hasText
                          ? IconButton(
                              tooltip: 'Limpiar',
                              splashRadius: 20,
                              icon: const Icon(
                                Icons.close_rounded,
                                size: 20,
                                color: MobileUi.textSecondary,
                              ),
                              onPressed: onClear,
                            )
                          : null,
                      suffixIconConstraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFD),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          MobileUi.radiusField,
                        ),
                        borderSide: const BorderSide(color: Color(0xFFD8DFE9)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          MobileUi.radiusField,
                        ),
                        borderSide: const BorderSide(color: Color(0xFFD8DFE9)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          MobileUi.radiusField,
                        ),
                        borderSide: const BorderSide(
                          color: MobileUi.primary,
                          width: 1.6,
                        ),
                      ),
                    ),
                    onSubmitted: (_) => onSearch(),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              _SearchScopeChip(icon: Icons.person_outline, label: 'Clientes'),
              _SearchScopeChip(icon: Icons.map_outlined, label: 'Solares'),
              _SearchScopeChip(
                icon: Icons.receipt_long_outlined,
                label: 'Ventas',
              ),
              _SearchScopeChip(
                icon: Icons.event_note_outlined,
                label: 'Cuotas',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResults(BuildContext context) {
    if (searchFailed) {
      return MobileSearchFailedView(
        title: 'No pudimos completar la búsqueda.',
        onRetry: onRetry,
      );
    }

    if (query.trim().isEmpty) {
      return const _GlobalSearchEmptyHero();
    }

    if (isLoading && results.isEmpty) {
      return const MobileLoadingView(label: 'Buscando…');
    }

    if (results.isEmpty) {
      return MobileEmptySearchView(
        message: 'No hay resultados para "$query".',
        onClear: onClear,
      );
    }

    return Column(
      children: [
        if (isLoading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              MobileUi.listPadding,
              10,
              MobileUi.listPadding,
              28,
            ),
            itemCount: results.length,
            separatorBuilder: (_, _) => const SizedBox(height: MobileUi.rowGap),
            itemBuilder: (context, index) =>
                _buildResultCard(context, results[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildResultCard(BuildContext context, GlobalSearchResult result) {
    final pending = result.totalPendingAmount;
    final saleId = _primarySaleId(result);

    final menuItems = <PopupMenuEntry<_ResultAction>>[
      if (result.client != null && onOpenClients != null)
        const PopupMenuItem<_ResultAction>(
          value: _ResultAction.clients,
          child: Text('Ver cliente'),
        ),
      if (result.lot != null && onOpenLots != null)
        const PopupMenuItem<_ResultAction>(
          value: _ResultAction.lots,
          child: Text('Ver solar'),
        ),
      if (result.relatedSales.isNotEmpty && onOpenSales != null)
        const PopupMenuItem<_ResultAction>(
          value: _ResultAction.sales,
          child: Text('Ver ventas'),
        ),
      if (saleId != null && onOpenInstallments != null)
        const PopupMenuItem<_ResultAction>(
          value: _ResultAction.installments,
          child: Text('Ver cuotas'),
        ),
      if (saleId != null && onOpenPayments != null)
        const PopupMenuItem<_ResultAction>(
          value: _ResultAction.payments,
          child: Text('Ver pagos'),
        ),
    ];

    return Material(
      color: MobileUi.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MobileUi.radiusCard),
        side: const BorderSide(color: MobileUi.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openDetail(context, result),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MobileInitialAvatar(name: result.displayName, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            result.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: MobileUi.itemTitle,
                          ),
                        ),
                        if (menuItems.isNotEmpty)
                          MobileRowMenu<_ResultAction>(
                            itemBuilder: (_) => menuItems,
                            onSelected: (action) =>
                                _runAction(context, action, result),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _cardSubtitle(result),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MobileUi.itemSubtitle,
                    ),
                    const SizedBox(height: 6),
                    if (pending > 0)
                      Row(
                        children: [
                          const Text('Pendiente', style: MobileUi.amountLabel),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              MobileUi.money(pending),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: MobileUi.amountSmall,
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        _cardMeta(result),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MobileUi.itemMeta,
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

  /// Abre el detalle en PANTALLA COMPLETA sin esperar ninguna carga.
  void _openDetail(BuildContext context, GlobalSearchResult result) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SearchResultDetailPage(
          result: result,
          onOpenClients: onOpenClients,
          onOpenLots: onOpenLots,
          onOpenSales: onOpenSales,
          onOpenInstallments: onOpenInstallments,
          onOpenPayments: onOpenPayments,
        ),
      ),
    );
  }

  void _runAction(
    BuildContext context,
    _ResultAction action,
    GlobalSearchResult result,
  ) {
    final saleId = _primarySaleId(result);
    switch (action) {
      case _ResultAction.clients:
        onOpenClients?.call();
      case _ResultAction.lots:
        onOpenLots?.call();
      case _ResultAction.sales:
        onOpenSales?.call();
      case _ResultAction.installments:
        onOpenInstallments?.call(saleId);
      case _ResultAction.payments:
        onOpenPayments?.call(saleId);
    }
  }

  String _cardSubtitle(GlobalSearchResult result) {
    final client = result.client;
    if (client != null) {
      final document = client.documentId.trim();
      return document.isEmpty ? 'Cliente' : 'Cédula: $document';
    }
    final lot = result.lot;
    if (lot != null) {
      return 'Manzana ${lot.blockNumber} · Solar ${lot.lotNumber}';
    }
    return 'Resultado';
  }

  String _cardMeta(GlobalSearchResult result) {
    final parts = <String>[];
    if (result.relatedSales.isNotEmpty) {
      parts.add('${result.relatedSales.length} venta(s)');
    }
    if (result.relatedInstallments.isNotEmpty) {
      parts.add('${result.relatedInstallments.length} cuota(s)');
    }
    if (result.relatedPayments.isNotEmpty) {
      parts.add('${result.relatedPayments.length} pago(s)');
    }
    return parts.isEmpty ? 'Sin movimientos registrados' : parts.join(' · ');
  }
}

class _SearchScopeChip extends StatelessWidget {
  const _SearchScopeChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: MobileUi.primarySoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD6E4F2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: MobileUi.primary),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: MobileUi.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlobalSearchEmptyHero extends StatelessWidget {
  const _GlobalSearchEmptyHero();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 34),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  color: const Color(0xFFA7F3D0),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: MobileUi.primary.withValues(alpha: 0.08),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.manage_search_rounded,
                  size: 36,
                  color: MobileUi.primary,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Busca clientes, solares, ventas y cuotas',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  height: 1.18,
                  fontWeight: FontWeight.w900,
                  color: MobileUi.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Escribe un nombre, cédula, teléfono o número de solar.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                  color: MobileUi.textSecondary,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: MobileUi.surface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: MobileUi.border),
                ),
                child: const Text(
                  'Toca el campo superior para empezar',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: MobileUi.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ResultAction { clients, lots, sales, installments, payments }

enum _DetailJump { clients, lots }

/// ============================================================================
/// DETALLE DEL RESULTADO — PANTALLA COMPLETA
/// ============================================================================
///
/// Se abre con `Navigator.push` ocupando todo el viewport (`SafeArea` + scroll
/// vertical), nunca como diálogo angosto. La información se agrupa por
/// secciones y no se muestra ningún identificador técnico.
class SearchResultDetailPage extends StatelessWidget {
  const SearchResultDetailPage({
    super.key,
    required this.result,
    this.onOpenClients,
    this.onOpenLots,
    this.onOpenSales,
    this.onOpenInstallments,
    this.onOpenPayments,
  });

  final GlobalSearchResult result;
  final VoidCallback? onOpenClients;
  final VoidCallback? onOpenLots;
  final VoidCallback? onOpenSales;
  final void Function(int? saleId)? onOpenInstallments;
  final void Function(int? saleId)? onOpenPayments;

  /// Etiqueta visible del módulo.
  static const String title = 'Detalle';

  @override
  Widget build(BuildContext context) {
    final jumps = <PopupMenuEntry<_DetailJump>>[
      if (result.client != null && onOpenClients != null)
        const PopupMenuItem<_DetailJump>(
          value: _DetailJump.clients,
          child: Text('Ver cliente'),
        ),
      if (result.lot != null && onOpenLots != null)
        const PopupMenuItem<_DetailJump>(
          value: _DetailJump.lots,
          child: Text('Ver solar'),
        ),
    ];

    return MobileDetailScaffold(
      title: title,
      menu: jumps.isEmpty
          ? null
          : PopupMenuButton<_DetailJump>(
              tooltip: 'Acciones',
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (value) => switch (value) {
                _DetailJump.clients => _openModule(context, onOpenClients),
                _DetailJump.lots => _openModule(context, onOpenLots),
              },
              itemBuilder: (_) => jumps,
            ),
      children: [
        MobileDetailIdentityCard(
          title: result.displayName,
          subtitle: _identitySubtitle(),
          chip: _heroChip(),
        ),
        const SizedBox(height: 18),
        ..._buildClientSection(),
        ..._buildLotSection(),
        ..._buildSaleSections(),
        ..._buildInstallmentsSection(),
        ..._buildPaymentsSection(),
        ..._buildAccessSection(context),
        const SizedBox(height: 8),
      ],
    );
  }

  // ── Secciones ──────────────────────────────────────────────────────────────

  List<Widget> _buildClientSection() {
    final client = result.client;
    if (client == null) {
      return const [];
    }

    // El nombre y la cédula ya están en la tarjeta de identidad: aquí solo van
    // los datos de contacto para no repetir información.
    final rows = <MobileInfoItem>[
      if ((client.phone ?? '').trim().isNotEmpty)
        MobileInfoItem('Teléfono', client.phone!.trim()),
      if ((client.address ?? '').trim().isNotEmpty)
        MobileInfoItem('Dirección', client.address!.trim()),
    ];

    if (rows.isEmpty) {
      return const [];
    }

    return [
      MobileSection(title: 'Datos de contacto', rows: rows),
      const SizedBox(height: 18),
    ];
  }

  List<Widget> _buildLotSection() {
    final lot = result.lot;
    if (lot == null) {
      return const [];
    }

    return [
      MobileSection(
        title: 'Datos del solar',
        rows: [
          // El código del solar ya está en la tarjeta de identidad.
          MobileInfoItem('Manzana', lot.blockNumber),
          MobileInfoItem('Solar', lot.lotNumber),
          MobileInfoItem('Área', '${lot.area.toStringAsFixed(2)} m²'),
          MobileInfoItem(
            'Precio por m²',
            MobileUi.money(lot.pricePerSquareMeter),
          ),
          MobileInfoItem('Precio total', MobileUi.money(lot.totalPrice)),
          MobileInfoItem('Estado', _lotStatusLabel(lot.status)),
        ],
      ),
      const SizedBox(height: 18),
    ];
  }

  List<Widget> _buildSaleSections() {
    final sales = result.relatedSales;
    return [
      for (var index = 0; index < sales.length; index++)
        Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: _buildSaleSection(sales[index], index),
        ),
    ];
  }

  Widget _buildSaleSection(Map<String, dynamic> sale, int index) {
    final sales = result.relatedSales;
    final title = sales.length > 1
        ? 'Venta ${index + 1} de ${sales.length}'
        : 'Venta';

    final pendingInitial = _toDouble(sale['monto_inicial_pendiente']);
    final apartadoMinimum = _toDouble(sale['monto_apartado_minimo']);
    final deadlineRaw = (sale['fecha_limite_inicial'] ?? '').toString().trim();

    return MobileSection(
      title: title,
      rows: [
        // El solar ya está en el encabezado cuando la búsqueda fue por solar.
        if (result.lot == null) MobileInfoItem('Solar', _lotCode(sale)),
        MobileInfoItem('Fecha', _dateTime(sale['fecha_venta'])),
        MobileInfoItem(
          'Precio de venta',
          MobileUi.money(_toDouble(sale['precio_venta'])),
        ),
        MobileInfoItem(
          'Inicial pagada',
          MobileUi.money(_toDouble(sale['monto_inicial_pagado'])),
        ),
        if (pendingInitial > 0)
          MobileInfoItem('Inicial pendiente', MobileUi.money(pendingInitial)),
        if (apartadoMinimum > 0)
          MobileInfoItem('Apartado mínimo', MobileUi.money(apartadoMinimum)),
        MobileInfoItem(
          'Financiado',
          MobileUi.money(_toDouble(sale['saldo_financiado'])),
        ),
        if (deadlineRaw.isNotEmpty)
          MobileInfoItem('Límite de inicial', _date(deadlineRaw)),
        MobileInfoItem('Vendedor', _text(sale['vendedor_nombre'])),
        MobileInfoItem('Registrada por', _text(sale['usuario_nombre'])),
      ],
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
        child: Align(
          alignment: Alignment.centerLeft,
          child: MobileStatusChip(
            label: _statusLabel(sale['estado']),
            color: _statusColor(sale['estado']),
          ),
        ),
      ),
    );
  }

  /// Plan de cuotas COMPLETO.
  ///
  /// El Buscador debe ser el punto único donde se ve todo lo relacionado al
  /// cliente/solar: aquí se listan TODAS las cuotas, no un botón al módulo.
  List<Widget> _buildInstallmentsSection() {
    final installments = result.relatedInstallments;
    if (installments.isEmpty) {
      return const [];
    }

    var total = 0.0;
    var paid = 0.0;
    var paidCount = 0;
    for (final installment in installments) {
      total += installment.totalAmount;
      paid += installment.paidAmount;
      if (installment.calculatedStatus == 'pagada') {
        paidCount += 1;
      }
    }

    // El código del solar solo se repite por fila si la búsqueda abarca varias
    // ventas (con una sola venta ya está en el encabezado de la sección Venta).
    final showLotCode = result.relatedSales.length > 1;

    return [
      MobileSectionTitle('Plan de cuotas (${installments.length})'),
      Container(
        decoration: mobileCardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DetailStats(
              items: [
                MobileInfoItem('Pagadas', '$paidCount/${installments.length}'),
                MobileInfoItem('Total del plan', MobileUi.money(total)),
                MobileInfoItem('Cobrado', MobileUi.money(paid)),
              ],
            ),
            const Divider(height: 1, thickness: 1, color: MobileUi.divider),
            for (var index = 0; index < installments.length; index++) ...[
              if (index > 0)
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: MobileUi.divider,
                  indent: 16,
                  endIndent: 16,
                ),
              _InstallmentDetailRow(
                installment: installments[index],
                showLotCode: showLotCode,
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 18),
    ];
  }

  /// Historial de pagos COMPLETO.
  List<Widget> _buildPaymentsSection() {
    final payments = result.relatedPayments;
    if (payments.isEmpty) {
      return const [];
    }

    var total = 0.0;
    for (final payment in payments) {
      total += _toDouble(payment['monto_pagado']);
    }

    return [
      MobileSectionTitle('Pagos registrados (${payments.length})'),
      Container(
        decoration: mobileCardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DetailStats(
              items: [MobileInfoItem('Total recibido', MobileUi.money(total))],
            ),
            const Divider(height: 1, thickness: 1, color: MobileUi.divider),
            for (var index = 0; index < payments.length; index++) ...[
              if (index > 0)
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: MobileUi.divider,
                  indent: 16,
                  endIndent: 16,
                ),
              _PaymentDetailRow(payment: payments[index]),
            ],
          ],
        ),
      ),
      const SizedBox(height: 18),
    ];
  }

  /// Accesos directos a los módulos relacionados.
  List<Widget> _buildAccessSection(BuildContext context) {
    final saleId = _primarySaleId(result);

    final actions = <Widget>[
      if (onOpenSales != null)
        MobileDetailActionTile(
          icon: Icons.receipt_long_outlined,
          label: 'Ver ventas',
          onTap: () => _openModule(context, onOpenSales),
        ),
      if (saleId != null && onOpenInstallments != null)
        MobileDetailActionTile(
          icon: Icons.event_note_outlined,
          label: 'Ver cuotas',
          onTap: () =>
              _openModule(context, () => onOpenInstallments!.call(saleId)),
        ),
      if (saleId != null && onOpenPayments != null)
        MobileDetailActionTile(
          icon: Icons.payments_outlined,
          label: 'Ver pagos',
          onTap: () => _openModule(context, () => onOpenPayments!.call(saleId)),
        ),
      if (result.client != null && onOpenClients != null)
        MobileDetailActionTile(
          icon: Icons.person_outline,
          label: 'Ver cliente',
          onTap: () => _openModule(context, onOpenClients),
        ),
      if (result.lot != null && onOpenLots != null)
        MobileDetailActionTile(
          icon: Icons.landscape_outlined,
          label: 'Ver solar',
          onTap: () => _openModule(context, onOpenLots),
        ),
    ];

    if (actions.isEmpty) {
      return const [];
    }

    return [
      const MobileSectionTitle('Accesos'),
      Container(
        decoration: mobileCardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < actions.length; index++) ...[
              if (index > 0)
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: MobileUi.divider,
                  indent: 16,
                  endIndent: 16,
                ),
              actions[index],
            ],
          ],
        ),
      ),
    ];
  }

  /// Cierra el detalle y navega al módulo destino. La navegación es inmediata:
  /// cada módulo carga su información dentro de su propia pantalla.
  void _openModule(BuildContext context, VoidCallback? action) {
    if (action == null) {
      return;
    }
    Navigator.of(context).pop();
    action();
  }

  // ── Textos ─────────────────────────────────────────────────────────────────

  String _identitySubtitle() {
    final client = result.client;
    if (client != null) {
      final document = client.documentId.trim();
      return document.isEmpty ? 'Cliente' : 'Cliente · $document';
    }
    if (result.lot != null) {
      // El código del solar es el título: no se repite aquí.
      return 'Solar';
    }
    return '';
  }

  /// Solar en formato `M5-S10`. Si no hay datos de manzana/solar se omite para
  /// no exponer identificadores internos.
  String _lotCode(Map<String, dynamic> sale) {
    final block = (sale['manzana_numero']?.toString() ?? '').trim();
    final lot = (sale['solar_numero']?.toString() ?? '').trim();
    if (block.isEmpty && lot.isEmpty) {
      return 'No especificado';
    }
    return 'M$block-S$lot';
  }

  String _statusLabel(Object? value) {
    switch ((value?.toString() ?? '').toLowerCase()) {
      case 'activa':
        return 'Activa';
      case 'apartado':
        return 'Apartado';
      case 'inicial_incompleto':
        return 'Inicial incompleto';
      case 'pagada':
        return 'Pagada';
      case 'cancelada':
        return 'Cancelada';
      default:
        return 'Sin estado';
    }
  }

  Color _statusColor(Object? value) {
    switch ((value?.toString() ?? '').toLowerCase()) {
      case 'activa':
        return MobileUi.info;
      case 'apartado':
        return MobileUi.warning;
      case 'inicial_incompleto':
        return MobileUi.warning;
      case 'pagada':
        return MobileUi.success;
      case 'cancelada':
        return MobileUi.danger;
      default:
        return MobileUi.textSecondary;
    }
  }

  String _lotStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'disponible':
        return 'Disponible';
      case 'vendido':
        return 'Vendido';
      case 'apartado':
        return 'Apartado';
      case 'reservado':
        return 'Reservado';
      default:
        return status.isEmpty ? 'No especificado' : status;
    }
  }

  String _text(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? 'No especificado' : text;
  }

  String _dateTime(Object? value) => _formatSearchDateTime(value);

  /// Fecha sola (`06/09/2026`).
  String _date(Object? value) {
    final raw = value?.toString() ?? '';
    if (raw.isEmpty) {
      return 'No especificada';
    }
    final parsed = DateTime.tryParse(raw);
    return parsed == null ? raw : MobileUi.date(parsed);
  }

  /// Chip del encabezado: el monto pendiente es el dato más relevante y solo
  /// se muestra aquí (las secciones muestran su desglose, no el total).
  Widget? _heroChip() {
    final pending = result.totalPendingAmount;
    if (pending > 0) {
      return MobileStatusChip(
        label: 'Pendiente ${MobileUi.money(pending)}',
        color: MobileUi.warning,
      );
    }
    final sales = result.relatedSales;
    if (sales.isNotEmpty) {
      return MobileStatusChip(
        label: _statusLabel(sales.first['estado']),
        color: _statusColor(sales.first['estado']),
      );
    }
    return null;
  }

  double _toDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}

/// Primer `saleId` del resultado (venta principal).
int? _primarySaleId(GlobalSearchResult result) {
  if (result.relatedSales.isEmpty) {
    return null;
  }
  final raw = result.relatedSales.first['id'];
  if (raw is int) {
    return raw;
  }
  return int.tryParse(raw?.toString() ?? '');
}

// ══════════════════════════════════════════════════════════════════════════════
// FILAS DE DETALLE (cuotas y pagos mostrados completos, sin repetir contexto)
// ══════════════════════════════════════════════════════════════════════════════

/// Franja de totales de una sección (etiqueta pequeña + valor destacado).
class _DetailStats extends StatelessWidget {
  const _DetailStats({required this.items});

  final List<MobileInfoItem> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Wrap(
        spacing: 22,
        runSpacing: 10,
        children: [
          for (final item in items)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(item.label.toUpperCase(), style: MobileUi.amountLabel),
                const SizedBox(height: 3),
                Text(item.value, style: MobileUi.amount),
              ],
            ),
        ],
      ),
    );
  }
}

/// Fila de una cuota del plan de pagos.
///
/// No repite cliente ni nombre del solar: toda la pantalla ya es de ese
/// cliente/solar. El código del solar solo se agrega cuando la búsqueda abarca
/// varias ventas.
class _InstallmentDetailRow extends StatelessWidget {
  const _InstallmentDetailRow({
    required this.installment,
    this.showLotCode = false,
  });

  final InstallmentDetail installment;
  final bool showLotCode;

  @override
  Widget build(BuildContext context) {
    final status = installment.calculatedStatus;
    final meta = <String>['Vence ${MobileUi.date(installment.dueDate)}'];
    if (showLotCode && installment.lotCode.trim().isNotEmpty) {
      meta.add(installment.lotCode.trim());
    }
    if (installment.paidAmount > 0 && installment.remainingAmount > 0) {
      meta.add('Pagado ${MobileUi.money(installment.paidAmount)}');
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cuota ${installment.installmentNumber}',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: MobileUi.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(meta.join(' · '), style: MobileUi.itemMeta),
                if (installment.interestAmount > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Capital ${MobileUi.money(installment.principalAmount)} · '
                    'Interés ${MobileUi.money(installment.interestAmount)}',
                    style: MobileUi.itemMeta,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                MobileUi.money(installment.totalAmount),
                style: MobileUi.amount,
              ),
              const SizedBox(height: 4),
              MobileStatusChip(
                label: installmentStatusLabel(status),
                color: installmentStatusColor(status),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Fila de un pago del historial.
class _PaymentDetailRow extends StatelessWidget {
  const _PaymentDetailRow({required this.payment});

  final Map<String, dynamic> payment;

  @override
  Widget build(BuildContext context) {
    final method = (payment['metodo_pago'] ?? '').toString().trim();
    final reference = (payment['referencia'] ?? '').toString().trim();
    final year = payment['ano_a_pagar'];

    final meta = <String>[_formatSearchDateTime(payment['fecha_pago'])];
    if (method.isNotEmpty) {
      meta.add(_paymentMethodLabel(method));
    }
    if (year != null) {
      meta.add('Año $year');
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _paymentTitle(payment),
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: MobileUi.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(meta.join(' · '), style: MobileUi.itemMeta),
                if (reference.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text('Ref. $reference', style: MobileUi.itemMeta),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            MobileUi.money(_asDouble(payment['monto_pagado'])),
            style: MobileUi.amount,
          ),
        ],
      ),
    );
  }
}

/// Concepto legible de un pago.
String _paymentTitle(Map<String, dynamic> payment) {
  final cuota = payment['numero_cuota'];
  switch ((payment['tipo_pago'] ?? '').toString().trim().toLowerCase()) {
    case 'apartado':
      return 'Pago de apartado';
    case 'abono_inicial':
      return 'Abono a inicial';
    case 'abono_capital':
      return 'Abono a capital';
    default:
      return cuota == null ? 'Pago de cuota' : 'Cuota #$cuota';
  }
}

/// Método de pago legible (`efectivo` → `Efectivo`).
String _paymentMethodLabel(String method) {
  switch (method.trim().toLowerCase()) {
    case 'efectivo':
      return 'Efectivo';
    case 'transferencia':
      return 'Transferencia';
    case 'cheque':
      return 'Cheque';
    case 'tarjeta':
      return 'Tarjeta';
    case 'deposito':
    case 'depósito':
      return 'Depósito';
    default:
      final trimmed = method.trim();
      return trimmed.isEmpty
          ? trimmed
          : trimmed[0].toUpperCase() + trimmed.substring(1);
  }
}

/// `dd/MM/yyyy HH:mm` con texto amable cuando no hay dato.
String _formatSearchDateTime(Object? value) {
  final raw = value?.toString() ?? '';
  if (raw.isEmpty) {
    return 'Fecha no registrada';
  }
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    return raw;
  }
  final hour = parsed.hour.toString().padLeft(2, '0');
  final minute = parsed.minute.toString().padLeft(2, '0');
  return '${MobileUi.date(parsed)} $hour:$minute';
}

double _asDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
