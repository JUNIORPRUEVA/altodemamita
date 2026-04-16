import 'dart:convert';

import 'package:printing/printing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_schema.dart';
import '../../../core/system/system_config_service.dart';
import '../domain/printer_config.dart';

class PrinterRepository {
  PrinterRepository({AppDatabase? appDatabase})
    : _appDatabase = appDatabase ?? AppDatabase.instance;

  final AppDatabase _appDatabase;

  Future<Database> get _database async => _appDatabase.database;

  Future<List<PrinterConfig>> getAllPrinters() async {
    try {
      final database = await _database;
      final maps = await database.query(
        DatabaseSchema.printerConfigTable,
        orderBy: 'es_predeterminada DESC, nombre ASC',
      );
      return maps.map((map) => PrinterConfig.fromMap(map)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<PrinterConfig?> getPrinterById(int id) async {
    try {
      final database = await _database;
      final maps = await database.query(
        DatabaseSchema.printerConfigTable,
        where: 'id = ?',
        whereArgs: [id],
      );

      if (maps.isEmpty) {
        return null;
      }

      return PrinterConfig.fromMap(maps.first);
    } catch (e) {
      return null;
    }
  }

  Future<PrinterConfig?> getDefaultPrinter() async {
    try {
      final database = await _database;
      final maps = await database.query(
        DatabaseSchema.printerConfigTable,
        where: 'es_predeterminada = ?',
        whereArgs: [1],
        limit: 1,
      );

      if (maps.isEmpty) {
        return null;
      }

      return PrinterConfig.fromMap(maps.first);
    } catch (e) {
      return null;
    }
  }

  Future<PrinterConfig> createPrinter(PrinterConfig printer) async {
    SystemConfigService.instance.ensureWritable();

    final database = await _database;
    // If this is the first printer, make it default
    final existing = await getDefaultPrinter();
    final printerToSave = existing == null && !printer.esPredeterminada
        ? printer.copyWith(esPredeterminada: true)
        : printer;

    final id = await database.insert(
      DatabaseSchema.printerConfigTable,
      printerToSave.toMap(),
    );
    return printerToSave.copyWith(id: id);
  }

  Future<void> updatePrinter(PrinterConfig printer) async {
    SystemConfigService.instance.ensureWritable();

    if (printer.id == null) {
      throw Exception('Printer ID cannot be null');
    }

    final database = await _database;

    // If setting as default, unset others
    if (printer.esPredeterminada) {
      await database.update(
        DatabaseSchema.printerConfigTable,
        {'es_predeterminada': 0},
        where: 'id != ?',
        whereArgs: [printer.id],
      );
    }

    await database.update(
      DatabaseSchema.printerConfigTable,
      printer.toMap(),
      where: 'id = ?',
      whereArgs: [printer.id],
    );
  }

  Future<void> deletePrinter(int id) async {
    SystemConfigService.instance.ensureWritable();

    final database = await _database;
    final printer = await getPrinterById(id);
    await database.delete(
      DatabaseSchema.printerConfigTable,
      where: 'id = ?',
      whereArgs: [id],
    );

    if (printer?.esPredeterminada != true) {
      return;
    }

    final remainingPrinters = await getAllPrinters();
    if (remainingPrinters.isNotEmpty && remainingPrinters.first.id != null) {
      await setDefaultPrinter(remainingPrinters.first.id!);
    }
  }

  Future<void> setDefaultPrinter(int id) async {
    SystemConfigService.instance.ensureWritable();

    final printer = await getPrinterById(id);
    if (printer != null) {
      await updatePrinter(printer.copyWith(esPredeterminada: true));
    }
  }

  Future<List<Printer>> getSystemPrinters() async {
    final info = await Printing.info();
    if (!info.canListPrinters) {
      return const [];
    }

    final printers = await Printing.listPrinters();
    printers.sort((left, right) {
      final leftDefault = left.isDefault == true;
      final rightDefault = right.isDefault == true;
      if (leftDefault && !rightDefault) {
        return -1;
      }
      if (!leftDefault && rightDefault) {
        return 1;
      }
      return left.name.compareTo(right.name);
    });
    return printers.where((printer) => printer.isAvailable != false).toList();
  }

  PrinterConfig mergeSystemPrinter({
    required Printer printer,
    PrinterConfig? current,
    required String tipo,
    required bool esPredeterminada,
  }) {
    final now = DateTime.now();
    final base = current ?? PrinterConfig.empty();
    return base.copyWith(
      nombre: printer.name,
      modelo: (printer.model ?? '').trim().isEmpty
          ? (current?.modelo ?? printer.name)
          : printer.model,
      tipo: tipo,
      esPredeterminada: esPredeterminada,
      configuracionJson: jsonEncode(printer.toMap()),
      fechaCreacion: current?.fechaCreacion ?? now,
      fechaActualizacion: now,
    );
  }

  Future<Printer?> resolvePrinter(PrinterConfig config) async {
    final configMap = config.configuracionMap;
    if (configMap.isEmpty) {
      return null;
    }

    final printers = await getSystemPrinters();
    final savedUrl = configMap['url'] as String?;
    final savedName = configMap['name'] as String?;
    final savedModel = configMap['model'] as String?;

    for (final printer in printers) {
      if (savedUrl != null && savedUrl.isNotEmpty && printer.url == savedUrl) {
        return printer;
      }
    }

    for (final printer in printers) {
      final sameName = savedName != null && printer.name == savedName;
      final sameModel = savedModel == null || savedModel.isEmpty || printer.model == savedModel;
      if (sameName && sameModel) {
        return printer;
      }
    }

    try {
      return Printer.fromMap(configMap);
    } catch (_) {
      return null;
    }
  }
}
