import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_solares/app/app.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/resilience/global_error_controller.dart';
import 'package:sistema_solares/core/resilience/incident_logger.dart';

Future<void> _settleApp(WidgetTester tester) async {
  for (var index = 0; index < 20; index++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('muestra el shell principal y navega por modulos base', (
    WidgetTester tester,
  ) async {
    await AppDatabase.instance.initialize();
    final errorController = GlobalErrorController(
      incidentLogger: IncidentLogger(),
    );
    await tester.pumpWidget(SistemaSolaresApp(errorController: errorController));
    await _settleApp(tester);

    expect(find.text('Sistema de\nSolares'), findsOneWidget);
    expect(find.text('Clientes'), findsOneWidget);
    expect(find.text('Solares'), findsOneWidget);
    expect(find.text('Panel principal'), findsOneWidget);

    await tester.tap(find.text('Clientes').first);
    await _settleApp(tester);
    expect(find.text('Nuevo cliente'), findsOneWidget);

    await tester.tap(find.text('Solares').first);
    await _settleApp(tester);
    expect(find.text('Nuevo solar'), findsOneWidget);

    await tester.tap(find.text('Ventas').first);
    await _settleApp(tester);
    expect(find.text('Nueva venta'), findsOneWidget);

    await tester.tap(find.text('Pagos').first);
    await _settleApp(tester);
    expect(
      find.text('No hay ventas activas con saldo pendiente para recibir pagos.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Busqueda').first);
    await _settleApp(tester);
    expect(find.text('Busqueda global'), findsOneWidget);

    await tester.tap(find.text('Configuracion').first);
    await _settleApp(tester);
    expect(find.text('Guardar cambios'), findsOneWidget);
  });
}
