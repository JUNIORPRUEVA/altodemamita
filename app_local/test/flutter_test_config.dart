import 'dart:async';
import 'dart:io';

import 'package:sistema_solares/core/resilience/app_paths.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final supportDirectory = await Directory.systemTemp.createTemp(
    'sistema_solares_test_support_',
  );
  AppPaths.debugOverrideDefaultSupportDirectory(supportDirectory.path);

  await testMain();
}
