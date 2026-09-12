import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/resilience/app_paths.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'default test paths stay under system temp, never real AppData root',
    () async {
      final tempRoot = path.normalize(Directory.systemTemp.path);
      final appPaths = AppPaths();
      final supportDirectory = path.normalize(appPaths.supportDirectory);
      final databasePath = path.normalize(
        await AppDatabase.instance.databasePath,
      );

      expect(path.isWithin(tempRoot, supportDirectory), isTrue);
      expect(path.isWithin(tempRoot, databasePath), isTrue);
      expect(supportDirectory, isNot(contains(r'\SistemaSolares\data')));
      expect(databasePath, isNot(contains(r'\SistemaSolares\data\database')));
    },
  );
}
