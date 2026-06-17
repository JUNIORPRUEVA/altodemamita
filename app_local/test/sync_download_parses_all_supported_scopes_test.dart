import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/models/sync/sync_conflict_strategy.dart';
import 'package:sistema_solares/models/sync/sync_settings.dart';
import 'package:sistema_solares/services/sync/sync_api_client.dart';

void main() {
  test('sync_download_parses_all_supported_scopes_test', () async {
    final apiClient = SyncApiClient(
      httpClient: _StaticJsonHttpClient({
        'server_time': '2026-05-05T12:00:00.000Z',
        'scope_cursors': {
          'users': '2026-05-05T12:00:00.000Z',
          'roles': '2026-05-05T12:00:00.000Z',
          'user_roles': '2026-05-05T12:00:00.000Z',
          'role_permissions': '2026-05-05T12:00:00.000Z',
          'permissions': '2026-05-05T12:00:00.000Z',
          'clients': '2026-05-05T12:00:00.000Z',
          'products': '2026-05-05T12:00:00.000Z',
          'sellers': '2026-05-05T12:00:00.000Z',
          'sales': '2026-05-05T12:00:00.000Z',
          'installments': '2026-05-05T12:00:00.000Z',
          'payments': '2026-05-05T12:00:00.000Z',
        },
        'records': {
          'users': [
            {'sync_id': 'user-1', 'updated_at': '2026-05-05T11:00:00.000Z'},
          ],
          'roles': [
            {'sync_id': 'role-1', 'updated_at': '2026-05-05T11:00:00.000Z'},
          ],
          'user_roles': [
            {
              'sync_id': 'user-1:role-1',
              'updated_at': '2026-05-05T11:00:00.000Z',
            },
          ],
          'role_permissions': [
            {
              'sync_id': 'role-1:permission-1',
              'updated_at': '2026-05-05T11:00:00.000Z',
            },
          ],
          'permissions': [
            {
              'sync_id': 'permission-1',
              'updated_at': '2026-05-05T11:00:00.000Z',
            },
          ],
          'clients': const [],
          'products': [
            {
              'sync_id': 'product-1',
              'updated_at': '2026-05-05T11:00:00.000Z',
              'deleted_at': '2026-05-05T10:30:00.000Z',
            },
          ],
          'sellers': const [],
          'sales': [
            {
              'sync_id': 'sale-1',
              'updated_at': '2026-05-05T11:00:00.000Z',
              'deleted_at': '2026-05-05T10:31:00.000Z',
            },
          ],
          'installments': [
            {
              'sync_id': 'installment-1',
              'updated_at': '2026-05-05T11:00:00.000Z',
              'deleted_at': '2026-05-05T10:32:00.000Z',
            },
          ],
          'payments': [
            {
              'sync_id': 'payment-1',
              'updated_at': '2026-05-05T11:00:00.000Z',
              'deleted_at': '2026-05-05T10:33:00.000Z',
            },
          ],
        },
      }),
    );

    final response = await apiClient.downloadChanges(
      settings: const SyncSettings(
        baseUrl: 'https://example.test',
        jwtToken: 'jwt-token',
        queueRetryInterval: Duration(seconds: 5),
        realtimePollingInterval: Duration(seconds: 5),
        conflictStrategy: SyncConflictStrategy.lastWriteWins,
        deviceId: 'device-test',
      ),
    );

    expect(response.supportsScope('roles'), isTrue);
    expect(response.supportsScope('user_roles'), isTrue);
    expect(response.supportsScope('role_permissions'), isTrue);
    expect(response.supportsScope('permissions'), isTrue);
    expect(response.recordsForScope('roles'), hasLength(1));
    expect(response.recordsForScope('permissions'), hasLength(1));
    expect(
      response.recordsForScope('products').single['deleted_at'],
      '2026-05-05T10:30:00.000Z',
    );
    expect(
      response.recordsForScope('sales').single['deleted_at'],
      '2026-05-05T10:31:00.000Z',
    );
    expect(
      response.recordsForScope('installments').single['deleted_at'],
      '2026-05-05T10:32:00.000Z',
    );
    expect(
      response.recordsForScope('payments').single['deleted_at'],
      '2026-05-05T10:33:00.000Z',
    );
    expect(response.cursorForScope('payments'), isNotNull);
  });
}

class _StaticJsonHttpClient implements HttpClient {
  _StaticJsonHttpClient(this.payload);

  final Map<String, Object?> payload;
  Duration? _connectionTimeout;
  Duration? _idleTimeout;

  @override
  Duration? get connectionTimeout => _connectionTimeout;

  @override
  set connectionTimeout(Duration? value) {
    _connectionTimeout = value;
  }

  @override
  Duration get idleTimeout => _idleTimeout ?? Duration.zero;

  @override
  set idleTimeout(Duration value) {
    _idleTimeout = value;
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _StaticJsonRequest(payload);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StaticJsonRequest implements HttpClientRequest {
  _StaticJsonRequest(this.payload);

  final Map<String, Object?> payload;
  final HttpHeaders _headers = _StaticHeaders();

  @override
  HttpHeaders get headers => _headers;

  @override
  Future<HttpClientResponse> close() async =>
      _StaticJsonResponse(jsonEncode(payload));

  @override
  void write(Object? obj) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StaticJsonResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _StaticJsonResponse(String body) : _body = body;

  final String _body;

  @override
  int get statusCode => HttpStatus.ok;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(utf8.encode(_body)).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StaticHeaders implements HttpHeaders {
  ContentType? _contentType;
  final Map<String, Object> _values = {};

  @override
  ContentType? get contentType => _contentType;

  @override
  set contentType(ContentType? value) {
    _contentType = value;
  }

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _values[name] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
