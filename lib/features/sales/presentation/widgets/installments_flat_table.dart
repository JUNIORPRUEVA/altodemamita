import 'package:flutter/material.dart';

import '../../../installments/domain/installment.dart';

class InstallmentsFlatTable extends StatelessWidget {
  const InstallmentsFlatTable({
    super.key,
    required this.installments,
    required this.scrollController,
  });

  final List<Installment> installments;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE4EAF2)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          children: [
            const _Header(),
            const Divider(height: 1),
            Expanded(
              child: Scrollbar(
                controller: scrollController,
                thumbVisibility: true,
                child: ListView.separated(
                  controller: scrollController,
                  padding: EdgeInsets.zero,
                  itemCount: installments.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    return _Row(item: installments[index]);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w800,
      color: Color(0xFF7A859D),
      letterSpacing: 0.3,
    );

    return Container(
      color: const Color(0xFFF8FAFD),
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: const [
          SizedBox(width: 76, child: Text('CUOTA', style: style)),
          SizedBox(width: 96, child: Text('ESTADO', style: style)),
          SizedBox(width: 92, child: Text('VENCE', style: style)),
          SizedBox(width: 112, child: Text('CUOTA FIJA', style: style)),
          SizedBox(width: 112, child: Text('PENDIENTE', style: style)),
          SizedBox(width: 104, child: Text('CAPITAL', style: style)),
          SizedBox(width: 96, child: Text('INTERES', style: style)),
          SizedBox(width: 104, child: Text('PAGADO', style: style)),
          Expanded(child: Text('SALDO FINAL', style: style)),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.item});

  final Installment item;

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(item.status);
    final settled = item.remainingAmount <= 0.009;

    return Container(
      color: Colors.white,
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(
              'Cuota ${item.installmentNumber}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A2235),
              ),
            ),
          ),
          SizedBox(
            width: 96,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _statusLabel(item.status),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 92,
            child: Text(
              _formatDate(item.dueDate),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF54627B),
              ),
            ),
          ),
          SizedBox(
            width: 112,
            child: Text(
              _money(item.totalAmount),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A2235),
              ),
            ),
          ),
          SizedBox(
            width: 112,
            child: Text(
              _money(item.remainingAmount),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: settled
                    ? const Color(0xFF2E7D32)
                    : const Color(0xFF1A2235),
              ),
            ),
          ),
          SizedBox(
            width: 104,
            child: Text(
              _money(item.principalAmount),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2D3A55),
              ),
            ),
          ),
          SizedBox(
            width: 96,
            child: Text(
              _money(item.interestAmount),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2D3A55),
              ),
            ),
          ),
          SizedBox(
            width: 104,
            child: Text(
              _money(item.paidAmount),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF54627B),
              ),
            ),
          ),
          Expanded(
            child: Text(
              _money(item.endingBalance),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF54627B),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Color _statusColor(String status) {
  switch (status.toLowerCase()) {
    case 'pagada':
      return const Color(0xFF2E7D32);
    case 'parcial':
      return const Color(0xFF1976D2);
    case 'vencida':
      return const Color(0xFFC62828);
    case 'pendiente':
      return const Color(0xFFE67E00);
    default:
      return const Color(0xFF455A64);
  }
}

String _statusLabel(String status) {
  switch (status.toLowerCase()) {
    case 'pagada':
      return 'Pagada';
    case 'parcial':
      return 'Parcial';
    case 'vencida':
      return 'Vencida';
    case 'pendiente':
      return 'Pendiente';
    default:
      return status;
  }
}

String _money(double value) => 'RD\$${_fmtAmount(value)}';

String _fmtAmount(double value) {
  return value
      .toStringAsFixed(2)
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
}

String _formatDate(DateTime value) {
  return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
}
