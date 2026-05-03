import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/app/navigation/sync_visual_state.dart';
import 'package:sistema_solares/models/sync/sync_connection_status.dart';

void main() {
  test('topbar_hides_sync_status_when_online_test', () {
    final state = getSyncVisualState(
      buildSyncVisualStateInput(
        connectionStatus: SyncConnectionStatus.connected,
        pendingCount: 8,
        failedCount: 2,
        isSyncing: true,
      ),
    );

    expect(state, SyncVisualState.hidden);
    expect(shouldShowOfflineChip(hasInternet: true), isFalse);
  });

  test('topbar_hides_retry_pending_when_online_test', () {
    final state = getSyncVisualState(
      buildSyncVisualStateInput(
        connectionStatus: SyncConnectionStatus.error,
        pendingCount: 0,
        failedCount: 9,
        isSyncing: false,
      ),
    );

    expect(state, SyncVisualState.hidden);
    expect(shouldShowOfflineChip(hasInternet: true), isFalse);
  });

  test('topbar_hides_pending_sync_when_online_test', () {
    final state = getSyncVisualState(
      buildSyncVisualStateInput(
        connectionStatus: SyncConnectionStatus.connected,
        pendingCount: 3,
        failedCount: 4,
        isSyncing: false,
      ),
    );

    expect(state, SyncVisualState.hidden);
    expect(shouldShowOfflineChip(hasInternet: true), isFalse);
  });

  test('topbar_shows_only_sin_internet_when_offline_test', () {
    final state = getSyncVisualState(
      buildSyncVisualStateInput(
        connectionStatus: SyncConnectionStatus.disconnected,
        pendingCount: 11,
        failedCount: 7,
        isSyncing: true,
      ),
    );

    expect(state, SyncVisualState.offline);
    expect(shouldShowOfflineChip(hasInternet: false), isTrue);
  });

  test('no_sync_technical_text_visible_in_main_ui_test', () {
    const forbidden = <String>[
      'Reintento sync',
      'Pendiente sync',
      'Sincronizando',
      'Error',
      'Error de conexion',
      'Error de conexión',
    ];
    const topBarVisibleLabel = 'Sin internet';

    for (final text in forbidden) {
      expect(topBarVisibleLabel.contains(text), isFalse);
    }
  });

  test('background_sync_still_runs_when_indicator_hidden_test', () {
    final stateWhileSyncing = getSyncVisualState(
      buildSyncVisualStateInput(
        connectionStatus: SyncConnectionStatus.connected,
        pendingCount: 5,
        failedCount: 2,
        isSyncing: true,
      ),
    );

    final stateWithPending = getSyncVisualState(
      buildSyncVisualStateInput(
        connectionStatus: SyncConnectionStatus.connected,
        pendingCount: 5,
        failedCount: 0,
        isSyncing: false,
      ),
    );

    expect(stateWhileSyncing, SyncVisualState.hidden);
    expect(stateWithPending, SyncVisualState.hidden);
    expect(shouldShowLargeSyncBanner(stateWhileSyncing), isFalse);
  });
}
