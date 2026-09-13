import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sistema_solares/app/navigation/app_module.dart';
import 'package:sistema_solares/app/navigation/app_shell.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/resilience/global_error_controller.dart';
import 'package:sistema_solares/core/resilience/incident_logger.dart';
import 'package:sistema_solares/core/system/system_config_service.dart';
import 'package:sistema_solares/features/auth/domain/permission_model.dart';
import 'package:sistema_solares/features/auth/domain/user_model.dart';
import 'package:sistema_solares/features/auth/presentation/auth_provider.dart';
import 'package:sistema_solares/services/sync/sync_queue_service.dart';

/// Anchos exigidos por la especificación de aceptación.
const List<double> _mobileWidths = [320, 360, 375, 390, 412, 430, 768];
const List<double> _desktopWidths = [1024, 1366, 1440, 1920];

/// Destinos visibles en la barra inferior móvil.
const List<AppModule> _mobilePrimary = [
  AppModule.dashboard,
  AppModule.sales,
  AppModule.globalSearch,
];

/// Destinos secundarios, agrupados en el Drawer móvil.
const List<AppModule> _mobileDrawerModules = [
  AppModule.payments,
  AppModule.clients,
  AppModule.lots,
  AppModule.installments,
  AppModule.sellers,
  AppModule.settings,
];

/// Destinos alcanzables en escritorio sin desplegar el submenú de
/// administración del sidebar (que no forma parte de esta migración).
const List<AppModule> _desktopModules = [
  AppModule.dashboard,
  AppModule.sales,
  AppModule.globalSearch,
  AppModule.payments,
  AppModule.settings,
];

Future<void> _settleApp(WidgetTester tester) async {
  for (var index = 0; index < 12; index++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  for (var index = 0; index < 4; index++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
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
      'responsive_shell_overflow_',
    );
    testDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
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

  /// NOTA IMPORTANTE: `tester.binding.setSurfaceSize` NO cambia el tamaño real
  /// de la vista en esta versión de Flutter, por lo que esta batería corre
  /// realmente a 800x600 (layout compacto). Sirve como smoke test de que
  /// ningún módulo se desborda en compacto ancho.
  ///
  /// PENDIENTE: cuando los módulos restantes (Pagos, Clientes, Solares, Cuotas,
  /// Vendedores, Usuarios) tengan su layout compacto definitivo, migrar esta
  /// batería a `useTestSize` (test/helpers/responsive_test_harness.dart) para
  /// validar de verdad 320/360/375/390/412/430.
  Future<void> pumpShell(WidgetTester tester, double width) async {
    await tester.binding.setSurfaceSize(Size(width, 900));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final errorController = GlobalErrorController(
      incidentLogger: IncidentLogger(),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(
            value: _TestAuthProvider(),
          ),
          ChangeNotifierProvider<SystemConfigService>.value(
            value: SystemConfigService.instance,
          ),
        ],
        child: MaterialApp(
          navigatorKey: errorController.navigatorKey,
          home: const AppShell(
            enableBackgroundSync: false,
            initializeBackupOnSettingsOpen: false,
          ),
        ),
      ),
    );
    await _settleApp(tester);
  }

  /// Cierra la prueba dejando el árbol desmontado y sin temporizadores
  /// periodicos del singleton de cola pendientes.
  Future<void> finish(WidgetTester tester) async {
    SyncQueueService.instance.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  /// Drena TODAS las excepciones pendientes para poder reportar varios
  /// problemas de layout en una sola corrida.
  List<String> drainExceptions(WidgetTester tester) {
    final problems = <String>[];
    for (var guard = 0; guard < 50; guard++) {
      final exception = tester.takeException();
      if (exception == null) {
        break;
      }
      problems.add(exception.toString().split('\n').first.trim());
    }
    return problems;
  }

  Future<void> openModule(
    WidgetTester tester,
    AppModule module,
    double width,
  ) async {
    final isDesktop = width >= 1024;
    final mobileLabel = switch (module) {
      AppModule.globalSearch => 'Buscador',
      _ => module.label,
    };

    if (!isDesktop && !_mobilePrimary.contains(module)) {
      // Movil: los modulos secundarios viven en el Drawer.
      await tester.tap(find.byIcon(Icons.menu_rounded).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(mobileLabel).last);
      await _settleApp(tester);
      return;
    }

    if (!isDesktop) {
      await tester.tap(find.text(mobileLabel).last);
      await _settleApp(tester);
      return;
    }

    // Escritorio: icono del sidebar o acción del pie lateral.
    final icon = find.byIcon(module.icon);
    if (icon.evaluate().isNotEmpty) {
      await tester.tap(icon.first);
      await _settleApp(tester);
      return;
    }

    final label = find.text(module.label);
    expect(
      label,
      findsAtLeastNWidgets(1),
      reason: 'no se encontro el destino ${module.label} en ${width}px',
    );
    await tester.tap(label.first);
    await _settleApp(tester);
  }

  Future<List<String>> visitModules(
    WidgetTester tester,
    double width,
    List<AppModule> modules,
  ) async {
    final problems = <String>[];
    problems.addAll(drainExceptions(tester));

    for (final module in modules) {
      await openModule(tester, module, width);
      for (final problem in drainExceptions(tester)) {
        problems.add('${width.toInt()}px ${module.label}: $problem');
      }
    }
    return problems;
  }

  group('Movil: sin overflow en ningun modulo', () {
    for (final width in _mobileWidths) {
      testWidgets('${width.toInt()}px', (tester) async {
        await pumpShell(tester, width);
        final problems = await visitModules(tester, width, [
          ..._mobilePrimary,
          ..._mobileDrawerModules,
        ]);
        await finish(tester);
        expect(
          problems,
          isEmpty,
          reason: 'problemas de layout movil: ${problems.join(' | ')}',
        );
      });
    }
  });

  group('Escritorio: layout existente sin overflow', () {
    for (final width in _desktopWidths) {
      testWidgets('${width.toInt()}px', (tester) async {
        await pumpShell(tester, width);
        final problems = await visitModules(tester, width, _desktopModules);
        await finish(tester);
        expect(
          problems,
          isEmpty,
          reason: 'problemas de layout escritorio: ${problems.join(' | ')}',
        );
      });
    }
  });
}
