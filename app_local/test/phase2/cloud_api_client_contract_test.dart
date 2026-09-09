import 'dart:convert';
import 'dart:io';

import 'package:sistema_solares/core/cloud_foundation/cloud_api_client.dart';
import 'package:test/test.dart';

void main() {
  test('refresh sends token field expected by backend contract', () async {
    late Map<String, Object?> receivedBody;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final handling = server.first.then((request) async {
      expect(request.method, 'POST');
      expect(request.uri.path, '/auth/refresh');
      receivedBody =
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, Object?>;
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'accessToken': 'jwt-refreshed',
            'data': {'accessToken': 'jwt-refreshed'},
          }),
        );
      await request.response.close();
    });

    addTearDown(() async {
      await handling;
      await server.close(force: true);
    });

    final client = CloudApiClient(
      baseUrl: 'http://${server.address.host}:${server.port}',
    );

    final response = await client.refresh(refreshToken: 'jwt-original');

    expect(response.statusCode, HttpStatus.ok);
    expect(receivedBody['token'], 'jwt-original');
    expect(receivedBody.containsKey('refreshToken'), isFalse);
  });
}
