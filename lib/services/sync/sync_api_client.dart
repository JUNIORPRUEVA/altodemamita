import 'dart:convert';
import 'dart:io';

import '../../core/system/system_config_service.dart';
import '../../models/sync/sync_conflict_strategy.dart';
import '../../models/sync/sync_settings.dart';

class SyncConflictItem {
  const SyncConflictItem({
    required this.scope,
    required this.recordSyncId,
    required this.localVersion,
    required this.serverVersion,
    this.localRecord,
    this.serverRecord,
    this.message,
  });

  final String scope;
  final String recordSyncId;
  final int? localVersion;
  final int? serverVersion;
  final Map<String, dynamic>? localRecord;
  final Map<String, dynamic>? serverRecord;
  final String? message;

  factory SyncConflictItem.fromMap(Map<String, dynamic> map) {
    return SyncConflictItem(
      scope: map['scope']?.toString() ?? '',
      recordSyncId:
          map['record_sync_id']?.toString() ?? map['sync_id']?.toString() ?? '',
      localVersion: SyncApiClient._readInt(
        map['local_version'] ?? map['client_version'],
      ),
      serverVersion: SyncApiClient._readInt(
        map['server_version'] ?? map['version'],
      ),
      localRecord: SyncApiClient._readRecord(map['local_record']),
      serverRecord: SyncApiClient._readRecord(
        map['server_record'] ?? map['record'],
      ),
      message: map['message']?.toString(),
    );
  }
}

class SyncConflictException implements Exception {
  const SyncConflictException({
    required this.message,
    required this.scope,
    required this.strategy,
    required this.conflicts,
    required this.serverUri,
    this.returnedRecords = const [],
    this.serverTime,
  });

  final String message;
  final String scope;
  final SyncConflictStrategy strategy;
  final List<SyncConflictItem> conflicts;
  final List<Map<String, dynamic>> returnedRecords;
  final DateTime? serverTime;
  final Uri serverUri;

  @override
  String toString() => message;
}

class SyncUploadResponse {
  const SyncUploadResponse({
    required this.returnedRecordsByScope,
    this.serverTime,
  });

  final Map<String, List<Map<String, dynamic>>> returnedRecordsByScope;
  final DateTime? serverTime;

  List<Map<String, dynamic>> recordsForScope(String scope) {
    return returnedRecordsByScope[scope] ?? const [];
  }
}

class SyncDownloadResponse {
  const SyncDownloadResponse({required this.recordsByScope, this.serverTime});

  final Map<String, List<Map<String, dynamic>>> recordsByScope;
  final DateTime? serverTime;

  List<Map<String, dynamic>> recordsForScope(String scope) {
    return recordsByScope[scope] ?? const [];
  }
}

class SyncApiClient {
  static const List<String> _scopes = [
    'clients',
    'products',
    'sellers',
    'sales',
    'installments',
    'payments',
  ];

  SyncApiClient({HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient() {
    _httpClient.connectionTimeout = const Duration(seconds: 10);
    _httpClient.idleTimeout = const Duration(seconds: 15);
  }

  final HttpClient _httpClient;

  Future<SyncUploadResponse> uploadQueuedRecords({
    required SyncSettings settings,
    required Map<String, List<Map<String, Object?>>> recordsByScope,
  }) async {
    final uri = Uri.parse('${settings.normalizedBaseUrl}/sync/upload');
    final payload = <String, Object?>{
      'device_id': settings.deviceId,
      'records': _normalizeRecordsPayload(recordsByScope),
    };
    final body = await _sendJsonRequest(
      method: 'POST',
      uri: uri,
      jwtToken: settings.jwtToken,
      payload: payload,
    );

    return SyncUploadResponse(
      returnedRecordsByScope: _readRecordsByScope(body['records']),
      serverTime: _readDate(body['server_time']),
    );
  }

  Future<SyncDownloadResponse> downloadChanges({
    required SyncSettings settings,
    DateTime? updatedSince,
  }) async {
    final queryParameters = <String, String>{
      'device_id': settings.deviceId,
      if (updatedSince != null)
        'updatedSince': updatedSince.toUtc().toIso8601String(),
    };
    final uri = Uri.parse(
      '${settings.normalizedBaseUrl}/sync/download',
    ).replace(queryParameters: queryParameters);
    final body = await _sendJsonRequest(
      method: 'GET',
      uri: uri,
      jwtToken: settings.jwtToken,
    );

    return SyncDownloadResponse(
      recordsByScope: _readRecordsByScope(body['records']),
      serverTime: _readDate(body['server_time']),
    );
  }

  Future<Map<String, dynamic>> _sendJsonRequest({
    required String method,
    required Uri uri,
    required String jwtToken,
    Map<String, Object?>? payload,
  }) async {
    final request = await _openRequest(method, uri);
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $jwtToken');

    if (payload != null) {
      request.write(jsonEncode(payload));
    }

    final response = await request.close();
    final responseBody = await utf8.decoder.bind(response).join();
    final decodedBody = _unwrapResponseEnvelope(_decodeJsonObject(responseBody));
    if (response.statusCode == 409) {
      throw SyncConflictException(
        message:
            decodedBody['message']?.toString() ??
            'La API reporto un conflicto de version.',
        scope:
            decodedBody['scope']?.toString() ??
            '',
        strategy: SyncConflictStrategy.fromStorage(
          decodedBody['strategy'] ?? decodedBody['conflict_strategy'],
        ),
        conflicts: _readConflictList(decodedBody['conflicts']),
        returnedRecords: _readRecordList(decodedBody['records']),
        serverTime: _readDate(decodedBody['server_time']),
        serverUri: uri,
      );
    }
    if (response.statusCode == HttpStatus.forbidden &&
        decodedBody['message']?.toString() == 'READ_ONLY_MODE') {
      throw const ReadOnlyModeException();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'La API de sincronizacion respondio con ${response.statusCode}: $responseBody',
        uri: uri,
      );
    }

    return decodedBody;
  }

  Map<String, dynamic> _unwrapResponseEnvelope(Map<String, dynamic> payload) {
    final data = payload['data'];
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), value));
    }
    return payload;
  }

  Future<HttpClientRequest> _openRequest(String method, Uri uri) {
    switch (method.toUpperCase()) {
      case 'GET':
        return _httpClient.getUrl(uri);
      case 'POST':
        return _httpClient.postUrl(uri);
      default:
        throw UnsupportedError('Metodo HTTP no soportado: $method');
    }
  }

  List<Map<String, dynamic>> _readRecordList(Object? value) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<Map>()
        .map((item) {
          return item.map((key, data) => MapEntry(key.toString(), data));
        })
        .toList(growable: false);
  }

  Map<String, List<Map<String, dynamic>>> _readRecordsByScope(Object? value) {
    final normalized = <String, List<Map<String, dynamic>>>{
      for (final scope in _scopes) scope: const [],
    };
    if (value is! Map) {
      return normalized;
    }

    for (final scope in _scopes) {
      normalized[scope] = _readRecordList(value[scope]);
    }
    return normalized;
  }

  Map<String, Object?> _normalizeRecordsPayload(
    Map<String, List<Map<String, Object?>>> recordsByScope,
  ) {
    return {
      for (final scope in _scopes)
        scope: recordsByScope[scope] ?? const <Map<String, Object?>>[],
    };
  }

  List<SyncConflictItem> _readConflictList(Object? value) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<Map>()
        .map((item) {
          return SyncConflictItem.fromMap(
            item.map((key, data) => MapEntry(key.toString(), data)),
          );
        })
        .toList(growable: false);
  }

  Map<String, dynamic> _decodeJsonObject(String responseBody) {
    if (responseBody.trim().isEmpty) {
      return const {};
    }

    final decoded = jsonDecode(responseBody);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'La API de sincronizacion no devolvio un objeto JSON valido.',
      );
    }
    return decoded;
  }

  DateTime? _readDate(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    return DateTime.tryParse(text);
  }

  static int? _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static Map<String, dynamic>? _readRecord(Object? value) {
    if (value is! Map) {
      return null;
    }
    return value.map((key, data) => MapEntry(key.toString(), data));
  }
}
