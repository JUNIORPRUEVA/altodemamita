import 'dart:io';

import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/features/auth/data/auth_service.dart';

Future<void> main(List<String> args) async {
  final identifier = _readArg(args, '--identifier');
  final password = _readArg(args, '--password');
  final shouldTryLogin = identifier != null && password != null;

  final appDatabase = AppDatabase.instance;
  final authService = AuthService(appDatabase: appDatabase);

  stdout.writeln('[LocalAuthDebug] starting');
  await authService.debugDumpLocalUsersSafe(context: 'tool');

  if (shouldTryLogin) {
    stdout.writeln(
      '[LocalAuthDebug] login_probe identifier=${identifier!.trim()}',
    );
    try {
      final result = await authService.signInHybrid(
        email: identifier,
        password: password!,
      );
      stdout.writeln(
        '[LocalAuthDebug] login_probe_success mode=${result.mode.name} email=${result.user.email}',
      );
    } on AuthException catch (error) {
      stdout.writeln('[LocalAuthDebug] login_probe_failed message=${error.message}');
    } catch (error) {
      stdout.writeln('[LocalAuthDebug] login_probe_error error=$error');
    }
  } else {
    stdout.writeln(
      '[LocalAuthDebug] login_probe_skipped pass --identifier and --password to test login',
    );
  }

  await appDatabase.close();
  stdout.writeln('[LocalAuthDebug] done');
}

String? _readArg(List<String> args, String key) {
  for (var i = 0; i < args.length; i++) {
    if (args[i] == key && i + 1 < args.length) {
      return args[i + 1];
    }
  }
  return null;
}
