class BackendEntityIdRegistry {
  BackendEntityIdRegistry._();

  static final BackendEntityIdRegistry instance = BackendEntityIdRegistry._();

  final Map<String, int> _localIdByKey = {};
  final Map<String, String> _remoteIdByLocalKey = {};
  final Set<int> _usedLocalIds = {};

  int register(String namespace, String remoteId) {
    final normalizedNamespace = namespace.trim().toLowerCase();
    final normalizedRemoteId = remoteId.trim();
    final compositeKey = '$normalizedNamespace::$normalizedRemoteId';
    final existing = _localIdByKey[compositeKey];
    if (existing != null) {
      return existing;
    }

    var candidate = normalizedRemoteId.hashCode & 0x7fffffff;
    if (candidate == 0) {
      candidate = 1;
    }
    while (_usedLocalIds.contains(candidate)) {
      candidate += 1;
    }

    _localIdByKey[compositeKey] = candidate;
    _remoteIdByLocalKey['$normalizedNamespace::$candidate'] = normalizedRemoteId;
    _usedLocalIds.add(candidate);
    return candidate;
  }

  String? resolveRemoteId(String namespace, int? localId) {
    if (localId == null) {
      return null;
    }
    final normalizedNamespace = namespace.trim().toLowerCase();
    return _remoteIdByLocalKey['$normalizedNamespace::$localId'];
  }
}