import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/app/navigation/mobile_navigation_shell.dart';

import 'helpers/responsive_test_harness.dart';

const _primary = [
  MobileNavigationItem(id: 'dashboard', label: 'Resumen', icon: Icons.home),
  MobileNavigationItem(
    id: 'sales',
    label: 'Ventas',
    icon: Icons.receipt_long,
    prominent: true,
  ),
  MobileNavigationItem(
    id: 'globalSearch',
    label: 'Buscador',
    icon: Icons.manage_search,
  ),
];

const _drawerSections = [
  MobileDrawerSection(
    title: 'Operación',
    items: [
      MobileNavigationItem(
        id: 'payments',
        label: 'Pagos',
        icon: Icons.account_balance_wallet,
      ),
      MobileNavigationItem(
        id: 'clients',
        label: 'Clientes',
        icon: Icons.people,
      ),
      MobileNavigationItem(id: 'lots', label: 'Solares', icon: Icons.map),
      MobileNavigationItem(
        id: 'installments',
        label: 'Cuotas',
        icon: Icons.event_note,
      ),
    ],
  ),
  MobileDrawerSection(
    title: 'Administración',
    items: [
      MobileNavigationItem(
        id: 'settings',
        label: 'Configuracion',
        icon: Icons.settings,
      ),
    ],
  ),
];

Widget _shell({
  required String selectedId,
  ValueChanged<String>? onSelected,
  bool withDrawer = true,
  List<Widget> actions = const [],
  bool showBackButton = false,
  VoidCallback? onBack,
  String title = 'Sistema de Solares',
  bool showHomeHeader = false,
  bool hideAppBar = false,
}) {
  return MobileNavigationShell(
    title: title,
    companyName: 'EL ALTO DE DOÑA MAMITA',
    userName: 'Administrador',
    userRole: 'Administrador',
    selectedId: selectedId,
    onSelected: onSelected ?? (_) {},
    primaryItems: _primary,
    drawerSections: withDrawer ? _drawerSections : const [],
    actions: actions,
    showBackButton: showBackButton,
    onBack: onBack,
    showHomeHeader: showHomeHeader,
    hideAppBar: hideAppBar,
    child: const Center(child: Text('CONTENIDO')),
  );
}

void main() {
  group('MobileNavigationShell', () {
    testWidgets('en movil muestra la barra inferior con 3 destinos exactos', (
      tester,
    ) async {
      useTestSize(tester, TestViewSizes.androidCompact);
      await tester.pumpWidget(testApp(_shell(selectedId: 'dashboard')));

      expect(find.byType(BottomNavigationBar), findsNothing);

      final items = tester
          .widgetList<MobileBottomNavigationItem>(
            find.byType(MobileBottomNavigationItem),
          )
          .toList();
      expect(items.length, 3);
      expect(items.map((entry) => entry.item.label), [
        'Resumen',
        'Ventas',
        'Buscador',
      ]);
      // Ventas es el destino destacado (icono central más grande).
      final prominent = items.where((entry) => entry.item.prominent).toList();
      expect(prominent.length, 1);
      expect(prominent.single.item.id, 'sales');
    });

    testWidgets('en tableta tambien usa navegacion compacta', (tester) async {
      useTestSize(tester, TestViewSizes.tabletPortrait);
      await tester.pumpWidget(testApp(_shell(selectedId: 'dashboard')));

      expect(find.byType(MobileBottomNavigationItem), findsNWidgets(3));
    });

    testWidgets('en Windows (1366) NO muestra barra inferior', (tester) async {
      useTestSize(tester, TestViewSizes.desktop);
      await tester.pumpWidget(testApp(_shell(selectedId: 'dashboard')));

      expect(find.byType(MobileBottomNavigationItem), findsNothing);
      expect(find.text('CONTENIDO'), findsOneWidget);
    });

    testWidgets('marca el modulo activo', (tester) async {
      useTestSize(tester, TestViewSizes.iphone12);
      await tester.pumpWidget(testApp(_shell(selectedId: 'sales')));

      final items = tester
          .widgetList<MobileBottomNavigationItem>(
            find.byType(MobileBottomNavigationItem),
          )
          .toList();
      final selected = items.where((entry) => entry.selected).toList();
      expect(selected.length, 1);
      expect(selected.single.item.id, 'sales');
    });

    testWidgets('al tocar un destino notifica el id', (tester) async {
      final selections = <String>[];

      useTestSize(tester, TestViewSizes.iphone12);
      await tester.pumpWidget(
        testApp(_shell(selectedId: 'dashboard', onSelected: selections.add)),
      );

      await tester.tap(find.text('Buscador'));
      await tester.pumpAndSettle();

      expect(selections, ['globalSearch']);
    });

    testWidgets('el menu abre un drawer con los modulos secundarios', (
      tester,
    ) async {
      final selections = <String>[];

      useTestSize(tester, TestViewSizes.androidCompact);
      await tester.pumpWidget(
        testApp(
          _shell(
            selectedId: 'dashboard',
            onSelected: selections.add,
            showHomeHeader: true,
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Pagos'), findsOneWidget);
      expect(find.text('Clientes'), findsOneWidget);
      expect(find.text('Solares'), findsOneWidget);
      expect(find.text('Cuotas'), findsOneWidget);
      expect(find.text('Configuracion'), findsOneWidget);

      await tester.tap(find.text('Cuotas'));
      await tester.pumpAndSettle();

      expect(selections, ['installments']);
    });

    testWidgets('sin drawer mantiene solo la barra inferior', (tester) async {
      useTestSize(tester, TestViewSizes.iphone12);
      await tester.pumpWidget(
        testApp(_shell(selectedId: 'dashboard', withDrawer: false)),
      );

      expect(find.byType(MobileBottomNavigationItem), findsNWidgets(3));
      expect(find.byIcon(Icons.menu_rounded), findsNothing);
    });

    testWidgets('puede ocultar la AppBar para pantallas con AppBar propia', (
      tester,
    ) async {
      useTestSize(tester, TestViewSizes.iphone12);
      await tester.pumpWidget(
        testApp(_shell(selectedId: 'sales', hideAppBar: true)),
      );

      expect(find.byType(AppBar), findsNothing);
      expect(find.text('CONTENIDO'), findsOneWidget);
      expect(find.byType(MobileBottomNavigationItem), findsNWidgets(3));
    });

    testWidgets('la AppBar soporta volver y una accion principal', (
      tester,
    ) async {
      var backPressed = 0;

      useTestSize(tester, TestViewSizes.iphone12);
      await tester.pumpWidget(
        testApp(
          _shell(
            selectedId: 'sales',
            showBackButton: true,
            onBack: () => backPressed += 1,
            actions: [
              IconButton(
                icon: const Icon(Icons.print),
                tooltip: 'Imprimir',
                onPressed: () {},
              ),
            ],
          ),
        ),
      );

      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(find.byIcon(Icons.print), findsOneWidget);
      expect(find.byIcon(Icons.menu_rounded), findsNothing);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pump();

      expect(backPressed, 1);
    });

    testWidgets('el titulo largo no desborda la AppBar en 320', (tester) async {
      useTestSize(tester, TestViewSizes.iphoneSe);
      await tester.pumpWidget(
        testApp(
          _shell(
            selectedId: 'reports',
            title: 'Reporte de amortizacion de venta financiada',
            showBackButton: true,
            actions: [
              IconButton(icon: const Icon(Icons.share), onPressed: () {}),
            ],
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('no se desborda en ningun tamano requerido', (tester) async {
      useTestSize(tester, const Size(320, 800));
      await tester.pumpWidget(testApp(_shell(selectedId: 'dashboard')));

      for (final width in TestViewSizes.requiredWidths) {
        tester.view.physicalSize = Size(width, 800);
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'ancho $width no debe desbordarse',
        );
      }
    });
  });
}
