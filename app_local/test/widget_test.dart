import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  // El backend local usa sqflite FFI sobre un isolate real: sus transacciones
  // no progresan con el reloj falso del test. Drenamos tiempo real en varios
  // ciclos para que ninguna transaccion quede pendiente al desmontar el arbol.
  for (var index = 0; index < 6; index++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pump();
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
  late Directory tempDirectory;
  late AppDatabase testDatabase;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
          (_) async => null,
        );
    SharedPreferences.setMockInitialValues({
      'shell.sidebar.expanded': true,
      'shell.sidebar.administration.expanded': true,
    });
    tempDirectory = await Directory.systemTemp.createTemp(
      'sistema_solares_widget_shell_',
    );
    testDatabase = AppDatabase.test(
      path.join(tempDirectory.path, 'test.db'),
    );
    AppDatabase.debugOverrideInstance(testDatabase);
    await AppDatabase.instance.initialize();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
          null,
        );
    await testDatabase.close();
    AppDatabase.debugOverrideInstance(null);
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  testWidgets('muestra el shell principal y navega por modulos base', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

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
          home: const AppShell(enableBackgroundSync: false),
        ),
      ),
    );
    await _settleApp(tester);

    expect(find.text('Sistema Solares'), findsAtLeastNWidgets(1));
    expect(find.text('Resumen'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.point_of_sale_outlined).first);
    await _settleApp(tester);
    expect(find.text('Nueva venta'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.search_outlined).first);
    await _settleApp(tester);
    expect(find.text('Buscador'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.payments_outlined).first);
    await _settleApp(tester);
    expect(find.text('Pagos'), findsOneWidget);
  });
}
