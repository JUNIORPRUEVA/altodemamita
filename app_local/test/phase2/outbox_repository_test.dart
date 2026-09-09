import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/core/cloud_foundation/cloud_foundation_databases.dart';
import 'package:sistema_solares/core/cloud_foundation/outbox_repository.dart';
import 'package:sistema_solares/core/resilience/app_paths.dart';

void main() {
  test('outbox enqueue is durable and idempotent by payload hash', () async {
    final root = await Directory.systemTemp.createTemp('phase2_outbox_');
    addTearDown(() => root.delete(recursive: true));

    var databases = CloudFoundationDatabases(
      appPaths: AppPaths(supportDirectory: root.path),
    );
    await databases.initialize();
    var outbox = OutboxRepository(await databases.outbox);

    final first = await outbox.enqueue(
      operationId: 'sale.create:abc',
      operationType: 'sale.create',
      payload: {'saleId': 'sale-1', 'amount': 100},
      dependencyKey: 'lot-1',
    );
    final replay = await outbox.enqueue(
      operationId: 'sale.create:abc',
      operationType: 'sale.create',
      payload: {'amount': 100, 'saleId': 'sale-1'},
      dependencyKey: 'lot-1',
    );

    expect(replay.operationId, first.operationId);
    expect(replay.payloadHash, first.payloadHash);
    expect(
      () => outbox.enqueue(
        operationId: 'sale.create:abc',
        operationType: 'sale.create',
        payload: {'saleId': 'sale-1', 'amount': 101},
      ),
      throwsStateError,
    );

    await outbox.failRetryable(first.operationId, 'HTTP 500');
    await databases.close();

    databases = CloudFoundationDatabases(
      appPaths: AppPaths(supportDirectory: root.path),
    );
    addTearDown(databases.close);
    await databases.initialize();
    outbox = OutboxRepository(await databases.outbox);

    final stored = await outbox.find(first.operationId);
    expect(stored, isNotNull);
    expect(stored!.status, OutboxStatus.retryableFailure);
    expect(stored.attemptCount, 1);
    expect(stored.nextRetryAt, isNotNull);
  });
}
