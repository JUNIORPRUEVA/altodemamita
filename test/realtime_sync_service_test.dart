import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/repositories/sync_repository.dart';
import 'package:sistema_solares/services/realtime_sync_service.dart';
import 'package:sistema_solares/services/sync/sync_service.dart';

void main() {
  test('entity.updated de ventas invalida tambien payments', () {
    final service = RealtimeSyncService(
      syncService: SyncService(
        repositories: [
          _FakeSyncRepository('clients'),
          _FakeSyncRepository('products'),
          _FakeSyncRepository('sales'),
          _FakeSyncRepository('installments'),
          _FakeSyncRepository('payments'),
        ],
      ),
    );

    final scopes = service.resolveAffectedScopes('entity.updated', {
      'entity': 'sale',
      'action': 'deleted',
    });

    expect(scopes, containsAll(['clients', 'products', 'sales', 'installments', 'payments']));
  });

  test('sale.created invalida payments para evitar cache viejo de iniciales', () {
    final service = RealtimeSyncService(
      syncService: SyncService(
        repositories: [
          _FakeSyncRepository('clients'),
          _FakeSyncRepository('products'),
          _FakeSyncRepository('sales'),
          _FakeSyncRepository('installments'),
          _FakeSyncRepository('payments'),
        ],
      ),
    );

    final scopes = service.resolveAffectedScopes('sale.created', {
      'entity': 'sale',
      'action': 'created',
    });

    expect(scopes, contains('payments'));
  });

  test('ignora solo eventos realmente identicos', () {
    final service = RealtimeSyncService(
      syncService: SyncService(
        repositories: [_FakeSyncRepository('sales')],
      ),
    );

    final payload = {
      'remoteJid': 'chat-1',
      'messageId': 'msg-1',
      'timestamp': '1712000000',
      'pushName': 'Ana',
      'text': 'hola',
    };

    expect(service.registerEventForDeduplication('entity.updated', payload), isTrue);
    expect(service.registerEventForDeduplication('entity.updated', payload), isFalse);
  });

  test('permite mismo id compuesto si cambia el contenido', () {
    final service = RealtimeSyncService(
      syncService: SyncService(
        repositories: [_FakeSyncRepository('sales')],
      ),
    );

    expect(
      service.registerEventForDeduplication('entity.updated', {
        'remoteJid': 'chat-1',
        'messageId': 'msg-1',
        'timestamp': '1712000000',
        'pushName': 'Ana',
        'text': 'hola',
      }),
      isTrue,
    );

    expect(
      service.registerEventForDeduplication('entity.updated', {
        'remoteJid': 'chat-1',
        'messageId': 'msg-1',
        'timestamp': '1712000000',
        'pushName': 'Ana',
        'text': 'hola 2',
      }),
      isTrue,
    );
  });

  test('permite mismo messageId si cambia el timestamp', () {
    final service = RealtimeSyncService(
      syncService: SyncService(
        repositories: [_FakeSyncRepository('sales')],
      ),
    );

    expect(
      service.registerEventForDeduplication('entity.updated', {
        'remoteJid': 'chat-1',
        'messageId': 'msg-1',
        'timestamp': '1712000000',
        'text': 'hola',
      }),
      isTrue,
    );

    expect(
      service.registerEventForDeduplication('entity.updated', {
        'remoteJid': 'chat-1',
        'messageId': 'msg-1',
        'timestamp': '1712000300',
        'text': 'hola',
      }),
      isTrue,
    );
  });
}

class _FakeSyncRepository implements SyncRepository {
  _FakeSyncRepository(this.scope);

  @override
  final String scope;

  @override
  String get uploadPath => '/sync/upload';

  @override
  String get downloadPath => '/sync/download';

  @override
  Future<List<Map<String, Object?>>> getPendingRecords() async => const [];

  @override
  Future<void> markAsSynced(Iterable<String> syncIds) async {}

  @override
  Future<void> markAsConflict(Iterable<String> syncIds) async {}

  @override
  Future<void> mergeRemoteRecords(List<Map<String, dynamic>> records) async {}
}