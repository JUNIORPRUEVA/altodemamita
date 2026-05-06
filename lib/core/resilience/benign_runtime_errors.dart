import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class BenignRuntimeErrors {
  const BenignRuntimeErrors._();

  static bool shouldSuppress(Object error) {
    return isDatabaseClosedDuringShutdown(error);
  }

  static bool isDatabaseClosedDuringShutdown(Object error) {
    if (error is DatabaseException && error.isDatabaseClosedError()) {
      return true;
    }

    final message = error.toString().toLowerCase();
    return message.contains('database_closed') ||
        message.contains('this database has already been closed');
  }
}
