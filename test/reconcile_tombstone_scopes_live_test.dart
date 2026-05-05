import 'package:flutter_test/flutter_test.dart';

import '../tool/reconcile_tombstone_scopes.dart' as runner;

const bool _tombstoneLiveEnabled = bool.fromEnvironment(
  'TOMBSTONE_LIVE',
  defaultValue: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'reconcile tombstone scopes against real backend and local db',
    () async {
      await runner.main();
    },
    skip: !_tombstoneLiveEnabled,
  );
}