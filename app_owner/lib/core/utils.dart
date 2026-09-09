import 'package:flutter/material.dart';

import '../app/app_colors.dart';

const String nullText = '-';

String text(Object? value, String fallback) {
  final resolved = value?.toString().trim() ?? '';
  return resolved.isEmpty ? fallback : resolved;
}

String dateText(Object? value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  if (parsed == null) return '-';
  return '${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.year}';
}

String money(Object? value) {
  final parsed = num.tryParse(value?.toString() ?? '');
  if (parsed == null) return 'RD\$0';
  final intPart = parsed.floor();
  final formatted = intPart.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (match) => '${match.group(1)},',
  );
  return 'RD\$$formatted';
}

class RecordView {
  const RecordView({
    required this.title,
    required this.subtitle,
    required this.fields,
    required this.searchText,
    this.badge,
    this.icon,
    this.accentColor,
  });

  final String title;
  final String subtitle;
  final List<RecordField> fields;
  final String searchText;
  final String? badge;
  final IconData? icon;
  final Color? accentColor;
}

class RecordField {
  const RecordField(this.label, this.value);

  final String label;
  final String value;
}

class RecordBuilders {
  static RecordView client(Map<String, dynamic> item) => RecordView(
    title: text(item['name'], 'Cliente sin nombre'),
    subtitle: 'Documento ${text(item['document'], '-')}',
    badge: text(item['phone'], '').isEmpty ? null : text(item['phone'], ''),
    icon: Icons.face_6_rounded,
    fields: [
      RecordField('Telefono', text(item['phone'], '-')),
      RecordField('Direccion', text(item['address'], '-')),
      RecordField('Actualizado', dateText(item['updatedAt'])),
    ],
    searchText: item.toString(),
  );

  static RecordView seller(Map<String, dynamic> item) => RecordView(
    title: text(item['name'], 'Vendedor sin nombre'),
    subtitle: 'Documento ${text(item['document'], '-')}',
    icon: Icons.handshake_rounded,
    fields: [
      RecordField('Telefono', text(item['phone'], '-')),
      RecordField('Actualizado', dateText(item['updatedAt'])),
    ],
    searchText: item.toString(),
  );

  static RecordView lot(Map<String, dynamic> item) => RecordView(
    title: 'Solar ${text(item['number'], '-')}',
    subtitle: 'Manzana ${text(item['block'], '-')}',
    badge: text(item['status'], '-'),
    icon: Icons.home_work_rounded,
    fields: [
      RecordField('Area', money(item['area'])),
      RecordField('Precio/m2', money(item['price'])),
      RecordField('Actualizado', dateText(item['updatedAt'])),
    ],
    searchText: item.toString(),
  );

  static RecordView sale(Map<String, dynamic> item) => RecordView(
    title:
        'Venta ${text(item['syncId'], '').isEmpty ? '' : text(item['syncId'], '')}',
    subtitle: 'Estado ${text(item['status'], '-')}',
    badge: text(item['status'], '-'),
    icon: Icons.description_rounded,
    fields: [
      RecordField('Total', money(item['total'])),
      RecordField('Inicial', money(item['initialPaid'])),
      RecordField('Balance', money(item['balance'])),
      RecordField('Fecha', dateText(item['saleDate'])),
    ],
    searchText: item.toString(),
  );

  static RecordView installment(Map<String, dynamic> item) {
    final status = _isOverdueInstallment(item)
        ? 'Vencida'
        : _installmentStatusLabel(item['status']);
    return RecordView(
      title: 'Cuota ${text(item['installmentNumber'], '-')}',
      subtitle: 'Estado $status',
      badge: status,
      icon: Icons.calendar_month_rounded,
      fields: [
        RecordField('Monto', money(item['totalAmount'])),
        RecordField('Pagado', money(item['paidAmount'])),
        RecordField('Pendiente', money(_installmentDueAmount(item))),
        RecordField('Vence', dateText(item['dueDate'])),
      ],
      searchText: item.toString(),
      accentColor: status == 'Vencida' ? AppColors.accentRose : null,
    );
  }

  static RecordView payment(Map<String, dynamic> item) => RecordView(
    title: 'Pago ${money(item['amount'])}',
    subtitle: text(item['method'], 'Metodo no indicado'),
    badge: text(item['paymentType'], nullText),
    icon: Icons.account_balance_wallet_rounded,
    fields: [
      RecordField('Fecha', dateText(item['paidAt'])),
      RecordField('Referencia', text(item['reference'], '-')),
      RecordField('Ano', text(item['yearToPay'], '-')),
    ],
    searchText: item.toString(),
  );
}

String _installmentStatusLabel(Object? status) {
  switch (status?.toString().toLowerCase()) {
    case 'pagada':
    case 'pagado':
    case 'paid':
      return 'Pagada';
    case 'pendiente':
    case 'pending':
      return 'Pendiente';
    case 'vencida':
    case 'vencido':
    case 'overdue':
      return 'Vencida';
    default:
      return text(status, '-');
  }
}

bool _isOverdueInstallment(Map<String, dynamic> installment) {
  final status = installment['status']?.toString().toLowerCase() ?? '';
  final isPaid = status.contains('pag') || status.contains('paid');
  if (status.contains('venc') || status.contains('overdue')) return true;
  final dueDate = DateTime.tryParse(installment['dueDate']?.toString() ?? '');
  if (dueDate == null || isPaid) return false;
  final today = DateTime.now();
  final todayOnly = DateTime(today.year, today.month, today.day);
  return dueDate.isBefore(todayOnly);
}

num _installmentDueAmount(Map<String, dynamic> installment) {
  final total = num.tryParse(installment['totalAmount']?.toString() ?? '') ?? 0;
  final paid = num.tryParse(installment['paidAmount']?.toString() ?? '') ?? 0;
  final pending = total - paid;
  if (pending > 0) return pending;
  if (total > 0 && paid <= 0) return total;
  return 0;
}
