import 'payment_history_item.dart';
import 'payment_sale_context.dart';

class ClientPagareItem {
  const ClientPagareItem({
    required this.paymentId,
    required this.saleId,
    required this.lotDisplayCode,
    required this.paymentDate,
    required this.amountPaid,
    required this.paymentMethod,
    required this.paymentType,
    this.installmentNumber,
    this.reference,
  });

  final int paymentId;
  final int saleId;
  final String lotDisplayCode;
  final DateTime paymentDate;
  final double amountPaid;
  final String paymentMethod;
  final String paymentType;
  final int? installmentNumber;
  final String? reference;

  factory ClientPagareItem.fromMap(Map<String, Object?> map) {
    final block = map['manzana_numero'] as String? ?? '';
    final lot = map['solar_numero'] as String? ?? '';

    return ClientPagareItem(
      paymentId: map['id'] as int? ?? 0,
      saleId: map['venta_id'] as int? ?? 0,
      lotDisplayCode: 'M$block-S$lot',
      paymentDate: DateTime.parse(map['fecha_pago'] as String),
      amountPaid: _toDouble(map['monto_pagado']),
      paymentMethod: map['metodo_pago'] as String? ?? 'N/A',
      paymentType: map['tipo_pago'] as String? ?? 'cuota',
      installmentNumber: map['numero_cuota'] as int?,
      reference: map['referencia'] as String?,
    );
  }

  static double _toDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value.toString()) ?? 0;
  }
}

class ClientPagareReport {
  const ClientPagareReport({
    required this.clientId,
    required this.clientName,
    required this.clientDocumentId,
    required this.items,
  });

  factory ClientPagareReport.fromPaymentContext({
    required PaymentSaleContext context,
    Iterable<PaymentHistoryItem>? payments,
  }) {
    final source = payments ?? context.history;
    final items = source
        .where((payment) => !payment.isAnnulled)
        .map(
          (payment) => ClientPagareItem(
            paymentId: payment.id,
            saleId: payment.saleId,
            lotDisplayCode: context.sale.lotDisplayCode,
            paymentDate: payment.paymentDate,
            amountPaid: payment.amountPaid,
            paymentMethod: payment.paymentMethod,
            paymentType: payment.paymentType,
            installmentNumber: payment.installmentNumber,
            reference: payment.reference,
          ),
        )
        .toList(growable: false);

    return ClientPagareReport(
      clientId: context.sale.clientId,
      clientName: context.sale.clientName,
      clientDocumentId: context.sale.clientDocumentId,
      items: items,
    );
  }

  final int clientId;
  final String clientName;
  final String clientDocumentId;
  final List<ClientPagareItem> items;

  double get totalPaid =>
      items.fold<double>(0, (sum, item) => sum + item.amountPaid);
}
