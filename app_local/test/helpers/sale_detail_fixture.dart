import 'package:sistema_solares/features/installments/domain/installment.dart';
import 'package:sistema_solares/features/sales/domain/sale.dart';
import 'package:sistema_solares/features/sales/domain/sale_detail.dart';

/// Fixture mínimo de detalle de venta para pruebas de presentación.
SaleDetail saleDetailFixture({
  int saleId = 10,
  String clientName = 'THELEMARQUE WISMIQUE',
  int installmentCount = 6,
  double salePrice = 750000,
  double pendingBalance = 631250,
}) {
  final date = DateTime(2026, 3, 6);
  return SaleDetail(
    sale: Sale(
      id: saleId,
      clientId: 1,
      lotId: 1,
      userId: 1,
      saleDate: date,
      salePrice: salePrice,
      downPaymentPercentage: 10,
      downPaymentAmount: 75000,
      requiredInitialPayment: 75000,
      paidInitialPayment: 75000,
      pendingInitialPayment: 0,
      financedBalance: 675000,
      pendingBalance: pendingBalance,
      monthlyInterest: 1,
      installmentCount: installmentCount,
      status: 'activa',
      createdAt: date,
      updatedAt: date,
    ),
    clientName: clientName,
    clientDocumentId: '001-0000000-1',
    lotDisplayCode: 'MM-B-1-S446',
    lotArea: 300,
    lotPricePerSquareMeter: 2500,
    userName: 'Administrador',
    initialPaymentMethod: 'Efectivo',
    sellerName: 'Vendedor Uno',
    installments: [
      for (var number = 1; number <= installmentCount; number++)
        _installment(number, saleId),
    ],
  );
}

Installment _installment(int number, int saleId) {
  final dueDate = DateTime(2026, 1 + number, 15);
  return Installment(
    id: number,
    saleId: saleId,
    installmentNumber: number,
    dueDate: dueDate,
    openingBalance: 675000,
    principalAmount: 11000,
    interestAmount: 1500,
    totalAmount: 12500,
    paidAmount: number <= 2 ? 12500 : 0,
    paidPrincipalAmount: 0,
    paidInterestAmount: 0,
    endingBalance: 664000,
    status: number <= 2 ? 'pagada' : 'pendiente',
    createdAt: dueDate,
    updatedAt: dueDate,
  );
}

/// Lista suelta de cuotas para la tabla plana.
List<Installment> installmentsFixture({int count = 24, int saleId = 10}) {
  return [for (var number = 1; number <= count; number++) _installment(number, saleId)];
}
