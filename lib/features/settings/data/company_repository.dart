import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/core/system/system_config_service.dart';
import '../domain/company_info.dart';

class CompanyRepository {
  const CompanyRepository(this.database);

  final Database database;

  Future<CompanyInfo?> getCompanyInfo() async {
    try {
      final maps = await database.query(
        DatabaseSchema.companyInfoTable,
        limit: 1,
      );

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
      await database.update(
        DatabaseSchema.companyInfoTable,
        company.copyWith(fechaCreacion: existing.fechaCreacion).toMap(),
        where: 'id = ?',
        whereArgs: [existing.id],
      );
      return company.copyWith(id: existing.id, fechaCreacion: existing.fechaCreacion);
    } else {
      final id = await database.insert(
        DatabaseSchema.companyInfoTable,
        company.toMap(),
      );
      return company.copyWith(id: id);
    }
  }

  Future<void> deleteCompanyInfo() async {
    SystemConfigService.instance.ensureWritable();

    await database.delete(DatabaseSchema.companyInfoTable);
  }
}
