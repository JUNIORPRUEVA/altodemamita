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
  test('panel blocks write operations on sales routes before reaching HTTP', () async {
    final client = _FakeHttpClient(
      handler: (_) async => http.Response('{"ok":true}', 200),
    );
    final apiClient = ApiClient(client: client);

    await expectLater(
      apiClient.post('/sales', body: {'total': 100}),
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

  test('panel still allows read operations on sales routes', () async {
    final client = _FakeHttpClient(
      handler: (_) async => http.Response('{"ok":true}', 200),
    );
    final apiClient = ApiClient(client: client);

    final response = await apiClient.get('/sales');

    expect(client.requestCount, 1);
    expect(response, {'ok': true});
  });
}