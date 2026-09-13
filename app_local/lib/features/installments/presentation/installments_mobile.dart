import 'package:flutter/material.dart';

import '../../../shared/mobile/mobile_screens.dart';
import '../../../shared/mobile/mobile_ui.dart';
import '../domain/installment_detail.dart';

/// Lista + detalle de CUOTAS en el layout compacto (patrón Ventas).
///
/// En mobile las cuotas se presentan como lista legible (no como tabla
/// comprimida). La tabla con columnas sigue disponible en "Cuotas amortizadas"
/// con scroll horizontal intencional.
class InstallmentsMobileView extends StatefulWidget {
  const InstallmentsMobileView({
    super.key,
    required this.installments,
    required this.isLoading,
    required this.totalFinanced,
    required this.totalPaid,
    required this.totalPending,
    required this.hasOverdue,
    required this.totalOverdueAmount,
    required this.onSearch,
    required this.onClearSearch,
    required this.onRetry,
  });

  final List<InstallmentDetail> installments;
  final bool isLoading;
  final double totalFinanced;
  final double totalPaid;
  final double totalPending;
  final bool hasOverdue;
  final double totalOverdueAmount;
  final ValueChanged<String> onSearch;
  final VoidCallback onClearSearch;
  final VoidCallback onRetry;

  @override
  State<InstallmentsMobileView> createState() => _InstallmentsMobileViewState();
}

class _InstallmentsMobileViewState extends State<InstallmentsMobileView> {
  final TextEditingController _searchController = TextEditingController();

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
      body: Column(
        children: [
          Container(
            color: MobileUi.surface,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: MobileSearchRow(
              controller: _searchController,
              hintText: 'Buscar cuotas…',
              onSubmitted: widget.onSearch,
              onClear: _clearSearch,
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (widget.isLoading && widget.installments.isEmpty) {
      return const MobileLoadingView(label: 'Cargando cuotas…');
    }
    if (widget.installments.isEmpty) {
      return MobileEmptyState(
        title: 'No hay cuotas para mostrar',
        message: _searchController.text.trim().isEmpty
            ? 'Las cuotas se generan al registrar una venta financiada.'
            : 'No se encontraron cuotas para tu búsqueda.',
        icon: Icons.event_note_outlined,
        actionLabel: _searchController.text.trim().isEmpty
            ? null
            : 'Limpiar búsqueda',
        onAction: _searchController.text.trim().isEmpty ? null : _clearSearch,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        MobileUi.listPadding,
        8,
        MobileUi.listPadding,
        24,
      ),
      itemCount: widget.installments.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: MobileUi.rowGap),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _summary();
        }
        final installment = widget.installments[index - 1];
        return MobileEntityRow(
          title: 'Cuota ${installment.installmentNumber}',
          subtitle: installment.clientName.trim().isEmpty
              ? 'Solar ${installment.lotCode}'
              : installment.clientName,
          meta: 'Vence ${MobileUi.date(installment.dueDate)} · '
              '${installment.lotCode}',
          leading: MobileInitialAvatar(
            name: installment.clientName.isEmpty
                ? installment.lotCode
                : installment.clientName,
            color: installmentStatusColor(installment.status),
          ),
          trailing: SizedBox(
            width: 96,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    MobileUi.money(installment.remainingAmount),
                    maxLines: 1,
                    style: MobileUi.amountSmall,
                  ),
                ),
                const SizedBox(height: 4),
                MobileStatusChip(
                  label: installmentStatusLabel(installment.status),
                  color: installmentStatusColor(installment.status),
                ),
              ],
            ),
          ),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => InstallmentDetailPage(installment: installment),
            ),
          ),
        );
      },
    );
  }

  Widget _summary() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
          decoration: mobileCardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _metric('Financiado', widget.totalFinanced),
                  ),
                  Expanded(child: _metric('Pagado', widget.totalPaid)),
                  Expanded(child: _metric('Pendiente', widget.totalPending)),
                ],
              ),
              if (widget.hasOverdue) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    MobileStatusChip(
                      label:
                          'En atraso: ${MobileUi.money(widget.totalOverdueAmount)}',
                      color: MobileUi.danger,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 4),
        const MobileSectionTitle('Cuotas'),
      ],
    );
  }

  Widget _metric(String label, double value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: MobileUi.amountLabel),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            MobileUi.money(value),
            maxLines: 1,
            style: MobileUi.amountSmall,
          ),
        ),
      ],
    );
  }
}

/// Detalle de una cuota (sin identificadores técnicos).
class InstallmentDetailPage extends StatelessWidget {
  const InstallmentDetailPage({super.key, required this.installment});

  final InstallmentDetail installment;

  @override
  Widget build(BuildContext context) {
    return MobileDetailScaffold(
      title: 'Detalle de cuota',
      children: [
        MobileDetailIdentityCard(
          title: 'Cuota ${installment.installmentNumber}',
          subtitle: installment.clientName.trim().isEmpty
              ? 'Solar ${installment.lotCode}'
              : installment.clientName,
          chip: MobileStatusChip(
            label: installmentStatusLabel(installment.status),
            color: installmentStatusColor(installment.status),
          ),
        ),
        const SizedBox(height: 18),
        MobileSection(
          title: 'Datos de la cuota',
          rows: [
            MobileInfoItem('Cliente', installment.clientName),
            MobileInfoItem('Solar', installment.lotCode),
            MobileInfoItem('Vence', MobileUi.date(installment.dueDate)),
            MobileInfoItem(
              'Estado',
              installmentStatusLabel(installment.status),
            ),
          ],
        ),
        const SizedBox(height: 18),
        MobileSection(
          title: 'Resumen financiero',
          rows: [
            MobileInfoItem(
              'Cuota fija',
              MobileUi.money(installment.totalAmount),
            ),
            MobileInfoItem(
              'Capital',
              MobileUi.money(installment.principalAmount),
            ),
            MobileInfoItem(
              'Interés',
              MobileUi.money(installment.interestAmount),
            ),
            MobileInfoItem('Pagado', MobileUi.money(installment.paidAmount)),
            MobileInfoItem(
              'Pendiente',
              MobileUi.money(installment.remainingAmount),
            ),
            MobileInfoItem(
              'Saldo final',
              MobileUi.money(installment.endingBalance),
            ),
          ],
        ),
      ],
    );
  }
}

String installmentStatusLabel(String status) {
  switch (status.trim().toLowerCase()) {
    case 'pagada':
      return 'Pagada';
    case 'parcial':
      return 'Parcial';
    case 'vencida':
      return 'Vencida';
    case 'pendiente':
      return 'Pendiente';
    case 'ajustada':
      return 'Ajustada';
    case 'cancelada':
      return 'Cancelada';
    default:
      return status;
  }
}

Color installmentStatusColor(String status) {
  switch (status.trim().toLowerCase()) {
    case 'pagada':
      return MobileUi.success;
    case 'parcial':
      return MobileUi.info;
    case 'vencida':
      return MobileUi.danger;
    case 'pendiente':
      return MobileUi.warning;
    default:
      return MobileUi.textSecondary;
  }
}
