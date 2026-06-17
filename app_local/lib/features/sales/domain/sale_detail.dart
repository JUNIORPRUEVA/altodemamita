import '../../installments/domain/installment.dart';
import 'sale.dart';

class SaleDetail {
  const SaleDetail({
    required this.sale,
    required this.clientName,
    required this.clientDocumentId,
    required this.lotDisplayCode,
    required this.lotArea,
    required this.lotPricePerSquareMeter,
    required this.userName,
    required this.initialPaymentMethod,
    this.sellerName,
    this.sellerDocumentId,
    this.sellerPhone,
    required this.installments,
  });

  final Sale sale;
  final String clientName;
  final String clientDocumentId;
  final String lotDisplayCode;
  final double lotArea;
  final double lotPricePerSquareMeter;
  final String userName;
  final String initialPaymentMethod;
  final String? sellerName;
  final String? sellerDocumentId;
  final String? sellerPhone;
  final List<Installment> installments;

  double get lotTotalPrice =>
      (lotArea * lotPricePerSquareMeter * 100).roundToDouble() / 100;

  int get activeInstallmentCount => installments.length;

  int get remainingInstallmentCount => installments
      .where((item) => item.remainingAmount > 0.009)
      .length;

  int get paidInstallmentCount =>
      activeInstallmentCount - remainingInstallmentCount;

  int get reducedInstallmentCount {
    final reduction = sale.installmentCount - activeInstallmentCount;
    return reduction > 0 ? reduction : 0;
  }

  int get overdueInstallmentCount {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    return installments.where((i) {
      if (i.status == 'pagada' || i.status == 'ajustada') return false;
      if (i.remainingAmount <= 0.009) return false;
      final dueDate = DateTime(i.dueDate.year, i.dueDate.month, i.dueDate.day);
      return dueDate.isBefore(todayDate);
    }).length;
  }
}