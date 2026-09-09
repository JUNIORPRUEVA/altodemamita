import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/core/cloud_foundation/cache_repository.dart';
import 'package:sistema_solares/core/cloud_foundation/cloud_api_client.dart';
import 'package:sistema_solares/core/cloud_foundation/cloud_foundation_databases.dart';
import 'package:sistema_solares/core/cloud_foundation/outbox_processor.dart';
import 'package:sistema_solares/core/cloud_foundation/outbox_repository.dart';
import 'package:sistema_solares/core/resilience/app_paths.dart';

void main() {
  test(
    'outbox processor acknowledges success and retries transient failures',
    () async {
      final root = await Directory.systemTemp.createTemp('phase2_processor_');
      addTearDown(() => root.delete(recursive: true));

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final statuses = <int>[500, 201, 409];
      server.listen((request) async {
        await utf8.decoder.bind(request).join();
        final status = statuses.removeAt(0);
        request.response.statusCode = status;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'ok': true, 'status': status}));
        await request.response.close();
      });

      final databases = CloudFoundationDatabases(
        appPaths: AppPaths(supportDirectory: root.path),
      );
      addTearDown(databases.close);
      await databases.initialize();

      final outbox = OutboxRepository(await databases.outbox);
      await outbox.enqueue(
        operationId: 'payment.register:retry',
        operationType: 'payment.register',
        payload: {'paymentId': 'payment-retry'},
      );
      await outbox.enqueue(
        operationId: 'sale.create:ok',
        operationType: 'sale.create',
        payload: {'saleId': 'sale-ok'},
      );
      await outbox.enqueue(
        operationId: 'sale.create:conflict',
        operationType: 'sale.create',
        payload: {'saleId': 'sale-conflict'},
      );

      final processor = OutboxProcessor(
        outbox: outbox,
        cache: CacheRepository(await databases.cache),
        apiClient: CloudApiClient(
          baseUrl: 'http://${server.address.host}:${server.port}',
        ),
        accessTokenProvider: () async => 'token',
      );

      final report = await processor.processDue();
      expect(report.scanned, 3);
      expect(report.acknowledged, 2);
      expect(report.retryable, 1);

      expect(
        (await outbox.find('payment.register:retry'))!.status,
        OutboxStatus.retryableFailure,
      );
      expect(
        (await outbox.find('sale.create:ok'))!.status,
        OutboxStatus.acknowledged,
      );
      expect(
        (await outbox.find('sale.create:conflict'))!.status,
        OutboxStatus.acknowledged,
      );
    },
  );
}
