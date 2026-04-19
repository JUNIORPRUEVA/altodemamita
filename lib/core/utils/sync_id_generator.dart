class SyncIdGenerator {
  SyncIdGenerator._();

  static int _lastMicrosecondsSinceEpoch = 0;
  static int _sequence = 0;

  static String next(String scope, {int? microsecondsSinceEpoch}) {
    final timestamp = microsecondsSinceEpoch ?? DateTime.now().microsecondsSinceEpoch;
    if (timestamp == _lastMicrosecondsSinceEpoch) {
      _sequence += 1;
    } else {
      _lastMicrosecondsSinceEpoch = timestamp;
      _sequence = 0;
    }

    return '$scope-$timestamp-${_sequence.toRadixString(36)}';
  }
}