import 'dart:developer' as developer;

import 'package:sistema_solares_ui/core/network/api_client.dart';

class PaymentsReadOnlyData {
  PaymentsReadOnlyData({
    required this.sales,
    required this.selectedSale,
    this.detailErrorMessage,
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
  });

  final List<PaymentSaleSummary> sales;
  final PaymentSaleDetail? selectedSale;
  final String? detailErrorMessage;
  final int total;
  final int page;
  final int limit;
  final int totalPages;
}

class PaymentSaleSummary {
  PaymentSaleSummary({
    required this.id,
    required this.clientName,
    required this.clientDocumentId,
    required this.clientPhone,
    required this.lotLabel,
    required this.contractNumber,
    required this.status,
    required this.saleDate,
    required this.totalAmount,
    required this.totalPaid,
    required this.pendingBalance,
    required this.requiredInitialPayment,
    required this.paidInitialPayment,
    required this.pendingInitialPayment,
  });

  final String id;
  final String clientName;
  final String clientDocumentId;
  final String clientPhone;
  final String lotLabel;
  final String contractNumber;
  final String status;
  final DateTime? saleDate;
  final double totalAmount;
  final double totalPaid;
  final double pendingBalance;
  final double requiredInitialPayment;
  final double paidInitialPayment;
  final double pendingInitialPayment;
}

class PaymentSaleDetail {
  PaymentSaleDetail({
    required this.summary,
    required this.monthlyInterest,
    required this.termMonths,
    required this.salespersonName,
    required this.installments,
    required this.history,
  });

  final PaymentSaleSummary summary;
  final double monthlyInterest;
  final int termMonths;
  final String salespersonName;
  final List<PaymentInstallmentView> installments;
  final List<PaymentHistoryView> history;

  int get paidInstallmentsCount =>
      installments.where((item) => item.isClosed).length;

  int get pendingInstallmentsCount =>
      installments.where((item) => !item.isClosed).length;

  int get overdueInstallmentsCount => installments
      .where((item) => item.statusLabel.startsWith('vencida'))
      .length;

  PaymentInstallmentView? get priorityInstallment {
    for (final installment in installments) {
      if (!installment.isClosed) {
        return installment;
      }
    }
    return null;
  }

  String get stageLabel {
    if (summary.pendingInitialPayment > 0.009) {
      return summary.paidInitialPayment > 0.009
          ? 'Inicial parcial'
          : 'Inicial pendiente';
    }
    if (summary.pendingBalance <= 0.009) {
      return 'Saldada';
    }
    final priority = priorityInstallment;
    if (priority == null) {
      return 'Saldo a capital';
    }
    if (priority.statusLabel.startsWith('vencida')) {
      return 'Cuota vencida';
    }
    if (priority.statusLabel == 'parcial') {
      return 'Cuota parcial';
    }
    return 'Al dia';
  }

  String get nextActionText {
    if (summary.pendingInitialPayment > 0.009) {
      return 'La venta aun esta en etapa de inicial. El panel web solo muestra el avance y no permite registrar cobros.';
    }
    final priority = priorityInstallment;
    if (priority == null) {
      return 'No hay cuotas abiertas. El saldo restante se refleja como capital pendiente o la venta ya esta saldada.';
    }
    return 'La prioridad actual es la cuota #${priority.installmentNumber} con vencimiento ${priority.dueDateIso}. Restante: RD\$ ${priority.remainingAmount.toStringAsFixed(2)}.';
  }
}

class PaymentInstallmentView {
  PaymentInstallmentView({
    required this.id,
    required this.installmentNumber,
    required this.dueDate,
    required this.amount,
    required this.paidAmount,
    required this.remainingAmount,
    required this.status,
    required this.statusLabel,
  });

  final String id;
  final int installmentNumber;
  final DateTime? dueDate;
  final double amount;
  final double paidAmount;
  final double remainingAmount;
  final String status;
  final String statusLabel;

  bool get isClosed => status == 'paid' || status == 'cancelled';

  String get dueDateIso {
    if (dueDate == null) {
      return '-';
    }
    final date = dueDate!;
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }
}

class PaymentHistoryView {
  PaymentHistoryView({
    required this.id,
    required this.paymentDate,
    required this.amount,
    required this.method,
    required this.reference,
    required this.type,
    required this.typeLabel,
    required this.installmentNumber,
  });

  final String id;
  final DateTime? paymentDate;
  final double amount;
  final String method;
  final String reference;
  final String type;
  final String typeLabel;
  final int? installmentNumber;
}

class PaymentsService {
  PaymentsService(this._apiClient);

  final ApiClient _apiClient;

  Future<PaymentsReadOnlyData> fetchReadOnly({
    String? search,
    int page = 1,
    int limit = 20,
    String? selectedSaleId,
  }) async {
    try {
      developer.log(
        'Loading payments read model from /payments/sales page=$page limit=$limit search=${search?.trim() ?? ''} selectedSaleId=${selectedSaleId ?? ''}',
        name: 'SistemaSolares.PaymentsPwa',
      );
      final response = await _apiClient.get(
        '/payments/sales',
        queryParameters: {
          'page': '$page',
          'limit': '$limit',
          if (search != null && search.trim().isNotEmpty)
            'search': search.trim(),
        },
      );

      final normalized = _asOptionalMap(response) ?? const <String, dynamic>{};
      final sales = _asList(
        normalized['items'],
      ).map(_asMap).map(_mapSaleSummary).toList(growable: false);
      final meta = _asMap(normalized['meta'] ?? const <String, dynamic>{});
      developer.log(
        'Payments sales payload parsed: items=${sales.length} total=${_asInt(meta['total'])} page=${_asInt(meta['page'], fallback: page)}',
        name: 'SistemaSolares.PaymentsPwa',
      );
      final effectiveSaleId = _resolveSelectedSaleId(sales, selectedSaleId);
      PaymentSaleDetail? selectedSale;
      String? detailErrorMessage;
      if (effectiveSaleId != null) {
        try {
          selectedSale = await fetchSaleDetail(effectiveSaleId);
        } on ApiException catch (error) {
          detailErrorMessage = error.message;
          developer.log(
            'Payments detail failed for sale=$effectiveSaleId: ${error.message}',
            name: 'SistemaSolares.PaymentsPwa',
            error: error,
          );
        } catch (_) {
          detailErrorMessage =
              'No se pudo cargar el detalle de la venta seleccionada.';
          developer.log(
            'Payments detail failed for sale=$effectiveSaleId with unexpected error.',
            name: 'SistemaSolares.PaymentsPwa',
          );
        }
      }

      return PaymentsReadOnlyData(
        sales: sales,
        selectedSale: selectedSale,
        detailErrorMessage: detailErrorMessage,
        total: _asInt(meta['total']),
        page: _asInt(meta['page'], fallback: page),
        limit: _asInt(meta['limit'], fallback: limit),
        totalPages: _resolveTotalPages(
          meta['totalPages'],
          total: _asInt(meta['total']),
          limit: limit,
        ),
      );
    } on ApiException catch (error) {
      developer.log(
        'Payments read model request failed: ${error.message}',
        name: 'SistemaSolares.PaymentsPwa',
        error: error,
      );
      throw ApiException(
        _readFriendlyMessage(error),
        statusCode: error.statusCode,
      );
    } catch (error, stackTrace) {
      developer.log(
        'Payments read model parsing failed.',
        name: 'SistemaSolares.PaymentsPwa',
        error: error,
        stackTrace: stackTrace,
      );
      throw ApiException('No se pudieron cargar los pagos.');
    }
  }

  Future<PaymentSaleDetail> fetchSaleDetail(String id) async {
    try {
      developer.log(
        'Loading payments detail from /payments/sales/$id',
        name: 'SistemaSolares.PaymentsPwa',
      );
      final response = await _apiClient.get('/payments/sales/$id');
      final sale = _asOptionalMap(response);
      if (sale == null) {
        throw ApiException('No se pudo interpretar el detalle de pagos.');
      }
      final summary = _mapSaleSummary(sale);
      final installments = _asList(
        sale['installments'],
      ).map(_asMap).map(_mapInstallment).toList(growable: false);
      final history = _asList(
        sale['payments'],
      ).map(_asMap).map(_mapHistory).toList(growable: false);
      developer.log(
        'Payments detail parsed for sale=$id installments=${installments.length} history=${history.length}',
        name: 'SistemaSolares.PaymentsPwa',
      );

      return PaymentSaleDetail(
        summary: summary,
        monthlyInterest: _asNum(sale['interestRate']),
        termMonths: _asInt(sale['termMonths']),
        salespersonName:
            _readNestedText(sale, ['seller', 'name']) ??
            _readNestedText(sale, ['user', 'fullName']) ??
            'Sin vendedor',
        installments: installments,
        history: history,
      );
    } on ApiException catch (error) {
      developer.log(
        'Payments detail request failed for sale=$id: ${error.message}',
        name: 'SistemaSolares.PaymentsPwa',
        error: error,
      );
      throw ApiException(
        _readFriendlyMessage(error),
        statusCode: error.statusCode,
      );
    } catch (error, stackTrace) {
      developer.log(
        'Payments detail parsing failed for sale=$id.',
        name: 'SistemaSolares.PaymentsPwa',
        error: error,
        stackTrace: stackTrace,
      );
      throw ApiException('No se pudo cargar el detalle de pagos.');
    }
  }

  Map<String, dynamic> _asMap(dynamic value) {
    return _asOptionalMap(value) ?? const <String, dynamic>{};
  }

  List<dynamic> _asList(Object? value) {
    if (value is List<dynamic>) {
      return value;
    }
    if (value is List) {
      return value.cast<dynamic>();
    }
    return const <dynamic>[];
  }

  PaymentSaleSummary _mapSaleSummary(Map<String, dynamic> sale) {
    final client = _asOptionalMap(sale['client']);
    final product = _asOptionalMap(sale['product']);
    final salePayload = _asOptionalMap(sale['syncPayload']);
    final productPayload = _asOptionalMap(product?['syncPayload']);
    final requiredInitialPayment = _readPayloadNum(salePayload, const [
      'monto_inicial_requerido',
      'down_payment',
      'inicial_monto',
    ], fallback: _asNum(sale['downPayment']));
    final paidInitialPayment = _readPayloadNum(
      salePayload,
      const ['monto_inicial_pagado', 'initial_payment_paid'],
      fallback: _min(_asNum(sale['paidAmount']), requiredInitialPayment),
    );
    final pendingInitialPayment = _readPayloadNum(salePayload, const [
      'monto_inicial_pendiente',
      'initial_payment_pending',
    ], fallback: _max(requiredInitialPayment - paidInitialPayment, 0));

    return PaymentSaleSummary(
      id: sale['id']?.toString() ?? '',
      clientName: _buildClientName(client),
      clientDocumentId: client?['documentId']?.toString().trim() ?? '',
      clientPhone: client?['phone']?.toString().trim() ?? '',
      lotLabel: _resolveLotLabel(product, productPayload, salePayload),
      contractNumber: sale['contractNumber']?.toString().trim() ?? '',
      status: sale['status']?.toString().trim() ?? 'active',
      saleDate: _parseDate(sale['saleDate']),
      totalAmount: _asNum(sale['totalAmount']),
      totalPaid: _asNum(sale['paidAmount']),
      pendingBalance: _asNum(sale['outstandingBalance']),
      requiredInitialPayment: requiredInitialPayment,
      paidInitialPayment: paidInitialPayment,
      pendingInitialPayment: pendingInitialPayment,
    );
  }

  PaymentInstallmentView _mapInstallment(Map<String, dynamic> installment) {
    final dueDate = _parseDate(installment['dueDate']);
    final amount = _asNum(installment['amount']);
    final paidAmount = _asNum(installment['paidAmount']);
    return PaymentInstallmentView(
      id: installment['id']?.toString() ?? '',
      installmentNumber: _asInt(installment['installmentNumber']),
      dueDate: dueDate,
      amount: amount,
      paidAmount: paidAmount,
      remainingAmount: _max(amount - paidAmount, 0),
      status: installment['status']?.toString().trim() ?? 'pending',
      statusLabel: _buildInstallmentStatusLabel(
        installment['status']?.toString().trim() ?? 'pending',
        dueDate,
      ),
    );
  }

  PaymentHistoryView _mapHistory(Map<String, dynamic> payment) {
    final syncPayload = _asOptionalMap(payment['syncPayload']);
    final installment = _asOptionalMap(payment['installment']);
    final installmentNumber = _asInt(installment?['installmentNumber']);
    final type =
        _readPayloadText(syncPayload, const ['payment_type', 'tipo_pago']) ??
        (installmentNumber > 0 ? 'cuota' : 'abono_capital');

    return PaymentHistoryView(
      id: payment['id']?.toString() ?? '',
      paymentDate: _parseDate(payment['paymentDate']),
      amount: _asNum(payment['amount']),
      method: payment['method']?.toString().trim() ?? '',
      reference: payment['reference']?.toString().trim() ?? '',
      type: type,
      typeLabel: _paymentTypeLabel(
        type,
        installmentNumber > 0 ? installmentNumber : null,
      ),
      installmentNumber: installmentNumber > 0 ? installmentNumber : null,
    );
  }

  Object? _normalize(dynamic value) {
    if (value is Map<dynamic, dynamic>) {
      return _asMap(value);
    }
    if (value is List) {
      return value.map(_normalize).toList(growable: false);
    }
    return value;
  }

  int _asInt(Object? value, {int fallback = 0}) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  int _resolveTotalPages(
    Object? value, {
    required int total,
    required int limit,
  }) {
    final parsed = _asInt(value);
    if (parsed > 0) {
      return parsed;
    }
    if (total <= 0) {
      return 1;
    }
    final safeLimit = limit <= 0 ? 1 : limit;
    return (total / safeLimit).ceil();
  }

  String? _resolveSelectedSaleId(
    List<PaymentSaleSummary> sales,
    String? selectedSaleId,
  ) {
    if (selectedSaleId != null &&
        sales.any((sale) => sale.id == selectedSaleId)) {
      return selectedSaleId;
    }
    if (sales.isEmpty) {
      return null;
    }
    return sales.first.id;
  }

  Map<String, dynamic>? _asOptionalMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value.map((key, item) => MapEntry(key, _normalize(item)));
    }
    if (value is Map) {
      return value.map(
        (key, item) => MapEntry(key.toString(), _normalize(item)),
      );
    }
    return null;
  }

  DateTime? _parseDate(Object? value) {
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw);
  }

  double _asNum(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _buildClientName(Map<String, dynamic>? client) {
    final firstName = client?['firstName']?.toString().trim() ?? '';
    final lastName = client?['lastName']?.toString().trim() ?? '';
    final fullName = [
      firstName,
      lastName,
    ].where((value) => value.isNotEmpty).join(' ').trim();
    return fullName.isEmpty ? 'Cliente no disponible' : fullName;
  }

  String _resolveLotLabel(
    Map<String, dynamic>? product,
    Map<String, dynamic>? productPayload,
    Map<String, dynamic>? salePayload,
  ) {
    final productName = product?['name']?.toString().trim() ?? '';
    if (productName.isNotEmpty) {
      return productName;
    }

    final block =
        _readPayloadText(salePayload, const [
          'manzana_numero',
          'lot_block',
          'block_number',
        ]) ??
        _readPayloadText(productPayload, const [
          'manzana_numero',
          'lot_block',
          'block_number',
        ]);
    final lot =
        _readPayloadText(salePayload, const ['solar_numero', 'lot_number']) ??
        _readPayloadText(productPayload, const ['solar_numero', 'lot_number']);
    if ((block ?? '').isNotEmpty || (lot ?? '').isNotEmpty) {
      return 'M${block ?? '-'}-S${lot ?? '-'}';
    }
    return 'Sin solar';
  }

  double _readPayloadNum(
    Map<String, dynamic>? payload,
    List<String> keys, {
    double fallback = 0,
  }) {
    if (payload == null) {
      return fallback;
    }
    for (final key in keys) {
      if (payload.containsKey(key)) {
        return _asNum(payload[key]);
      }
    }
    return fallback;
  }

  String? _readPayloadText(Map<String, dynamic>? payload, List<String> keys) {
    if (payload == null) {
      return null;
    }
    for (final key in keys) {
      final value = payload[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  String? _readNestedText(Map<String, dynamic> source, List<String> path) {
    Object? current = source;
    for (final segment in path) {
      if (current is! Map) {
        return null;
      }
      current = current[segment];
    }
    final value = current?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  String _buildInstallmentStatusLabel(String status, DateTime? dueDate) {
    if (status == 'paid') {
      return 'pagada';
    }
    if (status == 'cancelled') {
      return 'cancelada';
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final normalizedDueDate = dueDate == null
        ? null
        : DateTime(dueDate.year, dueDate.month, dueDate.day);
    if (normalizedDueDate != null && normalizedDueDate.isBefore(today)) {
      return status == 'partial' ? 'vencida parcial' : 'vencida';
    }
    if (status == 'partial') {
      return 'parcial';
    }
    return 'pendiente';
  }

  String _paymentTypeLabel(String paymentType, int? installmentNumber) {
    return switch (paymentType) {
      'apartado' => 'Pago de apartado',
      'abono_inicial' => 'Abono a inicial',
      'abono_capital' => 'Abono a capital',
      _ => 'Pago de cuota #${installmentNumber ?? '-'}',
    };
  }

  String _readFriendlyMessage(ApiException error) {
    if (error.message.trim() == 'Sistema en modo solo lectura') {
      return 'Esta accion no esta disponible en el panel web';
    }
    return switch (error.statusCode) {
      401 => 'Tu sesion vencio. Inicia sesion nuevamente para consultar pagos.',
      403 => 'No tienes permiso para consultar pagos en el panel web.',
      404 => 'No se encontraron pagos o ventas para la consulta actual.',
      500 => 'No se pudieron cargar los pagos en este momento.',
      _ =>
        error.message.trim().isEmpty
            ? 'No se pudieron cargar los pagos.'
            : error.message,
    };
  }

  double _min(double left, double right) => left < right ? left : right;

  double _max(double left, double right) => left > right ? left : right;
}
