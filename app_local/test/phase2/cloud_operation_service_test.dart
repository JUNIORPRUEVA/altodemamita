import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/core/cloud_foundation/cache_repository.dart';
import 'package:sistema_solares/core/cloud_foundation/cloud_foundation_databases.dart';
import 'package:sistema_solares/core/cloud_foundation/cloud_operation_service.dart';
import 'package:sistema_solares/core/cloud_foundation/outbox_repository.dart';
import 'package:sistema_solares/core/config/app_flags.dart';
import 'package:sistema_solares/core/resilience/app_paths.dart';

void main() {
  test('cloud operation service is disabled in legacy local mode', () async {
    final root = await Directory.systemTemp.createTemp('phase2_legacy_ops_');
    addTearDown(() => root.delete(recursive: true));

    final databases = CloudFoundationDatabases(
      appPaths: AppPaths(supportDirectory: root.path),
    );
    addTearDown(databases.close);
    await databases.initialize();

    final service = CloudOperationService(
      outbox: OutboxRepository(await databases.outbox),
      cache: CacheRepository(await databases.cache),
      mode: CloudCutoverMode.legacyLocal,
    );

    expect(
      () => service.createSale(
        stableBusinessKey: 'lot-1:client-1',
        payload: {'lotSyncId': 'lot-1'},
      ),
      throwsStateError,
    );
  });

  test('queues offline sale and payment in CLOUD_UAT mode', () async {
    final root = await Directory.systemTemp.createTemp('phase2_cloud_ops_');
    addTearDown(() => root.delete(recursive: true));

    final databases = CloudFoundationDatabases(
      appPaths: AppPaths(supportDirectory: root.path),
    );
    addTearDown(databases.close);
    await databases.initialize();

    final service = CloudOperationService(
      outbox: OutboxRepository(await databases.outbox),
      cache: CacheRepository(await databases.cache),
      mode: CloudCutoverMode.cloudUat,
    );

    final sale = await service.createSale(
      stableBusinessKey: 'lot-1:client-1',
      payload: {'lotSyncId': 'lot-1', 'clientSyncId': 'client-1'},
    );
    final payment = await service.registerPayment(
      stableBusinessKey: '${sale.operationId}:payment-1',
      payload: {'saleId': sale.operationId, 'amount': 500},
    );

    expect(sale.operation.operationType, 'sale.create');
    expect(payment.operation.operationType, 'payment.register');

    final cacheRows = await (await databases.cache).query('cache_records');
    final outboxRows = await (await databases.outbox).query(
      'outbox_operations',
    );
    expect(cacheRows.length, 2);
    expect(outboxRows.length, 2);
    expect(outboxRows.map((row) => row['status']).toSet(), {'PENDING'});
  });
}
