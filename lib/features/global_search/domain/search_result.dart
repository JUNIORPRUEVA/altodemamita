import '../../clients/domain/client.dart';
import '../../installments/domain/installment_detail.dart';
import '../../lots/domain/lot.dart';

class GlobalSearchResult {
  const GlobalSearchResult({
    this.client,
    this.lot,
    this.relatedSales = const [],
    this.relatedInstallments = const [],
    this.relatedPayments = const [],
    this.matchType = 'unknown', // 'client', 'lot'
  });

  final Client? client;
  final Lot? lot;
  final List<Map<String, dynamic>> relatedSales;
  final List<InstallmentDetail> relatedInstallments;
  /// Historial de pagos de todas las ventas relacionadas.
  final List<Map<String, dynamic>> relatedPayments;
  final String matchType;

  String get displayName {
    if (client != null) {
      return client!.fullName;
    }
    if (lot != null) {
      return lot!.displayCode;
    }
    return 'Resultado desconocido';
  }

  String get displaySubtitle {
    final parts = <String>[];
    
    if (client != null) {
      if (client!.documentId.isNotEmpty) {
        parts.add('Cédula: ${client!.documentId}');
      }
      if (client!.phone?.isNotEmpty ?? false) {
        parts.add('Tel: ${client!.phone}');
      }
      parts.add('${relatedSales.length} venta(s)');
    }
    
    if (lot != null) {
      parts.add('Manzana ${lot!.blockNumber}');
      parts.add('Solar ${lot!.lotNumber}');
      parts.add('Estado: ${lot!.status}');
    }
    
    return parts.join(' • ');
  }

  double get totalPendingAmount {
    return relatedInstallments.fold(
      0.0,
      (sum, inst) => sum + inst.remainingAmount,
    );
  }

  int get pendingInstallmentsCount {
    return relatedInstallments.where((inst) => inst.remainingAmount > 0).length;
  }
}
