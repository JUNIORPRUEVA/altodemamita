import 'package:flutter/material.dart';

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
  if (parsed == null) return 'RD\$0.00';
  return 'RD\$${parsed.toStringAsFixed(2)}';
}

class RecordView {
  const RecordView({
    required this.title,
    required this.subtitle,
    required this.fields,
    required this.searchText,
    this.badge,
    this.icon,
  });

  final String title;
  final String subtitle;
  final List<RecordField> fields;
  final String searchText;
  final String? badge;
  final IconData? icon;
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

  static RecordView installment(Map<String, dynamic> item) => RecordView(
        title: 'Cuota ${text(item['installmentNumber'], '-')}',
        subtitle: 'Estado ${text(item['status'], '-')}',
        badge: text(item['status'], '-'),
        icon: Icons.calendar_month_rounded,
        fields: [
          RecordField('Monto', money(item['totalAmount'])),
          RecordField('Pagado', money(item['paidAmount'])),
          RecordField('Balance final', money(item['endingBalance'])),
          RecordField('Vence', dateText(item['dueDate'])),
        ],
        searchText: item.toString(),
      );

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
