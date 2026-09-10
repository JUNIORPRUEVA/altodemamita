import '../../installments/domain/installment.dart';
import 'payment_sale_option.dart';

class PaymentWorkQueue {
  const PaymentWorkQueue({
    required this.entries,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.counts,
  });

  final List<PaymentWorkQueueEntry> entries;
  final int total;
  final int page;
  final int pageSize;
  final PaymentWorkQueueCounts counts;
}

class PaymentWorkQueueEntry {
  const PaymentWorkQueueEntry({required this.sale, required this.installment});

  final PaymentSaleOption sale;
  final Installment installment;
}

class PaymentWorkQueueCounts {
  const PaymentWorkQueueCounts({
    required this.overdue,
    required this.dueToday,
    required this.pending,
    required this.partial,
  });

  final int overdue;
  final int dueToday;
  final int pending;
  final int partial;
}
