import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_schema.dart';
import '../../../core/system/system_config_service.dart';
import '../domain/seller.dart';

class SellerRepository {
  SellerRepository({AppDatabase? database})
    : _appDatabase = database ?? AppDatabase.instance;

  final AppDatabase _appDatabase;

  Future<List<Seller>> getAll() async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      DatabaseSchema.sellersTable,
      orderBy: 'nombre ASC',
    );

    return rows.map((row) => Seller.fromMap(row)).toList();
  }

  Future<Seller?> getById(int id) async {
    final db = await _appDatabase.database;
    final rows = await db.query(
      DatabaseSchema.sellersTable,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return Seller.fromMap(rows.first);
  }

  Future<int> insert(Seller seller) async {
    SystemConfigService.instance.ensureWritable();

    final db = await _appDatabase.database;
    return await db.insert(
      DatabaseSchema.sellersTable,
      seller.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> update(Seller seller) async {
    SystemConfigService.instance.ensureWritable();

    if (seller.id == null) {
      throw ArgumentError('Seller must have an ID to update');
    }

    final db = await _appDatabase.database;
    await db.update(
      DatabaseSchema.sellersTable,
      seller.toMap(),
      where: 'id = ?',
      whereArgs: [seller.id],
    );
  }

  Future<void> delete(int id) async {
    SystemConfigService.instance.ensureWritable();

    final db = await _appDatabase.database;
    await db.delete(
      DatabaseSchema.sellersTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Seller>> search(String query) async {
    final db = await _appDatabase.database;
    final normalizedQuery = '%${query.toLowerCase()}%';

    final rows = await db.query(
      DatabaseSchema.sellersTable,
      where:
          'LOWER(nombre) LIKE ? OR LOWER(cedula) LIKE ? OR LOWER(telefono) LIKE ?',
      whereArgs: [normalizedQuery, normalizedQuery, normalizedQuery],
      orderBy: 'nombre ASC',
    );

    return rows.map((row) => Seller.fromMap(row)).toList();
  }
}
