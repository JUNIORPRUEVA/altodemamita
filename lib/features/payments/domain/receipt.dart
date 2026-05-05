import '../../installments/domain/installment.dart';
import '../../settings/domain/company_info.dart';
import '../../../core/utils/dominican_formatters.dart';
import '../domain/payment_history_item.dart';
import '../domain/payment_sale_option.dart';

/// Modelo de recibo de pago dinámico
/// Contiene toda la información necesaria para generar un recibo formal e imprimible
class Receipt {
  const Receipt({
    required this.paymentId,
    required this.receiptNumber,
    required this.paymentDate,
    required this.sale,
    required this.payment,
    required this.payments,
    required this.company,
    required this.paidInstallment,
    this.paidCapitalAmount,
    required this.installmentsPaid,
    required this.installmentsRemaining,
    required this.totalPaidAccumulated,
    required this.accountStatusLabel,
    this.nextInstallmentNumber,
    this.nextInstallmentDueDate,
    this.nextInstallmentAmount,
    this.monthlyInterest,
    required this.blockNumber,
    required this.lotNumber,
    required this.installmentCount,
    required this.userName,
    this.paymentRegisteredByName = '',
    this.sellerName,
    required this.conditionsOfPayment,
    required this.note,
  });

  final int paymentId;
  final String receiptNumber;
  final DateTime paymentDate;
  final PaymentSaleOption sale;
  final PaymentHistoryItem payment;
  final List<PaymentHistoryItem> payments;
  final CompanyInfo company;
  final Installment? paidInstallment; // La cuota que se pagó en este recibo
  final double? paidCapitalAmount; // Si hubo abono a capital
  final int installmentsPaid; // Cuotas pagadas hasta ahora
  final int installmentsRemaining; // Cuotas pendientes
  final double totalPaidAccumulated;
  final String accountStatusLabel;
  final int? nextInstallmentNumber;
  final DateTime? nextInstallmentDueDate;
  final double? nextInstallmentAmount;
  final double? monthlyInterest; // Interés mensual del solar
  final String blockNumber;
  final String lotNumber;
  final int installmentCount;
  final String userName;
  final String paymentRegisteredByName;
  final String? sellerName;
  final String conditionsOfPayment;
  final String note;

  /// Retorna el concepto del pago (Cuota X o Abono a Capital)
  String get paymentConcept {
    final concepts = paymentBreakdown.map((entry) => entry.label).toList();
    if (concepts.isEmpty) {
      return 'Pago';
    }
    return concepts.join(' + ');
  }

  /// Retorna el monto pagado formateado
  String get formattedAmount {
    return formatRdCurrency(totalAmount);
  }

  double get totalAmount {
    return payments.fold<double>(0, (sum, item) => sum + item.amountPaid);
  }

  double get currentOutstandingBalance {
    return sale.pendingBalance + sale.pendingInitialPayment;
  }

  double get remainingFinancedBalance {
    return sale.pendingBalance;
  }

  double get remainingInitialBalance {
    return sale.pendingInitialPayment;
  }

  String get paymentMethodLabel {
    final methods = payments
        .map((item) => item.paymentMethod.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();

    if (methods.isEmpty) {
      return '-';
    }

    return methods.map(_capitalize).join(' / ');
  }

  List<ReceiptLineItem> get paymentBreakdown {
    return payments
        .map((item) {
          final label = switch (item.paymentType) {
            'apartado' => 'Pago de apartado',
            'abono_inicial' => 'Abono a inicial',
            'abono_capital' => 'Abono a capital',
            _ => 'Cuota #${item.installmentNumber ?? '-'}',
          };
          return ReceiptLineItem(label: label, amount: item.amountPaid);
        })
        .toList(growable: false);
  }

  /// Retorna la fecha formateada para impresión
  String get formattedDate {
    final months = [
      '',
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];
    return '${paymentDate.day} de ${months[paymentDate.month]} de ${paymentDate.year}';
  }

  /// Retorna la fecha corta formateada
  String get formattedDateShort {
    final month = paymentDate.month.toString().padLeft(2, '0');
    final day = paymentDate.day.toString().padLeft(2, '0');
    return '$day/$month/${paymentDate.year}';
  }

  String formatShortDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$day/$month/${value.year}';
  }

  String get amountInWords {
    final wholePart = totalAmount.floor();
    final cents = ((totalAmount - wholePart) * 100).round();
    final wholeWords = _numberToSpanish(wholePart);
    return '$wholeWords pesos con ${cents.toString().padLeft(2, '0')}/100';
  }

  String get yearsToPayLabel {
    if (installmentCount <= 0) {
      return '-';
    }

    final years = installmentCount ~/ 12;
    final months = installmentCount % 12;
    if (years == 0) {
      return '$installmentCount mes${installmentCount == 1 ? '' : 'es'}';
    }
    if (months == 0) {
      return '$years año${years == 1 ? '' : 's'}';
    }
    return '$years año${years == 1 ? '' : 's'} y $months mes${months == 1 ? '' : 'es'}';
  }

  String get deliveredBy {
    final seller = (sellerName ?? '').trim();
    final operator = receivedBy.trim().toLowerCase();
    if (seller.isNotEmpty && seller.toLowerCase() != operator) {
      return seller;
    }
    return receivedFrom;
  }

  String get receivedFrom => sale.clientName;

  String get receivedBy {
    final paymentUser = paymentRegisteredByName.trim();
    if (paymentUser.isNotEmpty) {
      return paymentUser;
    }

    final saleUser = userName.trim();
    if (saleUser.isNotEmpty) {
      return saleUser;
    }

    final seller = (sellerName ?? '').trim();
    if (seller.isNotEmpty) {
      return seller;
    }
    return company.nombre;
  }

  static String _capitalize(String value) {
    if (value.isEmpty) {
      return value;
    }

    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

  static String _numberToSpanish(int value) {
    if (value == 0) {
      return 'cero';
    }

    const units = [
      '',
      'uno',
      'dos',
      'tres',
      'cuatro',
      'cinco',
      'seis',
      'siete',
      'ocho',
      'nueve',
    ];
    const teens = [
      'diez',
      'once',
      'doce',
      'trece',
      'catorce',
      'quince',
      'dieciseis',
      'diecisiete',
      'dieciocho',
      'diecinueve',
    ];
    const tens = [
      '',
      '',
      'veinte',
      'treinta',
      'cuarenta',
      'cincuenta',
      'sesenta',
      'setenta',
      'ochenta',
      'noventa',
    ];
    const hundreds = [
      '',
      'ciento',
      'doscientos',
      'trescientos',
      'cuatrocientos',
      'quinientos',
      'seiscientos',
      'setecientos',
      'ochocientos',
      'novecientos',
    ];

    String convertBelowHundred(int number) {
      if (number < 10) {
        return units[number];
      }
      if (number < 20) {
        return teens[number - 10];
      }
      if (number < 30) {
        return number == 20 ? 'veinte' : 'veinti${units[number - 20]}';
      }
      final ten = number ~/ 10;
      final unit = number % 10;
      return unit == 0 ? tens[ten] : '${tens[ten]} y ${units[unit]}';
    }

    String convertBelowThousand(int number) {
      if (number < 100) {
        return convertBelowHundred(number);
      }
      if (number == 100) {
        return 'cien';
      }
      final hundred = number ~/ 100;
      final remainder = number % 100;
      return remainder == 0
          ? hundreds[hundred]
          : '${hundreds[hundred]} ${convertBelowHundred(remainder)}';
    }

    if (value < 1000) {
      return convertBelowThousand(value);
    }
    if (value < 1000000) {
      final thousands = value ~/ 1000;
      final remainder = value % 1000;
      final thousandsText = thousands == 1
          ? 'mil'
          : '${convertBelowThousand(thousands)} mil';
      return remainder == 0
          ? thousandsText
          : '$thousandsText ${convertBelowThousand(remainder)}';
    }

    final millions = value ~/ 1000000;
    final remainder = value % 1000000;
    final millionsText = millions == 1
        ? 'un millon'
        : '${_numberToSpanish(millions)} millones';
    return remainder == 0
        ? millionsText
        : '$millionsText ${_numberToSpanish(remainder)}';
  }
}

class ReceiptLineItem {
  const ReceiptLineItem({required this.label, required this.amount});

  final String label;
  final double amount;
}
