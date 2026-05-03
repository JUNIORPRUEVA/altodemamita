import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/core/resilience/friendly_error_messages.dart';
import 'package:sistema_solares/shared/widgets/recovery_experience.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildDialogHost({
    required double width,
    Future<void> Function()? onRetry,
    String userMessage = 'La app sigue funcionando. Puedes intentarlo otra vez.',
    String? technicalDetails,
    String? technicalStackTrace,
  }) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 800)),
        child: Scaffold(
          body: Center(
            child: CompactGlobalErrorDialog(
              userMessage: userMessage,
              technicalDetails: technicalDetails,
              technicalStackTrace: technicalStackTrace,
              onRetry: onRetry,
              onClose: () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('global_error_dialog_is_compact_test', (tester) async {
    await tester.pumpWidget(buildDialogHost(width: 1280));
    final size = tester.getSize(find.byKey(const Key('compact_error_card')));

    expect(size.width, lessThanOrEqualTo(420));
  });

  testWidgets('global_error_dialog_always_has_close_button_test', (
    tester,
  ) async {
    await tester.pumpWidget(buildDialogHost(width: 1024));

    expect(find.byKey(const Key('compact_error_close_button')), findsOneWidget);
  });

  testWidgets('global_error_dialog_always_has_copy_button_test', (
    tester,
  ) async {
    await tester.pumpWidget(buildDialogHost(width: 1024));

    expect(find.byKey(const Key('compact_error_copy_button')), findsOneWidget);
  });

  testWidgets('global_error_dialog_hides_retry_when_no_retry_callback_test', (
    tester,
  ) async {
    await tester.pumpWidget(buildDialogHost(width: 1024, onRetry: null));

    expect(find.byKey(const Key('compact_error_retry_button')), findsNothing);
  });

  testWidgets('global_error_dialog_shows_retry_only_when_callback_exists_test', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildDialogHost(width: 1024, onRetry: () async {}),
    );

    expect(find.byKey(const Key('compact_error_retry_button')), findsOneWidget);
  });

  testWidgets('global_error_dialog_does_not_show_stacktrace_to_user_test', (
    tester,
  ) async {
    const rawStack = 'Stacktrace: Null check operator used on a null value';
    await tester.pumpWidget(
      buildDialogHost(
        width: 1024,
        technicalDetails: 'SocketException',
        technicalStackTrace: rawStack,
      ),
    );

    expect(find.textContaining('Stacktrace'), findsNothing);
    expect(find.textContaining('Null check operator'), findsNothing);
    expect(find.textContaining('SocketException'), findsNothing);
  });

  testWidgets('global_error_dialog_copies_technical_report_test', (
    tester,
  ) async {
    String clipboardText = '';
    final messenger = TestDefaultBinaryMessengerBinding.instance
        .defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        final arguments = call.arguments as Map<dynamic, dynamic>;
        clipboardText = (arguments['text'] as String? ?? '').trim();
        return null;
      }
      if (call.method == 'Clipboard.getData') {
        return <String, dynamic>{'text': clipboardText};
      }
      return null;
    });

    await tester.pumpWidget(
      buildDialogHost(
        width: 1024,
        technicalDetails:
            'Authorization: Bearer secret-token password=abc123 backend failed',
        technicalStackTrace: 'line1\nline2',
      ),
    );

    await tester.tap(find.byKey(const Key('compact_error_copy_button')));
    await tester.pump(const Duration(milliseconds: 300));

    expect(clipboardText, contains('APP ERROR REPORT'));
    expect(clipboardText, contains('Mensaje tecnico:'));
    expect(clipboardText, contains('Stacktrace:'));
    expect(clipboardText, isNot(contains('secret-token')));
    expect(clipboardText, isNot(contains('abc123')));
    expect(find.text('Detalle copiado.'), findsOneWidget);

    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('internet_error_uses_human_offline_message_test', () {
    final friendly = FriendlyErrorMessages.unexpected(
      const SocketException('Failed host lookup'),
    );

    expect(
      friendly.message,
      'No hay conexion en este momento. Puedes seguir trabajando y la app sincronizara luego.',
    );
  });

  test('server_error_uses_local_mode_message_test', () {
    final friendly = FriendlyErrorMessages.unexpected(
      StateError('backend server unavailable status code 503'),
    );

    expect(
      friendly.message,
      'No pudimos conectar con el servidor. La app seguira usando los datos locales.',
    );
  });
}
