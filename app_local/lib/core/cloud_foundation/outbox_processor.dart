import 'dart:convert';

import 'cache_repository.dart';
import 'cloud_api_client.dart';
import 'outbox_repository.dart';

class OutboxProcessor {
  const OutboxProcessor({
    required OutboxRepository outbox,
    required CacheRepository cache,
    required CloudApiClient apiClient,
    required Future<String> Function() accessTokenProvider,
  }) : _outbox = outbox,
       _cache = cache,
       _apiClient = apiClient,
       _accessTokenProvider = accessTokenProvider;

  final OutboxRepository _outbox;
  final CacheRepository _cache;
  final CloudApiClient _apiClient;
  final Future<String> Function() _accessTokenProvider;

  Future<OutboxProcessReport> processDue() async {
    final due = await _outbox.dueOperations();
    var acknowledged = 0;
    var retryable = 0;
    var permanent = 0;

    for (final operation in due) {
      await _outbox.markSending(operation.operationId);
      final token = await _accessTokenProvider();
      final response = await _apiClient.sendOperation(
        operationType: operation.operationType,
        operationId: operation.operationId,
        payload: operation.payload,
        accessToken: token,
      );

      if (response.isSuccess) {
        await _outbox.acknowledge(operation.operationId, response.body);
        await _cache.putMetadata(
          'last_ack:${operation.operationId}',
          jsonEncode(response.body),
        );
        acknowledged += 1;
        continue;
      }

      final safeError = _safeError(response);
      if (response.isRetryable) {
        await _outbox.failRetryable(operation.operationId, safeError);
        retryable += 1;
      } else if (response.isBusinessConflict) {
        await _outbox.failPermanent(operation.operationId, safeError);
        permanent += 1;
      } else if (response.isPermanentFailure) {
        await _outbox.failPermanent(operation.operationId, safeError);
        permanent += 1;
      } else {
        await _outbox.failRetryable(operation.operationId, safeError);
        retryable += 1;
      }
    }

    return OutboxProcessReport(
      scanned: due.length,
      acknowledged: acknowledged,
      retryable: retryable,
      permanent: permanent,
    );
  }
}

class OutboxProcessReport {
  const OutboxProcessReport({
    required this.scanned,
    required this.acknowledged,
    required this.retryable,
    required this.permanent,
  });

  final int scanned;
  final int acknowledged;
  final int retryable;
  final int permanent;
}

String _safeError(CloudApiResponse response) {
  final error = response.body['error'];
  if (error is Map) {
    final code = error['code']?.toString();
    final message = error['message']?.toString();
    return [code, message].whereType<String>().join(': ');
  }
  return response.body['message']?.toString() ??
      'HTTP ${response.statusCode} cloud operation failed';
}
