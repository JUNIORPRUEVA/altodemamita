import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sistema_solares_ui/core/network/api_client.dart';

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient({required this.handler});

  final Future<http.Response> Function(http.BaseRequest request) handler;
  int requestCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestCount += 1;
    final response = await handler(request);
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
      reasonPhrase: response.reasonPhrase,
    );
  }
}

void main() {
  test('pwa bloquea sync upload antes de llegar a HTTP', () async {
    final client = _FakeHttpClient(
      handler: (_) async => http.Response('{"ok":true}', 200),
    );
    final apiClient = ApiClient(client: client);

    await expectLater(
      apiClient.post('/sync/upload', body: {
        'device_id': 'pwa-device',
        'records': <String, dynamic>{},
      }),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          'Esta accion no esta disponible en el panel web',
        ),
      ),
    );

    expect(client.requestCount, 0);
  });
}