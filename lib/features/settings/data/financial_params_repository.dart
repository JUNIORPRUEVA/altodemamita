import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sistema_solares/core/database/database_schema.dart';
import 'package:sistema_solares/core/system/system_config_service.dart';
import '../domain/financial_params.dart';

class FinancialParamsRepository {
  const FinancialParamsRepository(this.database);

  final Database database;

  Future<FinancialParams> getParams() async {
    try {
      final maps = await database.query(
        DatabaseSchema.financialParamsTable,
        limit: 1,
      );

      if (maps.isEmpty) {
        await _initializeDefaults();
        return FinancialParams.defaults();
      }

      return FinancialParams.fromMap(maps.first);
    } catch (e) {
      return FinancialParams.defaults();
    }
  }

  Future<void> saveParams(FinancialParams params) async {
    SystemConfigService.instance.ensureWritable();

    final existing = await getParams();

    if (existing.id != null) {
      await database.update(
        DatabaseSchema.financialParamsTable,
        params.toMap(),
        where: 'id = ?',
        whereArgs: [existing.id],
      );
    } else {
      await database.insert(
        DatabaseSchema.financialParamsTable,
        params.toMap(),
      );
    }
  }

  Future<void> _initializeDefaults() async {
    final defaults = FinancialParams.defaults();
    await database.insert(
      DatabaseSchema.financialParamsTable,
      defaults.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<double> getInitialPercentageDefault() async {
    final params = await getParams();
    return params.initialPercentageDefault;
  }

  Future<double> getMonthlyInterestDefault() async {
    final params = await getParams();
    return params.monthlyInterestDefault;
  }

  Future<int> getInstallmentCountDefault() async {
    final params = await getParams();
    return params.installmentCountDefault;
  }

  Future<void> updateInitialPercentage(double percentage) async {
    SystemConfigService.instance.ensureWritable();

    final params = await getParams();
    await saveParams(params.copyWith(initialPercentageDefault: percentage));
  }

  Future<void> updateMonthlyInterest(double interest) async {
    SystemConfigService.instance.ensureWritable();

    final params = await getParams();
    await saveParams(params.copyWith(monthlyInterestDefault: interest));
  }

  Future<void> updateInstallmentCount(int count) async {
    SystemConfigService.instance.ensureWritable();

    final params = await getParams();
    await saveParams(params.copyWith(installmentCountDefault: count));
  }
}
