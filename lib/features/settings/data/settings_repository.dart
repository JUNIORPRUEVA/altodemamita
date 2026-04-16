import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_schema.dart';
import '../domain/app_setting.dart';

class SettingsRepository {
  static const businessNameKey = 'business_name';
  static const currencySymbolKey = 'currency_symbol';
  static const defaultPaymentMethodKey = 'default_payment_method';
  static const saleDefaultDownPaymentKey =
      'sale_default_down_payment_percentage';
  static const saleDefaultMonthlyInterestKey = 'sale_default_monthly_interest';
  static const saleDefaultInstallmentCountKey =
      'sale_default_installment_count';

  static const defaultSettings = <String, String>{
    businessNameKey: 'EL ALTO DE DONA MAMITA',
    currencySymbolKey: 'RD\$',
    defaultPaymentMethodKey: 'efectivo',
    saleDefaultDownPaymentKey: '10',
    saleDefaultMonthlyInterestKey: '1',
    saleDefaultInstallmentCountKey: '12',
  };

  SettingsRepository({AppDatabase? appDatabase})
    : _appDatabase = appDatabase ?? AppDatabase.instance;

  final AppDatabase _appDatabase;

  Future<Map<String, AppSetting>> fetchByKeys(List<String> keys) async {
    if (keys.isEmpty) {
      return {};
    }

    final db = await _appDatabase.database;
    final placeholders = List.filled(keys.length, '?').join(',');
    final rows = await db.query(
      DatabaseSchema.settingsTable,
      where: 'clave IN ($placeholders)',
      whereArgs: keys,
      orderBy: 'clave ASC',
    );

    final settings = rows.map(AppSetting.fromMap);
    return {for (final setting in settings) setting.key: setting};
  }

  Future<Map<String, AppSetting>> fetchByKeysWithDefaults(
    Map<String, String> defaults,
  ) async {
    await ensureDefaults(defaults);
    return fetchByKeys(defaults.keys.toList());
  }

  Future<void> ensureDefaults([Map<String, String> defaults = defaultSettings]) async {
    final existing = await fetchByKeys(defaults.keys.toList());
    final missingEntries = defaults.entries
        .where((entry) => !existing.containsKey(entry.key))
        .toList();

    if (missingEntries.isEmpty) {
      return;
    }

    final db = await _appDatabase.database;
    final batch = db.batch();
    final now = DateTime.now().toIso8601String();

    for (final entry in missingEntries) {
      batch.insert(DatabaseSchema.settingsTable, {
        'clave': entry.key,
        'valor': entry.value,
        'fecha_actualizacion': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    await batch.commit(noResult: true);
  }

  Future<void> upsert(String key, String value) async {
    final db = await _appDatabase.database;
    await db.insert(DatabaseSchema.settingsTable, {
      'clave': key,
      'valor': value,
      'fecha_actualizacion': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> saveMultiple(Map<String, String> keyValues) async {
    if (keyValues.isEmpty) return;
    final db = await _appDatabase.database;
    final batch = db.batch();
    final now = DateTime.now().toIso8601String();
    for (final entry in keyValues.entries) {
      batch.insert(
        DatabaseSchema.settingsTable,
        {
          'clave': entry.key,
          'valor': entry.value,
          'fecha_actualizacion': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }
}
