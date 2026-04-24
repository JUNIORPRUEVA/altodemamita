import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../sync/sync_config_repository.dart';

class CloudBackupListItem {
  const CloudBackupListItem({
    required this.id,
    required this.filename,
    required this.sizeBytes,
    required this.modifiedAt,
  });

  final String id;
  final String filename;
  final int sizeBytes;
  final String modifiedAt;

  factory CloudBackupListItem.fromJson(Map<String, dynamic> json) {
    return CloudBackupListItem(
      id: (json['id'] ?? json['filename'] ?? '').toString(),
      filename: (json['filename'] ?? json['id'] ?? '').toString(),
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      modifiedAt: (json['modifiedAt'] ?? '').toString(),
    );
  }
}

class CloudRestoreAgent {
  CloudRestoreAgent({
    SyncConfigRepository? syncConfigRepository,
    HttpClient? httpClient,
  }) : _syncConfigRepository = syncConfigRepository ?? SyncConfigRepository(),
       _httpClient = httpClient ?? HttpClient() {
    _httpClient.connectionTimeout = const Duration(seconds: 20);
    _httpClient.idleTimeout = const Duration(seconds: 30);
  }

  final SyncConfigRepository _syncConfigRepository;
  final HttpClient _httpClient;

  Future<List<CloudBackupListItem>> listBackups() async {
    final settings = await _syncConfigRepository.loadSettings();
    if (!settings.isConfigured) {
      throw StateError('La sincronización no está configurada (baseUrl/token).');
    }

    final uri = _buildApiUri(settings.normalizedBaseUrl, '/system/backup/list');
    final request = await _httpClient.getUrl(uri);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${settings.jwtToken}');
    request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);

    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Error listando backups cloud (${response.statusCode}).',
        uri: uri,
      );
    }

    final decoded = body.trim().isEmpty ? const <String, dynamic>{} : jsonDecode(body);
    final payload = _unwrapEnvelope(decoded);

    final itemsAny = payload['items'];
    if (itemsAny is! List) {
      return const <CloudBackupListItem>[];
    }

    return itemsAny
        .whereType<Map>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .map((e) => CloudBackupListItem.fromJson(e))
        .toList();
  }

  Future<File> downloadBackup({
    required String id,
    required String destinationPath,
  }) async {
    final settings = await _syncConfigRepository.loadSettings();
    if (!settings.isConfigured) {
      throw StateError('La sincronización no está configurada (baseUrl/token).');
    }

    final safeId = path.basename(id);
    final uri = _buildApiUri(
      settings.normalizedBaseUrl,
      '/system/backup/download/${Uri.encodeComponent(safeId)}',
    );

    final request = await _httpClient.getUrl(uri);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${settings.jwtToken}');
    request.headers.set(HttpHeaders.acceptHeader, '*/*');

    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await utf8.decoder.bind(response).join();
      throw HttpException(
        'Error descargando backup cloud (${response.statusCode}): ${body.trim()}',
        uri: uri,
      );
    }

    final file = File(destinationPath);
    await file.parent.create(recursive: true);

    final tmpPath = '${file.path}.tmp';
    final tmpFile = File(tmpPath);
    if (await tmpFile.exists()) {
      try {
        await tmpFile.delete();
      } catch (_) {}
    }

    final sink = tmpFile.openWrite();
    try {
      await response.pipe(sink);
    } finally {
      await sink.close();
    }

    try {
      await tmpFile.rename(file.path);
    } on FileSystemException {
      await tmpFile.copy(file.path);
      await tmpFile.delete();
    }

    return file;
  }

  static Uri _buildApiUri(String normalizedBaseUrl, String apiRelativePath) {
    final base = Uri.parse(normalizedBaseUrl);
    final trimmedPath = base.path.replaceAll(RegExp(r'/+$'), '');
    final hasApiPrefix = trimmedPath == '/api' || trimmedPath.endsWith('/api');
    final prefix = hasApiPrefix ? trimmedPath : '$trimmedPath/api';

    final normalizedPrefix = prefix.isEmpty
        ? '/api'
        : (prefix.startsWith('/') ? prefix : '/$prefix');

    final normalizedRelative = apiRelativePath.startsWith('/')
        ? apiRelativePath
        : '/$apiRelativePath';

    return base.replace(path: '$normalizedPrefix$normalizedRelative');
  }

  static Map<String, dynamic> _unwrapEnvelope(Object decoded) {
    if (decoded is Map) {
      final map = decoded.map((k, v) => MapEntry(k.toString(), v));
      final data = map['data'];
      if (data is Map) {
        return data.map((k, v) => MapEntry(k.toString(), v));
      }
      if (map is Map<String, dynamic>) {
        return map;
      }
      return map.cast<String, dynamic>();
    }
    return const <String, dynamic>{};
  }
}
