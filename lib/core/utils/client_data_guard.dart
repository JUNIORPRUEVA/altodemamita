import '../config/app_flags.dart';
import 'dominican_validators.dart';

class ClientDataGuard {
  static bool isTestLikeName(String? value) {
    final normalized = value?.trim().toLowerCase() ?? '';
    if (normalized.isEmpty) {
      return true;
    }

    const exactMatches = {
      'test',
      'demo',
      'cliente 1',
      'cliente 2',
      'cliente1',
      'cliente2',
    };
    if (exactMatches.contains(normalized)) {
      return true;
    }

    // Avoid false positives like "protesta" or "demografia".
    final tokenPattern = RegExp(r'(^|[\s\-_])(test|demo)([\s\-_]|$)');
    return tokenPattern.hasMatch(normalized);
  }

  static bool hasValidDocumentId(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) {
      return false;
    }
    return DominicanValidators.validateDominicanIdLengthOnly(normalized) == null;
  }

  static bool hasValidSyncId(String? value) {
    final normalized = value?.trim() ?? '';
    return normalized.isNotEmpty;
  }

  static bool shouldBlockClientUpload(Map<String, Object?> payload) {
    if (!isProductionMode) {
      return false;
    }

    final name = payload['full_name']?.toString() ?? payload['nombre']?.toString();
    final doc = payload['document_id']?.toString() ?? payload['cedula']?.toString();
    final syncId = payload['sync_id']?.toString();
    final deletedAt =
        payload['deleted_at']?.toString() ?? payload['deletedAt']?.toString();
    final isDelete = deletedAt.trim().isNotEmpty;

    // Deletes can carry anonymized document IDs (e.g. __DELETED__123).
    // For delete propagation we only require a valid sync_id.
    if (isDelete) {
      return !hasValidSyncId(syncId);
    }

    return isTestLikeName(name) ||
        !hasValidDocumentId(doc) ||
        !hasValidSyncId(syncId);
  }

  static bool shouldBlockClientDownload(Map<String, dynamic> record) {
    if (!isProductionMode) {
      return false;
    }

    final name = record['full_name']?.toString() ?? record['nombre']?.toString();
    final syncId = record['sync_id']?.toString();

    return isTestLikeName(name) ||
        !hasValidSyncId(syncId);
  }
}
