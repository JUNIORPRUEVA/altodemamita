import '../../installments/domain/installment.dart';
import 'payment_history_item.dart';
import 'payment_sale_option.dart';

class PaymentSaleContext {
  const PaymentSaleContext({
    required this.sale,
    required this.monthlyInterest,
    required this.installments,
    required this.history,
    this.actionableInstallment,
  });

  final PaymentSaleOption sale;
  final double monthlyInterest;
  final List<Installment> installments;
  final List<PaymentHistoryItem> history;
  final Installment? actionableInstallment;

  /// Returns overdue installments using due date + open balance criteria,
  /// matching the behavior shown in the installments table UI.
  List<Installment> get overdueInstallments {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final items = installments.where((installment) {
      final status = installment.status.trim().toLowerCase();
      final isClosed =
          status == 'pagada' || status == 'ajustada' || status == 'cancelada';
      if (isClosed) {
        return false;
      }
      if (installment.remainingAmount <= 0.009) {
        return false;
      }
      return installment.dueDate.isBefore(todayStart);
    }).toList(growable: false);

    items.sort((a, b) {
      final byDate = a.dueDate.compareTo(b.dueDate);
      if (byDate != 0) {
        return byDate;
      }
      return a.installmentNumber.compareTo(b.installmentNumber);
    });
    return items;
  }
}
