import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/core/responsive/responsive_table.dart';

import 'helpers/responsive_test_harness.dart';

void main() {
  group('ResponsiveTableSwitch', () {
    testWidgets('en Windows (1366) conserva la tabla existente', (tester) async {
      useTestSize(tester, TestViewSizes.desktop);
      await tester.pumpWidget(
        testApp(
          const ResponsiveTableSwitch(
            table: Text('TABLA-DESKTOP'),
            cards: Text('TARJETAS-MOBILE'),
          ),
        ),
      );

      expect(find.text('TABLA-DESKTOP'), findsOneWidget);
      expect(find.text('TARJETAS-MOBILE'), findsNothing);
    });

    testWidgets('en movil usa tarjetas', (tester) async {
      useTestSize(tester, TestViewSizes.iphoneSe);
      await tester.pumpWidget(
        testApp(
          const ResponsiveTableSwitch(
            table: Text('TABLA-DESKTOP'),
            cards: Text('TARJETAS-MOBILE'),
          ),
        ),
      );

      for (final size in [
        TestViewSizes.iphoneSe,
        TestViewSizes.androidCompact,
        TestViewSizes.iphone12,
        TestViewSizes.androidLarge,
        TestViewSizes.iphoneProMax,
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();

        expect(
          find.text('TARJETAS-MOBILE'),
          findsOneWidget,
          reason: 'tamano ${size.width}x${size.height}',
        );
      }
    });

    testWidgets('en tableta usa tarjetas con el umbral por defecto',
        (tester) async {
      useTestSize(tester, TestViewSizes.tabletPortrait);
      await tester.pumpWidget(
        testApp(
          const ResponsiveTableSwitch(
            table: Text('TABLA-DESKTOP'),
            cards: Text('TARJETAS-MOBILE'),
          ),
        ),
      );

      expect(find.text('TARJETAS-MOBILE'), findsOneWidget);
    });

    testWidgets('fuerza la estrategia cuando se solicita', (tester) async {
      useTestSize(tester, TestViewSizes.desktop);
      await tester.pumpWidget(
        testApp(
          const ResponsiveTableSwitch(
            forceStrategy: ResponsiveTableStrategy.cards,
            table: Text('TABLA-DESKTOP'),
            cards: Text('TARJETAS-MOBILE'),
          ),
        ),
      );

      expect(find.text('TARJETAS-MOBILE'), findsOneWidget);
    });

    testWidgets('un ancho minimo mayor al de la ventana degrada a tarjetas',
        (tester) async {
      useTestSize(tester, TestViewSizes.desktopSmall);
      await tester.pumpWidget(
        testApp(
          const ResponsiveTableSwitch(
            forceStrategy: ResponsiveTableStrategy.table,
            minTableWidth: 1280,
            table: Text('TABLA-DESKTOP'),
            cards: Text('TARJETAS-MOBILE'),
          ),
        ),
      );

      expect(find.text('TARJETAS-MOBILE'), findsOneWidget);
    });
  });

  group('ResponsiveRecordCard', () {
    testWidgets('muestra titulo, subtitulo y campos sin desbordarse en 320',
        (tester) async {
      useTestSize(tester, TestViewSizes.iphoneSe);
      await tester.pumpWidget(
        testApp(
          Scaffold(
            body: ResponsiveRecordCard(
              title: 'Juan Perez',
              subtitle: '001-1234567-8',
              fields: const [
                ResponsiveRecordField(label: 'Solar', value: 'A-12'),
                ResponsiveRecordField(
                  label: 'Total',
                  value: 'RD\$ 600,000.00',
                ),
                ResponsiveRecordField(
                  label: 'Saldo',
                  value: 'RD\$ 230,000.00',
                  emphasis: true,
                ),
              ],
              trailing: const Chip(label: Text('Pendiente')),
              actions: [
                TextButton(onPressed: () {}, child: const Text('Ver')),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Juan Perez'), findsOneWidget);
      expect(find.text('A-12'), findsOneWidget);
      expect(find.text('RD\$ 230,000.00'), findsOneWidget);
      expect(find.text('Ver'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('el valor largo se ajusta en varias lineas', (tester) async {
      useTestSize(tester, TestViewSizes.androidCompact);
      await tester.pumpWidget(
        testApp(
          const Scaffold(
            body: ResponsiveRecordCard(
              title: 'Cliente con nombre extremadamente largo para movil',
              fields: [
                ResponsiveRecordField(
                  label: 'Direccion',
                  value: 'Calle Duarte numero 123, sector Los Minas, '
                      'municipio Santo Domingo Este, provincia Santo Domingo',
                ),
              ],
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('responde al toque', (tester) async {
      var taps = 0;

      useTestSize(tester, TestViewSizes.iphone12);
      await tester.pumpWidget(
        testApp(
          Scaffold(
            body: ResponsiveRecordCard(
              title: 'Juan Perez',
              onTap: () => taps += 1,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Juan Perez'));
      await tester.pumpAndSettle();

      expect(taps, 1);
    });

    testWidgets('no se desborda en ningun tamano requerido', (tester) async {
      useTestSize(tester, const Size(320, 800));
      await tester.pumpWidget(
        testApp(
          const Scaffold(
            body: ResponsiveRecordCard(
              title: 'Juan Perez',
              subtitle: '001-1234567-8',
              fields: [
                ResponsiveRecordField(label: 'Solar', value: 'A-12'),
                ResponsiveRecordField(
                  label: 'Total',
                  value: 'RD\$ 600,000.00',
                  emphasis: true,
                ),
              ],
              actions: [Text('Ver')],
            ),
          ),
        ),
      );

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
