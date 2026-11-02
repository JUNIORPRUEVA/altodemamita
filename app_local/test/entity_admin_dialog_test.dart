import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/shared/widgets/entity_admin_dialog.dart';

/// FASE 04 — el diálogo administrativo refleja la autorización del backend y
/// exige motivo antes de confirmar.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required EntityAdminPreview preview,
    required Future<Map<String, dynamic>> Function(String, Map<String, String>)
    apply,
    List<EntityAdminField> fields = const [],
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDialog<bool>(
                  context: context,
                  builder: (_) => EntityAdminDialog(
                    title: 'Editar cliente',
                    fields: fields,
                    summaryLines: const ['Cliente Demo', '001-0000001-1'],
                    loadPreview: (values) async => preview,
                    apply: apply,
                  ),
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('muestra datos actuales y exige motivo', (tester) async {
    await pump(
      tester,
      preview: const EntityAdminPreview(
        allowed: true,
        code: 'OK',
        message: 'Cambio permitido.',
        version: 3,
      ),
      fields: const [
        EntityAdminField(key: 'name', label: 'Nombre', initial: 'Cliente Demo'),
      ],
      apply: (reason, values) async => <String, dynamic>{},
    );

    expect(find.textContaining('Cliente Demo'), findsWidgets);
    final confirm = find.widgetWithText(FilledButton, 'Editar cliente');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await tester.enterText(
      find.byType(TextField).last,
      'Datos corregidos por el propietario',
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
  });

  testWidgets('bloquea cuando el backend rechaza el cambio', (tester) async {
    await pump(
      tester,
      preview: const EntityAdminPreview(
        allowed: false,
        code: 'CLIENT_HAS_ACTIVE_SALES',
        message: 'El cliente tiene ventas activas.',
        version: 0,
      ),
      apply: (reason, values) async => <String, dynamic>{},
    );

    expect(find.textContaining('tiene ventas activas'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Intento de desactivar');
    await tester.pump();
    final confirm = find.widgetWithText(FilledButton, 'Editar cliente');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
  });

  testWidgets('la fusion muestra ventas y pagos afectados', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDialog<bool>(
                  context: context,
                  builder: (_) => EntityAdminDialog(
                    title: 'Fusionar duplicados',
                    mergeSourceId: 'src-1',
                    summaryLines: const ['Se conserva: Cliente A'],
                    loadPreview: (values) async => const EntityAdminPreview(
                      allowed: true,
                      code: 'OK',
                      message: 'Fusion permitida.',
                      version: 5,
                      detail: {'movedSales': 3, 'movedPayments': 7},
                    ),
                    apply: (reason, values) async => <String, dynamic>{},
                  ),
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.textContaining('3 venta(s)'), findsOneWidget);
    expect(find.textContaining('7 pago(s)'), findsOneWidget);
    expect(find.textContaining('queda como historico'), findsOneWidget);
  });

  testWidgets('el visor de auditoria lista los cambios', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EntityAdminAuditDialog(
            title: 'Auditoria',
            data: {
              'history': [
                {'action': 'deactivate', 'reason': 'Retiro', 'performedAt': '2026-11-02T10:00:00.000Z'},
                {'action': 'update_details', 'reason': 'Area corregida', 'performedAt': '2026-11-02T11:00:00.000Z'},
              ],
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('deactivate'), findsOneWidget);
    expect(find.textContaining('Area corregida'), findsOneWidget);
  });
}
