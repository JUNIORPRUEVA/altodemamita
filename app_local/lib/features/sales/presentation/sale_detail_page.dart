import 'package:flutter/material.dart';

import '../../../core/utils/dominican_formatters.dart';
import '../domain/sale_calculator.dart';
import '../domain/sale_detail.dart';
import 'sale_detail_dialog.dart';

/// ============================================================================
/// DETALLE DE VENTA - PANTALLA COMPLETA
/// ============================================================================
///
/// Reemplaza al modal en la PWA / layout compacto: el contenido se adapta al
/// tamaño del dispositivo, no se desborda y queda ordenado en secciones.
///
/// Reglas de producto:
/// - NUNCA se muestran identificadores técnicos (ID local, sync ID, UUID,
///   versiones, etc.).
/// - Los montos se ven COMPLETOS (nunca recortados).
/// - Los dos accesos principales son "Ver cuotas" y "Ver pagos".
class SaleDetailPage extends StatefulWidget {
  const SaleDetailPage({
    super.key,
    this.initialDetail,
    this.loadDetail,
    this.previewClientName,
    this.previewLotCode,
    this.canUpdate = false,
    this.canDelete = false,
    this.onEdit,
    this.onDelete,
  });

  /// Detalle ya cargado (crear / editar venta).
  final SaleDetail? initialDetail;

  /// Carga diferida cuando solo se tiene el resumen de la lista.
  final Future<SaleDetail?> Function()? loadDetail;

  /// Texto mostrado mientras se carga el detalle.
  final String? previewClientName;
  final String? previewLotCode;

  final bool canUpdate;
  final bool canDelete;
  final Future<void> Function()? onEdit;
  final Future<bool> Function()? onDelete;

  /// Etiqueta visible del módulo.
  static const String title = 'Detalle de venta';

  @override
  State<SaleDetailPage> createState() => _SaleDetailPageState();
}

class _SaleDetailPageState extends State<SaleDetailPage> {
  SaleDetail? _detail;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _detail = widget.initialDetail;
    if (_detail == null) {
      _load();
    }
  }

  Future<void> _load() async {
    final loader = widget.loadDetail;
    if (loader == null || _isLoading) {
      return;
    }
    setState(() {
      _isLoading = true;
    });
    SaleDetail? detail;
    try {
      detail = await loader();
    } catch (_) {
      detail = null;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _isLoading = false;
      _detail = detail;
    });
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: const Border(
          bottom: BorderSide(color: Color(0xFFECEEF2)),
        ),
        title: const Text(
          SaleDetailPage.title,
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: Color(0xFF16202E),
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF16202E)),
        actions: [
          if (detail != null)
            PopupMenuButton<_DetailAction>(
              tooltip: 'Acciones',
              icon: const Icon(
                Icons.more_vert_rounded,
                color: Color(0xFF16202E),
              ),
              onSelected: _handleAction,
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: _DetailAction.print,
                  child: Text('Imprimir documento'),
                ),
                if (widget.canUpdate && widget.onEdit != null)
                  const PopupMenuItem(
                    value: _DetailAction.edit,
                    child: Text('Editar venta'),
                  ),
                if (widget.canDelete && widget.onDelete != null)
                  const PopupMenuItem(
                    value: _DetailAction.delete,
                    child: Text('Eliminar venta'),
                  ),
              ],
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: _buildBody(),
    );
  }

  Future<void> _handleAction(_DetailAction action) async {
    final detail = _detail;
    if (detail == null) {
      return;
    }
    switch (action) {
      case _DetailAction.print:
        await printSaleDocument(context, detail);
      case _DetailAction.edit:
        await widget.onEdit?.call();
        if (mounted && _detail != null) {
          await _load();
        }
      case _DetailAction.delete:
        final deleted = await widget.onDelete?.call();
        if (deleted == true && mounted) {
          Navigator.of(context).maybePop();
        }
    }
  }

  Widget _buildBody() {
    final detail = _detail;
    if (detail != null) {
      return _DetailContent(
        detail: detail,
        canUpdate: widget.canUpdate,
        canDelete: widget.canDelete,
        onEdit: widget.onEdit == null
            ? null
            : () async {
                await widget.onEdit!.call();
                if (mounted) await _load();
              },
        onDelete: widget.onDelete == null
            ? null
            : () async {
                final deleted = await widget.onDelete!.call();
                if (deleted && mounted) {
                  Navigator.of(context).maybePop();
                }
              },
      );
    }

    if (_isLoading) {
      return _LoadingState(
        clientName: widget.previewClientName,
        lotCode: widget.previewLotCode,
      );
    }

    return _LoadFailedState(onRetry: widget.loadDetail == null ? null : _load);
  }
}

enum _DetailAction { print, edit, delete }

// ══════════════════════════════════════════════════════════════════════════════
// CONTENIDO
// ══════════════════════════════════════════════════════════════════════════════

class _DetailContent extends StatelessWidget {
  const _DetailContent({
    required this.detail,
    required this.canUpdate,
    required this.canDelete,
    required this.onEdit,
    required this.onDelete,
  });

  final SaleDetail detail;
  final bool canUpdate;
  final bool canDelete;
  final Future<void> Function()? onEdit;
  final Future<void> Function()? onDelete;

  @override
  Widget build(BuildContext context) {
    final sale = detail.sale;
    final sellerLabel = (detail.sellerName ?? '').trim().isEmpty
        ? detail.userName
        : detail.sellerName!.trim();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _IdentityCard(detail: detail),
        const SizedBox(height: 18),
        _Section(
          title: 'Cliente y solar',
          rows: [
            _RowData('Cliente', detail.clientName),
            if (detail.clientDocumentId.trim().isNotEmpty)
              _RowData('Documento', detail.clientDocumentId),
            _RowData('Solar', detail.lotDisplayCode),
            _RowData('Área', '${detail.lotArea.toStringAsFixed(2)} m²'),
            _RowData(
              'Precio por m²',
              _money(detail.lotPricePerSquareMeter),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _Section(
          title: 'Condiciones de venta',
          rows: [
            _RowData('Fecha de venta', _date(sale.saleDate)),
            _RowData(
              'Plan de pago',
              '${sale.installmentCount} cuotas · '
                  '${sale.monthlyInterest.toStringAsFixed(2)}% mensual',
            ),
            _RowData(
              'Inicial',
              '${_money(sale.paidInitialPayment)} de '
                  '${_money(sale.requiredInitialPayment)}',
            ),
            if (sale.initialPaymentDeadline != null)
              _RowData(
                'Límite de inicial',
                _date(sale.initialPaymentDeadline!),
              ),
            _RowData('Responsable', sellerLabel),
            if (detail.initialPaymentMethod.trim().isNotEmpty)
              _RowData('Método de inicial', detail.initialPaymentMethod),
          ],
        ),
        const SizedBox(height: 18),
        _FinancialSection(detail: detail),
        const SizedBox(height: 18),
        _PaymentPlanSection(detail: detail),
        if (canUpdate || canDelete) ...[
          const SizedBox(height: 18),
          _Section(
            title: 'Acciones',
            rows: const [],
            footer: Column(
              children: [
                if (canUpdate && onEdit != null)
                  _ActionTile(
                    icon: Icons.edit_outlined,
                    label: 'Editar venta',
                    onTap: onEdit!,
                  ),
                if (canDelete && onDelete != null)
                  _ActionTile(
                    icon: Icons.delete_outline_rounded,
                    label: 'Eliminar venta',
                    color: const Color(0xFFB42318),
                    onTap: onDelete!,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.detail});

  final SaleDetail detail;

  @override
  Widget build(BuildContext context) {
    final name = detail.clientName.trim().isEmpty
        ? 'Cliente sin nombre'
        : detail.clientName.trim();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Color(0xFF16202E),
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Solar ${detail.lotDisplayCode}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF667085),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _StatusChip(detail: detail),
            ],
          ),
        ],
      ),
    );
  }
}

class _FinancialSection extends StatelessWidget {
  const _FinancialSection({required this.detail});

  final SaleDetail detail;

  @override
  Widget build(BuildContext context) {
    final sale = detail.sale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle('Resumen financiero'),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 600 ? 3 : 2;
            const spacing = 10.0;
            final itemWidth =
                (constraints.maxWidth - (spacing * (columns - 1))) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                _kpi(itemWidth, 'Valor de la venta', sale.salePrice),
                _kpi(
                  itemWidth,
                  'Balance pendiente',
                  sale.pendingBalance,
                  tone: sale.pendingBalance > 0.009
                      ? const Color(0xFFB54708)
                      : const Color(0xFF2E7D32),
                ),
                _kpi(itemWidth, 'Capital financiado', sale.financedBalance),
                _kpi(
                  itemWidth,
                  'Cuota mensual',
                  _fixedInstallmentAmount(detail),
                ),
                _kpi(itemWidth, 'Inicial pagada', sale.paidInitialPayment),
                _kpi(
                  itemWidth,
                  'Inicial requerida',
                  sale.requiredInitialPayment,
                ),
                if (sale.pendingInitialPayment > 0.009)
                  _kpi(
                    itemWidth,
                    'Inicial pendiente',
                    sale.pendingInitialPayment,
                    tone: const Color(0xFFB54708),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _kpi(double width, String label, double value, {Color? tone}) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 12, 13, 13),
        decoration: _cardDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF667085),
              ),
            ),
            const SizedBox(height: 7),
            // Nunca se recorta: si no cabe, se reduce.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                _money(value),
                maxLines: 1,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: tone ?? const Color(0xFF16202E),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentPlanSection extends StatelessWidget {
  const _PaymentPlanSection({required this.detail});

  final SaleDetail detail;

  @override
  Widget build(BuildContext context) {
    final paid = detail.paidInstallmentCount;
    final pending = detail.remainingInstallmentCount;
    final total = detail.activeInstallmentCount;
    final progress = total <= 0 ? 0.0 : (paid / total).clamp(0.0, 1.0);
    final saleId = detail.sale.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle('Plan de pagos'),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          decoration: _cardDecoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '$total cuotas',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF16202E),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$paid pagadas · $pending pendientes',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF667085),
                ),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: const Color(0xFFEDEFF3),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF123A5E),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Los dos accesos principales.
              Row(
                children: [
                  Expanded(
                    child: _PlanButton(
                      icon: Icons.event_note_outlined,
                      label: 'Ver cuotas',
                      onTap: () => openInstallmentsFullscreen(context, detail),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _PlanButton(
                      icon: Icons.account_balance_wallet_outlined,
                      label: 'Ver pagos',
                      onTap: saleId == null
                          ? null
                          : () => openSalePaymentsHistory(
                              context,
                              saleId: saleId,
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// PIEZAS
// ══════════════════════════════════════════════════════════════════════════════

final BoxDecoration _cardDecoration = BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(14),
  border: Border.all(color: const Color(0xFFECEEF2)),
);

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.7,
          color: Color(0xFF98A2B3),
        ),
      ),
    );
  }
}

class _RowData {
  const _RowData(this.label, this.value);

  final String label;
  final String value;
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.rows,
    this.footer,
  });

  final String title;
  final List<_RowData> rows;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(title),
        Container(
          decoration: _cardDecoration,
          padding: EdgeInsets.symmetric(vertical: rows.isEmpty ? 0 : 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < rows.length; index++)
                _InfoRow(
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({
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
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF667085),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 5,
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF16202E),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          const Divider(
            height: 1,
            thickness: 1,
            color: Color(0xFFECEEF2),
            indent: 16,
            endIndent: 16,
          ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = const Color(0xFF16202E),
  });

  final IconData icon;
  final String label;
  final Future<void> Function() onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onTap(),
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
              color: Color(0xFF98A2B3),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanButton extends StatelessWidget {
  const _PlanButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          maxLines: 1,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(46),
        foregroundColor: const Color(0xFF123A5E),
        side: const BorderSide(color: Color(0xFFD6DEE8)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.detail});

  final SaleDetail detail;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(detail);
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          _statusLabel(detail),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState({this.clientName, this.lotCode});

  final String? clientName;
  final String? lotCode;

  @override
  Widget build(BuildContext context) {
    final name = (clientName ?? '').trim();
    final lot = (lotCode ?? '').trim();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 18),
            const Text(
              'Cargando detalle de venta…',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF667085),
              ),
            ),
            if (name.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF16202E),
                ),
              ),
            ],
            if (lot.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Solar $lot',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF98A2B3),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LoadFailedState extends StatelessWidget {
  const _LoadFailedState({this.onRetry});

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
              color: Color(0xFF98A2B3),
            ),
            const SizedBox(height: 14),
            const Text(
              'No pudimos cargar el detalle de esta venta.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF16202E),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Revisa tu conexión e inténtalo nuevamente.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                color: Color(0xFF667085),
              ),
            ),
            const SizedBox(height: 20),
            if (onRetry != null)
              FilledButton(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF123A5E),
                  minimumSize: const Size(160, 46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Reintentar'),
              ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// FORMATO / ESTADO
// ══════════════════════════════════════════════════════════════════════════════

String _money(double value) => formatRdMoney(value);

String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/'
    '${value.month.toString().padLeft(2, '0')}/${value.year}';

double _fixedInstallmentAmount(SaleDetail detail) {
  if (detail.installments.isNotEmpty) {
    return detail.installments.first.totalAmount;
  }
  return SaleCalculator.calculateEstimatedInstallmentAmount(
    financedBalance: detail.sale.financedBalance,
    monthlyInterest: detail.sale.monthlyInterest,
    installmentCount: detail.sale.installmentCount,
  );
}

String _statusLabel(SaleDetail detail) {
  if (detail.sale.isFullyPaid) return 'Venta definitiva';
  if (detail.overdueInstallmentCount > 0) {
    return 'En atraso (${detail.overdueInstallmentCount})';
  }
  switch (detail.sale.status.toLowerCase()) {
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
    case 'reservada':
      return 'Reservada';
    case 'completada':
      return 'Completada';
    default:
      return detail.sale.status;
  }
}

Color _statusColor(SaleDetail detail) {
  if (detail.sale.isFullyPaid) return const Color(0xFF2E7D32);
  if (detail.overdueInstallmentCount > 0) return const Color(0xFFB42318);
  switch (detail.sale.status.toLowerCase()) {
    case 'activa':
      return const Color(0xFF2E7D32);
    case 'pagada':
    case 'completada':
      return const Color(0xFF1565C0);
    case 'apartado':
    case 'inicial_incompleto':
    case 'reservada':
      return const Color(0xFFB54708);
    case 'cancelada':
      return const Color(0xFFB42318);
    default:
      return const Color(0xFF667085);
  }
}
