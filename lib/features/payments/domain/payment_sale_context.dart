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
}
