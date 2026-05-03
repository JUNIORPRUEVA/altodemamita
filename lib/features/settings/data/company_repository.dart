import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/core/system/system_config_service.dart';
import '../domain/company_info.dart';

class CompanyRepository {
  const CompanyRepository(this.database);

  final Database database;

  Future<CompanyInfo?> getCompanyInfo() async {
    try {
      var maps = await database.query(
        DatabaseSchema.companyInfoTable,
        limit: 1,
      );

      if (maps.isEmpty) {
        maps = await database.query(
          DatabaseSchema.companyProfilesTable,
          columns: [
            'id',
            'name AS nombre',
            'phone AS telefono',
            'address AS direccion',
            'logo_base64',
            'local_path',
            'remote_url',
            'upload_status',
            'created_at AS fecha_creacion',
            'updated_at AS fecha_actualizacion',
          ],
          limit: 1,
        );
      }

      if (maps.isEmpty) {
        return null;
      }

      return CompanyInfo.fromMap(maps.first);
    } catch (e) {
      return null;
    }
  }

  Future<CompanyInfo> saveCompanyInfo(CompanyInfo company) async {
    SystemConfigService.instance.ensureWritable();

    final existing = await getCompanyInfo();

    if (existing != null) {
      final persisted = company.copyWith(fechaCreacion: existing.fechaCreacion);
      await database.update(
        DatabaseSchema.companyInfoTable,
        persisted.toMap(),
        where: 'id = ?',
        whereArgs: [existing.id],
      );
      await _upsertCompanyProfile(persisted.copyWith(id: existing.id));
      return persisted.copyWith(id: existing.id);
    } else {
      final id = await database.insert(
        DatabaseSchema.companyInfoTable,
        company.toMap(),
      );
      final persisted = company.copyWith(id: id);
      await _upsertCompanyProfile(persisted);
      return persisted;
    }
  }

  Future<void> deleteCompanyInfo() async {
    SystemConfigService.instance.ensureWritable();

    await database.delete(DatabaseSchema.companyInfoTable);
    await database.delete(DatabaseSchema.companyProfilesTable);
  }

  Future<void> _upsertCompanyProfile(CompanyInfo company) async {
    final existing = await database.query(
      DatabaseSchema.companyProfilesTable,
      columns: ['id'],
      limit: 1,
    );

    final values = {
      'name': company.nombre,
      'phone': company.telefono,
      'address': company.direccion,
      'logo_base64': company.logoBytesBase64,
      'local_path': company.logoLocalPath,
      'remote_url': company.logoRemoteUrl,
      'upload_status': company.logoUploadStatus,
      'id_local': company.id,
      'sync_status':
        company.logoUploadStatus == DatabaseSchema.uploadStatusPending ||
          company.logoUploadStatus == DatabaseSchema.uploadStatusFailed
        ? DatabaseSchema.syncStatusPendingUpdate
        : DatabaseSchema.syncStatusSynced,
      'created_at': company.fechaCreacion.toIso8601String(),
      'updated_at': company.fechaActualizacion.toIso8601String(),
      'last_modified_local': company.fechaActualizacion.toIso8601String(),
      'last_modified_remote': null,
      'deleted_at': null,
    };

    if (existing.isEmpty) {
      await database.insert(DatabaseSchema.companyProfilesTable, values);
      return;
    }

    await database.update(
      DatabaseSchema.companyProfilesTable,
      values,
      where: 'id = ?',
      whereArgs: [existing.first['id']],
    );
  }
}
