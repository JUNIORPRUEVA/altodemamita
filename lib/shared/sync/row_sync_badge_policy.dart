import 'package:flutter/material.dart';

const Set<String> _pendingSyncStatuses = <String>{
  'pending',
  'pending_create',
  'pending_update',
  'pending_delete',
  'pending_sync',
};

bool shouldShowRowSyncBadge({
  required bool hasInternet,
  required String syncStatus,
  required bool isFailed,
}) {
  if (hasInternet) {
    return false;
  }

  final normalized = syncStatus.trim().toLowerCase();
  if (normalized == 'synced') {
    return false;
  }

  if (isFailed || normalized == 'failed') {
    return true;
  }

  return _pendingSyncStatuses.contains(normalized);
}

String? rowSyncBadgeLabel({
  required String syncStatus,
  required bool isFailed,
}) {
  final normalized = syncStatus.trim().toLowerCase();
  if (isFailed || normalized == 'failed') {
    return 'pendiente';
  }
  if (_pendingSyncStatuses.contains(normalized)) {
    return 'local';
  }
  return null;
}

class RowSyncListBadge extends StatelessWidget {
  const RowSyncListBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F5F8),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFD9E0E8), width: 0.8),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 9.5,
            height: 1,
            fontWeight: FontWeight.w600,
            color: Color(0xFF637082),
          ),
        ),
      ),
    );
  }
}
