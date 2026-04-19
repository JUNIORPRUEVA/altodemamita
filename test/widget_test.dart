import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:sistema_solares/app/navigation/app_shell.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/resilience/global_error_controller.dart';
import 'package:sistema_solares/core/resilience/incident_logger.dart';
import 'package:sistema_solares/core/system/system_config_service.dart';
import 'package:sistema_solares/features/auth/domain/permission_model.dart';
import 'package:sistema_solares/features/auth/domain/user_model.dart';
import 'package:sistema_solares/features/auth/presentation/auth_provider.dart';

Future<void> _settleApp(WidgetTester tester) async {
  for (var index = 0; index < 20; index++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _TestAuthProvider extends AuthProvider {
  _TestAuthProvider()
    : _currentUser = UserModel(
        id: 1,
        nombre: 'Administrador',
        email: 'admin@local.test',
        passwordHash: '',
        passwordResetRequired: false,
        role: UserRole.admin,
        permissions: const <PermissionModel>[],
        activo: true,
        fechaCreacion: DateTime(2026, 1, 1),
        fechaActualizacion: DateTime(2026, 1, 1),
      );

  final UserModel _currentUser;

  @override
  bool get isInitializing => false;

  @override
  bool get isAuthenticated => true;

  @override
  UserModel? get currentUser => _currentUser;

  @override
  bool canReadModule(String module) => true;

  @override
  bool canAccess(String module, PermissionAction action) => true;

  @override
  Future<void> refreshCurrentUser() async {}

  @override
  Future<void> signOut() async {}
}

void main() {
  testWidgets('muestra el shell principal y navega por modulos base', (
    WidgetTester tester,
  ) async {
    await AppDatabase.instance.initialize();
    final errorController = GlobalErrorController(
      incidentLogger: IncidentLogger(),
    );
    final authProvider = _TestAuthProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<SystemConfigService>.value(
            value: SystemConfigService.instance,
          ),
        ],
        child: MaterialApp(
          navigatorKey: errorController.navigatorKey,
          home: const AppShell(),
        ),
      ),
    );
    await _settleApp(tester);

    expect(find.text('Sistema Solares'), findsAtLeastNWidgets(1));
    expect(find.text('Clientes'), findsOneWidget);
    expect(find.text('Solares'), findsOneWidget);
    expect(find.text('Panel Principal'), findsOneWidget);

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

    await tester.tap(find.text('Buscador').first);
    await _settleApp(tester);
    expect(find.text('Búsqueda global'), findsOneWidget);

    await tester.tap(find.text('Configuración').first);
    await _settleApp(tester);
    expect(find.text('Guardar cambios'), findsOneWidget);
  });
}
