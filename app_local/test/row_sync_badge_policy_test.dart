import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/shared/sync/row_sync_badge_policy.dart';

void main() {
  test('client_list_hides_sync_badge_when_online_test', () {
    expect(
      shouldShowRowSyncBadge(
        hasInternet: true,
        syncStatus: 'pending_create',
        isFailed: false,
      ),
      isFalse,
    );

    expect(
      shouldShowRowSyncBadge(
        hasInternet: true,
        syncStatus: 'failed',
        isFailed: true,
      ),
      isFalse,
    );
  });

  test('client_list_shows_tiny_local_badge_only_when_offline_test', () {
    expect(
      shouldShowRowSyncBadge(
        hasInternet: false,
        syncStatus: 'pending_update',
        isFailed: false,
      ),
      isTrue,
    );

    expect(
      rowSyncBadgeLabel(syncStatus: 'pending_update', isFailed: false),
      'local',
    );
  });

  test('sync_badge_never_shows_technical_text_test', () {
    final localLabel = rowSyncBadgeLabel(
      syncStatus: 'pending_delete',
      isFailed: false,
    );
    final pendingLabel = rowSyncBadgeLabel(syncStatus: 'failed', isFailed: true);

    expect(localLabel, 'local');
    expect(pendingLabel, 'pendiente');

    const forbidden = <String>[
      'pendiente de sync',
      'reintento sync',
      'sincronizando',
      'error',
    ];

    for (final text in forbidden) {
      expect(localLabel!.toLowerCase().contains(text), isFalse);
      expect(pendingLabel!.toLowerCase().contains(text), isFalse);
    }
  });

  test('synced_records_never_show_badge_test', () {
    expect(
      shouldShowRowSyncBadge(
        hasInternet: false,
        syncStatus: 'synced',
        isFailed: false,
      ),
      isFalse,
    );
    expect(rowSyncBadgeLabel(syncStatus: 'synced', isFailed: false), isNull);
  });
}
