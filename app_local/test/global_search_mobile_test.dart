import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_solares/core/responsive/app_breakpoints.dart';
import 'package:sistema_solares/features/clients/domain/client.dart';
import 'package:sistema_solares/features/global_search/domain/search_result.dart';
import 'package:sistema_solares/features/global_search/presentation/global_search_mobile.dart';
import 'package:sistema_solares/features/global_search/presentation/global_search_page.dart';
import 'package:sistema_solares/features/installments/domain/installment_detail.dart';
import 'package:sistema_solares/features/lots/domain/lot.dart';
import 'package:sistema_solares/shared/mobile/mobile_screens.dart';

import 'helpers/responsive_test_harness.dart';

const List<double> _widths = [320, 360, 375, 390, 412, 430, 768];

/// Alto amplio: así TODAS las secciones del detalle se montan y las
/// aserciones de contenido no dependen del scroll.
const Size _tallPhone = Size(390, 2200);

/// Alto amplio con ancho variable (para las pruebas de desbordes).
Size _tall(double width) => Size(width, 2600);

final _now = DateTime(2026, 6, 9, 10, 30);

Client _client() => Client(
  id: 1,
  fullName: 'THELEMARQUE WISMIQUE',
  documentId: '001-0000000-1',
  phone: '809-555-0101',
  address: 'Calle Principal 12',
  createdAt: _now,
  updatedAt: _now,
);

Lot _lot() => Lot(
  id: 2,
  blockNumber: 'M5',
  lotNumber: 'S10',
  area: 300,
  pricePerSquareMeter: 2500,
  status: 'disponible',
  createdAt: _now,
  updatedAt: _now,
);

Map<String, dynamic> _sale() => <String, dynamic>{
  // El id existe en el modelo, pero la UI NUNCA debe mostrarlo.
  'id': 10,
  'estado': 'activa',
  'fecha_venta': '2026-06-09T10:30:00.000',
  'manzana_numero': 'M5',
  'solar_numero': 'S10',
  'precio_venta': 951537.38,
  'monto_inicial_requerido': 150000.0,
  'monto_inicial_pagado': 150000.0,
  'monto_inicial_pendiente': 0.0,
  'saldo_financiado': 801537.38,
  'saldo_pendiente': 650000.0,
  'cantidad_cuotas': 24,
  'vendedor_nombre': 'Vendedor Uno',
  'usuario_nombre': 'Administrador',
  'solar_id': 2,
};

InstallmentDetail _installment({
  required int number,
  required double total,
  required double paid,
  required DateTime dueDate,
  double interest = 1500,
}) => InstallmentDetail(
  id: number,
  installmentNumber: number,
  saleId: 10,
  clientName: 'THELEMARQUE WISMIQUE',
  clientDocumentId: '001-0000000-1',
  lotCode: 'M5-S10',
  dueDate: dueDate,
  openingBalance: 675000,
  principalAmount: total - interest,
  interestAmount: interest,
  totalAmount: total,
  paidAmount: paid,
  remainingAmount: total - paid,
  endingBalance: 664000,
  status: 'pendiente',
);

Map<String, dynamic> _payment({
  String tipo = 'cuota',
  double monto = 120000,
  String fecha = '2026-01-15T09:00:00.000',
  String metodo = 'efectivo',
  int? cuota = 3,
  int? ano,
  String referencia = 'REC-001',
}) => <String, dynamic>{
  'id': 99,
  'tipo_pago': tipo,
  'monto_pagado': monto,
  'fecha_pago': fecha,
  'metodo_pago': metodo,
  'numero_cuota': cuota,
  'ano_a_pagar': ano,
  'referencia': referencia,
};

/// Resultado tipo cliente con 1 venta, 2 cuotas (1 pagada) y 2 pagos.
GlobalSearchResult _clientResult() => GlobalSearchResult(
  client: _client(),
  relatedSales: [_sale()],
  relatedInstallments: [
    _installment(
      number: 3,
      total: 120000,
      paid: 120000,
      dueDate: DateTime(2026, 1, 15),
    ),
    _installment(
      number: 4,
      total: 125000,
      paid: 0,
      dueDate: DateTime(2030, 6, 15),
    ),
  ],
  relatedPayments: [
    _payment(),
    _payment(
      tipo: 'abono_capital',
      monto: 50000,
      fecha: '2026-02-20T11:15:00.000',
      metodo: 'transferencia',
      cuota: null,
      ano: 2026,
      referencia: '',
    ),
  ],
);

/// Plan largo (120 cuotas) + pagos, para verificar que se lista todo sin
/// desbordes en cualquier ancho.
GlobalSearchResult _longPlanResult() => GlobalSearchResult(
  client: _client(),
  relatedSales: [_sale()],
  relatedInstallments: [
    for (var index = 1; index <= 120; index++)
      _installment(
        number: index,
        total: 12500,
        paid: index == 1 ? 12500 : 0,
        dueDate: DateTime(2027, 1, 15).add(Duration(days: 30 * index)),
      ),
  ],
  relatedPayments: [
    _payment(),
    _payment(
      tipo: 'apartado',
      monto: 25000,
      fecha: '2026-01-05T08:00:00.000',
      metodo: 'cheque',
      cuota: null,
      ano: null,
      referencia: 'REC-000',
    ),
  ],
);

GlobalSearchResult _lotResult() =>
    GlobalSearchResult(lot: _lot(), matchType: 'lot');

Widget _view({
  required TextEditingController controller,
  String query = 'juan',
  List<GlobalSearchResult>? results,
  bool isLoading = false,
  bool searchFailed = false,
  VoidCallback? onOpenSales,
  void Function(int? saleId)? onOpenInstallments,
  void Function(int? saleId)? onOpenPayments,
}) => GlobalSearchMobileView(
  controller: controller,
  query: query,
  results: results ?? [_clientResult()],
  isLoading: isLoading,
  searchFailed: searchFailed,
  onSearch: () {},
  onClear: () {},
  onRetry: () {},
  onOpenClients: () {},
  onOpenLots: () {},
  onOpenSales: onOpenSales ?? () {},
  onOpenInstallments: onOpenInstallments ?? (_) {},
  onOpenPayments: onOpenPayments ?? (_) {},
);

/// Detalle con todos los accesos habilitados (como en la app real).
Widget _detailWithLinks(GlobalSearchResult result) => SearchResultDetailPage(
  result: result,
  onOpenClients: () {},
  onOpenLots: () {},
  onOpenSales: () {},
  onOpenInstallments: (_) {},
  onOpenPayments: (_) {},
);

/// Monta el detalle dentro de una pila con una pantalla previa, para poder
/// verificar que las acciones cierran el detalle y navegan.
Widget _detailHarness({
  required GlobalSearchResult result,
  void Function(int? saleId)? onOpenInstallments,
  void Function(int? saleId)? onOpenPayments,
  VoidCallback? onOpenSales,
}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SearchResultDetailPage(
                  result: result,
                  onOpenSales: onOpenSales,
                  onOpenInstallments: onOpenInstallments,
                  onOpenPayments: onOpenPayments,
                ),
              ),
            ),
            child: const Text('abrir detalle'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('Buscador mobile - buscador superior', () {
    testWidgets('una sola linea, lupa dentro del campo y limpiar alineado', (
      tester,
    ) async {
      useTestSize(tester, const Size(390, 844));
      final controller = TextEditingController(text: 'juan');
      addTearDown(controller.dispose);

      await tester.pumpWidget(testApp(_view(controller: controller)));
      await tester.pumpAndSettle();

      // La lupa vive DENTRO del campo.
      expect(
        find.descendant(
          of: find.byType(TextField),
          matching: find.byIcon(Icons.search_rounded),
        ),
        findsOneWidget,
      );
      // La acción de limpiar está alineada en la misma línea (sufijo).
      expect(
        find.descendant(
          of: find.byType(TextField),
          matching: find.byIcon(Icons.close_rounded),
        ),
        findsOneWidget,
      );
      // Sigue siendo compacto, pero con jerarquía visual propia del buscador.
      expect(
        tester.getSize(find.byType(TextField)).height,
        lessThanOrEqualTo(52),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('sin consulta muestra el estado inicial', (tester) async {
      useTestSize(tester, const Size(390, 844));
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        testApp(_view(controller: controller, query: '', results: const [])),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Busca clientes, solares, ventas y cuotas'),
        findsOneWidget,
      );
    });

    testWidgets('sin resultados ofrece limpiar la busqueda', (tester) async {
      useTestSize(tester, const Size(390, 844));
      final controller = TextEditingController(text: 'zzz');
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        testApp(_view(controller: controller, query: 'zzz', results: const [])),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('No hay resultados'), findsOneWidget);
      expect(find.text('Limpiar búsqueda'), findsOneWidget);
    });

    testWidgets('error de busqueda muestra reintentar', (tester) async {
      useTestSize(tester, const Size(390, 844));
      final controller = TextEditingController(text: 'juan');
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        testApp(
          _view(controller: controller, results: const [], searchFailed: true),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No pudimos completar la búsqueda.'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
    });
  });

  group('Buscador mobile - lista de resultados', () {
    testWidgets('tarjeta ordenada con nombre, cedula y pendiente con miles', (
      tester,
    ) async {
      useTestSize(tester, const Size(390, 900));
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(testApp(_view(controller: controller)));
      await tester.pumpAndSettle();

      expect(find.text('THELEMARQUE WISMIQUE'), findsOneWidget);
      expect(find.text('Cédula: 001-0000000-1'), findsOneWidget);
      expect(find.text('RD\$125,000.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('resultado de solar usa manzana y solar', (tester) async {
      useTestSize(tester, const Size(390, 900));
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        testApp(_view(controller: controller, results: [_lotResult()])),
      );
      await tester.pumpAndSettle();

      expect(find.text('Manzana M5 · Solar S10'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Buscador mobile - detalle a pantalla completa', () {
    testWidgets('abre pantalla completa ocupando todo el viewport', (
      tester,
    ) async {
      useTestSize(tester, const Size(390, 844));
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(testApp(_view(controller: controller)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('THELEMARQUE WISMIQUE'));
      await tester.pumpAndSettle();

      // Nunca un modal angosto flotante.
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(SearchResultDetailPage), findsOneWidget);

      final size = tester.getSize(find.byType(MobileDetailScaffold));
      expect(size.width, 390);
      expect(size.height, 844);
    });

    testWidgets('la navegacion ocurre antes de cualquier carga', (
      tester,
    ) async {
      useTestSize(tester, _tallPhone);
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(testApp(_view(controller: controller)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('THELEMARQUE WISMIQUE'));
      // Dos frames: inicia la transición y monta el detalle. No se espera
      // ninguna carga (no hay pumpAndSettle) antes de navegar.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byType(SearchResultDetailPage), findsOneWidget);
      expect(find.text('Detalle'), findsOneWidget);
    });

    testWidgets('el contenido hace scroll vertical', (tester) async {
      useTestSize(tester, const Size(390, 844));
      await tester.pumpWidget(
        testApp(SearchResultDetailPage(result: _clientResult())),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ListView), findsWidgets);
      final before = tester.getTopLeft(find.text('DATOS DE CONTACTO')).dy;
      await tester.drag(find.byType(ListView).first, const Offset(0, -200));
      await tester.pumpAndSettle();
      final after = tester.getTopLeft(find.text('DATOS DE CONTACTO')).dy;

      expect(after, lessThan(before));
    });

    testWidgets('agrupa la informacion en secciones claras', (tester) async {
      useTestSize(tester, _tallPhone);
      await tester.pumpWidget(testApp(_detailWithLinks(_clientResult())));
      await tester.pumpAndSettle();

      expect(find.text('DATOS DE CONTACTO'), findsOneWidget);
      expect(find.text('VENTA'), findsOneWidget);
      expect(find.text('PLAN DE CUOTAS (2)'), findsOneWidget);
      expect(find.text('PAGOS REGISTRADOS (2)'), findsOneWidget);
      expect(find.text('ACCESOS'), findsOneWidget);
    });

    testWidgets('no muestra identificadores tecnicos', (tester) async {
      useTestSize(tester, _tallPhone);
      await tester.pumpWidget(
        testApp(SearchResultDetailPage(result: _clientResult())),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Venta ID'), findsNothing);
      expect(find.textContaining('Solar #'), findsNothing);
      expect(find.textContaining('Sync'), findsNothing);
      expect(find.textContaining('UUID'), findsNothing);
      expect(find.textContaining('companyId'), findsNothing);
      expect(find.textContaining('remoteId'), findsNothing);
      // El id de la venta (10) no se pinta como valor suelto.
      expect(find.text('10'), findsNothing);
    });

    testWidgets('montos completos con separador de miles', (tester) async {
      useTestSize(tester, _tallPhone);
      await tester.pumpWidget(
        testApp(SearchResultDetailPage(result: _clientResult())),
      );
      await tester.pumpAndSettle();

      // Precio de la venta y totales del plan, todos con separador de miles.
      expect(find.text('RD\$951,537.38'), findsWidgets);
      expect(find.text('RD\$245,000.00'), findsOneWidget);
      expect(find.text('RD\$120,000.00'), findsWidgets);
      expect(find.textContaining('RD\$951537.38'), findsNothing);
      expect(find.textContaining('RD\$245000.00'), findsNothing);
    });

    testWidgets('fechas en formato español', (tester) async {
      useTestSize(tester, _tallPhone);
      await tester.pumpWidget(
        testApp(SearchResultDetailPage(result: _clientResult())),
      );
      await tester.pumpAndSettle();

      expect(find.text('09/06/2026 10:30'), findsWidgets);
    });

    testWidgets('el plan lista TODAS las cuotas dentro del detalle', (
      tester,
    ) async {
      useTestSize(tester, _tallPhone);
      await tester.pumpWidget(
        testApp(SearchResultDetailPage(result: _longPlanResult())),
      );
      await tester.pumpAndSettle();

      expect(find.text('PLAN DE CUOTAS (120)'), findsOneWidget);
      for (var index = 1; index <= 120; index++) {
        expect(
          find.text('Cuota $index'),
          findsOneWidget,
          reason: 'la cuota $index debe verse en el detalle',
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('plan largo a 320 px sin desbordes', (tester) async {
      useTestSize(tester, const Size(320, 844));
      await tester.pumpWidget(
        testApp(SearchResultDetailPage(result: _longPlanResult())),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('los pagos se listan con concepto, fecha, metodo y monto', (
      tester,
    ) async {
      useTestSize(tester, _tallPhone);
      await tester.pumpWidget(
        testApp(SearchResultDetailPage(result: _clientResult())),
      );
      await tester.pumpAndSettle();

      expect(find.text('PAGOS REGISTRADOS (2)'), findsOneWidget);
      expect(find.text('Cuota #3'), findsOneWidget);
      expect(find.text('Abono a capital'), findsOneWidget);
      expect(find.text('15/01/2026 09:00 · Efectivo'), findsOneWidget);
      expect(find.textContaining('Transferencia'), findsOneWidget);
      expect(find.text('Ref. REC-001'), findsOneWidget);
      expect(find.textContaining('Año 2026'), findsOneWidget);
      expect(find.text('RD\$170,000.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('las cuotas muestran vencimiento, monto y estado', (
      tester,
    ) async {
      useTestSize(tester, _tallPhone);
      await tester.pumpWidget(
        testApp(SearchResultDetailPage(result: _clientResult())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cuota 3'), findsOneWidget);
      expect(find.text('Cuota 4'), findsOneWidget);
      expect(find.text('Vence 15/01/2026'), findsOneWidget);
      expect(find.text('Vence 15/06/2030'), findsOneWidget);
      expect(find.text('Pagada'), findsOneWidget);
      expect(find.text('Pendiente'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no repite datos ya mostrados en el encabezado', (
      tester,
    ) async {
      useTestSize(tester, _tallPhone);
      await tester.pumpWidget(
        testApp(SearchResultDetailPage(result: _clientResult())),
      );
      await tester.pumpAndSettle();

      // El nombre y la cédula aparecen una sola vez (tarjeta de identidad).
      expect(find.text('THELEMARQUE WISMIQUE'), findsOneWidget);
      expect(find.text('Cliente · 001-0000000-1'), findsOneWidget);
      expect(find.text('Cédula'), findsNothing);
      // El monto pendiente vive solo en el chip del encabezado.
      expect(find.textContaining('Pendiente RD\$125,000.00'), findsOneWidget);
      expect(find.text('Monto pendiente'), findsNothing);
      expect(find.text('Saldo pendiente'), findsNothing);
      expect(find.text('RESUMEN'), findsNothing);
      // El nombre del cliente no se repite en cada cuota.
      expect(
        find.textContaining('THELEMARQUE', findRichText: false),
        findsOneWidget,
      );
    });

    testWidgets('acciones principales visibles', (tester) async {
      useTestSize(tester, _tallPhone);
      await tester.pumpWidget(testApp(_detailWithLinks(_clientResult())));
      await tester.pumpAndSettle();

      expect(find.text('Ver ventas'), findsOneWidget);
      expect(find.text('Ver cuotas'), findsOneWidget);
      expect(find.text('Ver pagos'), findsOneWidget);
      // Los accesos a cada lugar referenciado son visibles, no solo un botón.
      expect(find.text('Ver cliente'), findsOneWidget);
    });

    testWidgets('Ver cuotas navega inmediatamente con el saleId', (
      tester,
    ) async {
      useTestSize(tester, _tallPhone);
      final opened = <int?>[];

      await tester.pumpWidget(
        _detailHarness(result: _clientResult(), onOpenInstallments: opened.add),
      );

      await tester.tap(find.text('abrir detalle'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ver cuotas'));
      await tester.pumpAndSettle();

      expect(opened, [10]);
      expect(find.text('abrir detalle'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Ver pagos navega inmediatamente con el saleId', (
      tester,
    ) async {
      useTestSize(tester, _tallPhone);
      final opened = <int?>[];

      await tester.pumpWidget(
        _detailHarness(result: _clientResult(), onOpenPayments: opened.add),
      );

      await tester.tap(find.text('abrir detalle'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ver pagos'));
      await tester.pumpAndSettle();

      expect(opened, [10]);
      expect(tester.takeException(), isNull);
    });
  });

  group('Buscador mobile - responsive sin desbordes', () {
    for (final width in _widths) {
      testWidgets('lista de resultados a ${width.toInt()} px', (tester) async {
        useTestSize(tester, _tall(width));
        final controller = TextEditingController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(testApp(_view(controller: controller)));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });

      testWidgets('detalle a ${width.toInt()} px', (tester) async {
        useTestSize(tester, _tall(width));
        await tester.pumpWidget(
          testApp(SearchResultDetailPage(result: _longPlanResult())),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Buscador - escritorio sin regresion', () {
    testWidgets('a 1024 px no usa navegacion compacta', (tester) async {
      useTestSize(tester, const Size(1024, 768));
      late bool compact;

      await tester.pumpWidget(
        testApp(
          Builder(
            builder: (context) {
              compact = AppBreakpoints.usesCompactNavigation(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(compact, isFalse);
    });

    testWidgets('la pagina mantiene el layout de escritorio', (tester) async {
      useTestSize(tester, const Size(1280, 900));

      await tester.pumpWidget(testApp(const GlobalSearchPage()));
      await tester.pumpAndSettle();

      expect(find.byType(GlobalSearchMobileView), findsNothing);
      expect(find.text('Búsqueda Global'), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
