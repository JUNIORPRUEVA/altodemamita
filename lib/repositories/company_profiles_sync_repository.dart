import '../core/database/app_database.dart';
import '../core/database/database_schema.dart';
import 'sync_repository.dart';

class CompanyProfilesSyncRepository implements SyncRepository {
  CompanyProfilesSyncRepository({AppDatabase? appDatabase})
    : _appDatabase = appDatabase ?? AppDatabase.instance;

  final AppDatabase _appDatabase;

  @override
  String get scope => 'company_profiles';

  @override
  String get uploadPath => '/sync/upload';

  @override
  String get downloadPath => '/sync/changes';

  @override
  Future<List<Map<String, Object?>>> getPendingRecords() async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      DatabaseSchema.companyProfilesTable,
      where: 'sync_status IN (?, ?, ?, ?, ?)',
      whereArgs: [
        DatabaseSchema.syncStatusPending,
        DatabaseSchema.syncStatusPendingCreate,
        DatabaseSchema.syncStatusPendingUpdate,
        DatabaseSchema.syncStatusPendingDelete,
        DatabaseSchema.syncStatusFailed,
      ],
      orderBy: 'updated_at ASC',
    );

    return rows
        .map(
          (row) => {
            'id': row['id'],
            'id_remote': row['id_remote'],
            'sync_id': row['sync_id'],
            'name': row['name'],
            'phone': row['phone'],
            'address': row['address'],
            'logo_base64': row['logo_base64'],
            'local_path': row['local_path'],
            'remote_url': row['remote_url'],
            'upload_status': row['upload_status'],
            'created_at': row['created_at'],
            'updated_at': row['updated_at'],
            'deleted_at': row['deleted_at'],
            'sync_status': row['sync_status'],
          },
        )
        .toList(growable: false);
  }

  @override
  Future<void> markAsSynced(Iterable<String> syncIds) async {
    await _markRows(syncIds, DatabaseSchema.syncStatusSynced);
  }

  @override
  Future<void> markAsConflict(Iterable<String> syncIds) async {
    await _markRows(syncIds, DatabaseSchema.syncStatusConflict);
  }

  @override
  Future<void> mergeRemoteRecords(List<Map<String, dynamic>> records) async {
    if (records.isEmpty) {
      return;
    }

    final db = await _appDatabase.database;
    await db.transaction((txn) async {
      for (final record in records) {
        final syncId = record['sync_id']?.toString().trim() ?? '';
        if (syncId.isEmpty) {
          continue;
        }

        final remoteId = record['id']?.toString().trim();
        var existing = await txn.query(
          DatabaseSchema.companyProfilesTable,
          columns: ['id'],
          where: 'sync_id = ?',
          whereArgs: [syncId],
          limit: 1,
        );
        if (existing.isEmpty && remoteId != null && remoteId.isNotEmpty) {
          existing = await txn.query(
            DatabaseSchema.companyProfilesTable,
            columns: ['id'],
            where: 'id_remote = ?',
            whereArgs: [remoteId],
            limit: 1,
          );
        }

        final nowIso = DateTime.now().toIso8601String();
        final createdAt = record['created_at']?.toString() ?? nowIso;
        final updatedAt = record['updated_at']?.toString() ?? nowIso;
        final deletedAt = record['deleted_at']?.toString();
        final values = {
          'sync_id': syncId,
          'id_remote': remoteId,
          'id_local': existing.isEmpty ? null : existing.first['id'],
          'name': record['name']?.toString() ?? 'Empresa',
          'phone': record['phone']?.toString(),
          'address': record['address']?.toString(),
          'logo_base64': record['logo_base64']?.toString(),
          'local_path': record['local_path']?.toString(),
          'remote_url': record['remote_url']?.toString(),
          'upload_status':
              record['upload_status']?.toString() ??
              DatabaseSchema.uploadStatusSynced,
          'created_at': createdAt,
          'updated_at': updatedAt,
          'last_modified_remote': updatedAt,
          'deleted_at': deletedAt,
          'sync_status': DatabaseSchema.syncStatusSynced,
        };

        if (existing.isEmpty) {
          await txn.insert(DatabaseSchema.companyProfilesTable, values);
        } else {
          await txn.update(
            DatabaseSchema.companyProfilesTable,
            values,
            where: 'id = ?',
            whereArgs: [existing.first['id']],
          );
        }

        await _mirrorCompanyInfo(
          txn,
          name: values['name']?.toString() ?? 'Empresa',
          phone: values['phone']?.toString(),
          address: values['address']?.toString(),
          logoBase64: values['logo_base64']?.toString(),
          localPath: values['local_path']?.toString(),
          remoteUrl: values['remote_url']?.toString(),
          uploadStatus:
              values['upload_status']?.toString() ??
              DatabaseSchema.uploadStatusSynced,
          remoteId: remoteId,
          syncStatus: DatabaseSchema.syncStatusSynced,
          createdAt: createdAt,
          updatedAt: updatedAt,
          deletedAt: deletedAt,
        );
      }
    });
  }

  Future<void> _markRows(Iterable<String> syncIds, String status) async {
    final ids = syncIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (ids.isEmpty) {
      return;
    }

    final db = await _appDatabase.database;
    final placeholders = List.filled(ids.length, '?').join(', ');
    await db.rawUpdate(
      'UPDATE ${DatabaseSchema.companyProfilesTable} '
      'SET sync_status = ? '
      'WHERE sync_id IN ($placeholders)',
      [status, ...ids],
    );
  }

  Future<void> _mirrorCompanyInfo(
    dynamic txn, {
    required String name,
    required String? phone,
    required String? address,
    required String? logoBase64,
    required String? localPath,
    required String? remoteUrl,
    required String uploadStatus,
    required String? remoteId,
    required String syncStatus,
    required String createdAt,
    required String updatedAt,
    required String? deletedAt,
  }) async {
    final companyRows = await txn.query(
      DatabaseSchema.companyInfoTable,
      columns: ['id'],
      limit: 1,
    );

    final values = {
      'nombre': name,
      'telefono': phone,
      'direccion': address,
      'logo_base64': logoBase64,
      'local_path': localPath,
      'remote_url': remoteUrl,
      'upload_status': uploadStatus,
      'id_remote': remoteId,
      'sync_status': syncStatus,
      'last_modified_remote': updatedAt,
      'deleted_at': deletedAt,
      'fecha_creacion': createdAt,
      'fecha_actualizacion': updatedAt,
    };

    if (companyRows.isEmpty) {
      await txn.insert(DatabaseSchema.companyInfoTable, values);
      return;
    }

    await txn.update(
      DatabaseSchema.companyInfoTable,
      values,
      where: 'id = ?',
      whereArgs: [companyRows.first['id']],
    );
  }
}
