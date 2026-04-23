import 'dart:io';
import 'dart:typed_data';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class BackupValidatorAgent {
  const BackupValidatorAgent();

  Future<void> validateSQLiteDbFile(File file) async {
    if (!await file.exists()) {
      throw StateError('El archivo de base de datos no existe.');
    }

    final length = await file.length();
    if (length <= 0) {
      throw StateError('El archivo de base de datos está vacío.');
    }

    // Fast signature validation without opening SQLite.
    final header = await _readFirstBytes(file, 16);
    final expected = Uint8List.fromList(
      'SQLite format 3\x00'.codeUnits,
    );
    for (var i = 0; i < expected.length; i++) {
      if (i >= header.length || header[i] != expected[i]) {
        throw StateError('El archivo no parece ser una base SQLite válida.');
      }
    }

    await _validateSQLiteOpens(file);
  }

  Future<void> _validateSQLiteOpens(File file) async {
    Database? db;
    try {
      db = await databaseFactoryFfi.openDatabase(
        file.path,
        options: OpenDatabaseOptions(
          readOnly: true,
          singleInstance: false,
        ),
      );

      final rows = await db.rawQuery('PRAGMA quick_check(1)');
      final first = rows.isNotEmpty ? rows.first.values.first : null;
      final normalized = first?.toString().trim().toLowerCase() ?? '';
      if (normalized != 'ok') {
        throw StateError('El archivo SQLite no pasó la verificación de integridad.');
      }
    } catch (e) {
      throw StateError('No se pudo abrir/verificar la base SQLite del backup.');
    } finally {
      try {
        await db?.close();
      } catch (_) {
        // Best effort.
      }
    }
  }

  Future<void> validateZipFile(File file) async {
    if (!await file.exists()) {
      throw StateError('El archivo ZIP no existe.');
    }

    final length = await file.length();
    if (length <= 0) {
      throw StateError('El archivo ZIP está vacío.');
    }

    final header = await _readFirstBytes(file, 4);
    // ZIP local file header signature: 50 4B 03 04
    if (header.length < 4 ||
        header[0] != 0x50 ||
        header[1] != 0x4B ||
        header[2] != 0x03 ||
        header[3] != 0x04) {
      throw StateError('El archivo no parece ser un ZIP válido.');
    }
  }

  Future<Uint8List> _readFirstBytes(File file, int count) async {
    final raf = await file.open();
    try {
      final buffer = Uint8List(count);
      final read = await raf.readInto(buffer);
      return Uint8List.sublistView(buffer, 0, read);
    } finally {
      await raf.close();
    }
  }
}
