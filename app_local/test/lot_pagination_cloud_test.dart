import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sistema_solares/core/config/app_flags.dart';
import 'package:sistema_solares/core/database/app_database.dart';
import 'package:sistema_solares/core/network/backend_api_client.dart';
import 'package:sistema_solares/features/lots/data/lot_repository.dart';

/// API simulada que pagina igual que `GET /business/lots`.
class _PagedLotsApiClient extends BackendApiClient {
  _PagedLotsApiClient({required this.total});

  final int total;
  static const int availablePerPage = 1;
  final List<Map<String, String>> requests = [];

  @override
  Future<dynamic> get(
    String path, {
    Map<String, String>? queryParameters,
    bool authorized = true,
    String? idempotencyKey,
  }) async {
    requests.add(Map<String, String>.from(queryParameters ?? const {}));
    final page = int.tryParse(queryParameters?['page'] ?? '1') ?? 1;
    final limit = int.tryParse(queryParameters?['limit'] ?? '100') ?? 100;
    final onlyAvailable = queryParameters?['status'] == 'disponible';
    final sourceTotal = onlyAvailable ? availablePerPage : total;
    final start = (page - 1) * limit;
    final end = (start + limit) > sourceTotal ? sourceTotal : start + limit;
    final items = <Map<String, dynamic>>[
      for (var index = start; index < end; index++)
        {
          'id': 'remote-lot-$index',
          'syncId': 'remote-lot-sync-$index',
          'block': 'M-N',
          'number': '${1000 + index}',
          'status': onlyAvailable || index < availablePerPage
              ? 'disponible'
              : 'vendido',
          'area': 200,
          'price': 3000,
          'version': 1,
          'createdAt': '2026-01-01T00:00:00.000Z',
          'updatedAt': '2026-01-01T00:00:00.000Z',
        },
    ];
    return {
      'data': {
        'items': items,
        'total': sourceTotal,
        'page': page,
        'pageSize': limit,
      },
    };
  }
}

void main() {
  late Directory tempDirectory;
  late AppDatabase appDatabase;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('lots_paging_');
    appDatabase = AppDatabase.test(path.join(tempDirectory.path, 'test.db'));
    await appDatabase.initialize();
  });

  tearDown(() async {
    await appDatabase.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('lee mas de 100 solares recorriendo todas las paginas', () async {
    expect(
      cloudCutoverMode.usesAuthoritativeBusinessWrites,
      isTrue,
      reason:
          'Este test debe ejecutarse con '
          '--dart-define=CLOUD_CUTOVER_MODE=CLOUD_AUTHORITATIVE',
    );

    final api = _PagedLotsApiClient(total: 117);
    final repository = LotRepository(
      appDatabase: appDatabase,
      apiClient: api,
    );

    final lots = await repository.fetchAll();

    expect(lots, hasLength(117));
    expect(api.requests.map((request) => request['page']), ['1', '2']);
    expect(
      lots.where((lot) => lot.isAvailable),
      hasLength(1),
      reason: 'Solo el primer solar simulado esta disponible.',
    );
    // Los vendidos se conservan con su estado real para poder explicarlo.
    expect(lots.where((lot) => lot.normalizedStatus == 'vendido'), hasLength(116));
  });
}
