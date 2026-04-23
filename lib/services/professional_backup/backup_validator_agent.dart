import 'dart:io';
import 'dart:typed_data';

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
