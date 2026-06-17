import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/app_shell.dart';
import 'app/app_theme.dart';
import 'widgets/error_view.dart';

void main() {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();

      FlutterError.onError = (details) {
        if (kDebugMode) {
          FlutterError.presentError(details);
        }
        Zone.current.handleUncaughtError(
          details.exception,
          details.stack ?? StackTrace.current,
        );
      };

      PlatformDispatcher.instance.onError = (error, stack) {
        Zone.current.handleUncaughtError(error, stack);
        return true;
      };

      ErrorWidget.builder = (_) => const AppErrorFallback();

      runApp(const OwnerApp());
    },
    (error, stack) {
      if (kDebugMode) {
        debugPrint('Unhandled app error: $error');
        debugPrintStack(stackTrace: stack);
      }
    },
  );
}

class OwnerApp extends StatelessWidget {
  const OwnerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Sistema Solares Owner',
      theme: appTheme,
      home: const AppShell(),
    );
  }
}
