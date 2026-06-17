import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/models/sync/sync_connection_status.dart';
import 'package:sistema_solares/services/realtime_sync_service.dart';
import 'package:sistema_solares/services/sync/sync_manager.dart';
import 'package:sistema_solares/services/sync/sync_queue_service.dart';

void main() {
  group('resolveEffectiveSyncConnectionStatus', () {
    test('realtime desconectado y cola HTTP sana se considera conectado', () {
      final result = resolveEffectiveSyncConnectionStatus(
        realtimeState: const RealtimeSyncState(
          connectionStatus: SyncConnectionStatus.disconnected,
        ),
        queueState: const SyncQueueState(),
      );

      expect(result, SyncConnectionStatus.connected);
    });

    test('realtime desconectado con pendientes queda desconectado', () {
      final result = resolveEffectiveSyncConnectionStatus(
        realtimeState: const RealtimeSyncState(
          connectionStatus: SyncConnectionStatus.disconnected,
        ),
        queueState: const SyncQueueState(pendingCount: 1),
      );

      expect(result, SyncConnectionStatus.disconnected);
    });

    test('realtime desconectado con error de cola queda desconectado', () {
      final result = resolveEffectiveSyncConnectionStatus(
        realtimeState: const RealtimeSyncState(
          connectionStatus: SyncConnectionStatus.disconnected,
        ),
        queueState: const SyncQueueState(lastError: 'Error de cola'),
      );

      expect(result, SyncConnectionStatus.disconnected);
    });

    test('realtime conectado queda conectado', () {
      final result = resolveEffectiveSyncConnectionStatus(
        realtimeState: const RealtimeSyncState(
          connectionStatus: SyncConnectionStatus.connected,
        ),
        queueState: const SyncQueueState(),
      );

      expect(result, SyncConnectionStatus.connected);
    });
  });
}
