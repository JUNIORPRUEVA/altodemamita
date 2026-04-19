import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/core/utils/sync_id_generator.dart';

void main() {
  test('genera ids unicos aunque comparta el mismo microsegundo', () {
    const fixedTick = 1776632317550928;
    final ids = <String>{
      for (var index = 0; index < 50; index += 1)
        SyncIdGenerator.next(
          'installment',
          microsecondsSinceEpoch: fixedTick,
        ),
    };

    expect(ids, hasLength(50));
    expect(
      ids.every((value) => value.startsWith('installment-$fixedTick-')),
      isTrue,
    );
  });
}