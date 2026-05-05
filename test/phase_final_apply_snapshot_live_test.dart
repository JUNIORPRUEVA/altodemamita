import 'package:flutter_test/flutter_test.dart';

import '../tool/phase_final_apply_snapshot.dart' as runner;

const bool _phaseFinalLiveEnabled = bool.fromEnvironment(
  'PHASE_FINAL_LIVE',
  defaultValue: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'aplica snapshot backend sobre la base local real',
    () async {
      await runner.main(const []);
    },
    skip: !_phaseFinalLiveEnabled,
  );
}