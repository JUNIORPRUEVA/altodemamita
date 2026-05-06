import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PC vieja pierde escritura cuando otra reclama principal', () async {
    final backendState = FakeBackendState()..initialized = true;
    final httpClient = FakeBackendHttpClient(state: backendState);

    await _post(
      httpClient,
      '/devices/register',
      deviceId: 'pc-vieja',
      body: {
        'device_id': 'pc-vieja',
        'device_name': 'PC vieja',
        'platform': 'windows',
      },
    );
    await _post(
      httpClient,
      '/devices/claim-primary',
      deviceId: 'pc-nueva',
      body: {
        'device_id': 'pc-nueva',
        'device_name': 'PC nueva',
        'platform': 'windows',
      },
    );

    final oldDevice = await _get(httpClient, '/devices/current', deviceId: 'pc-vieja');
    final newDevice = await _get(httpClient, '/devices/current', deviceId: 'pc-nueva');

    expect(oldDevice['canWrite'], isFalse);
    expect(oldDevice['isPrimary'], isFalse);
    expect(oldDevice['reason'], 'device_not_primary');
    expect(newDevice['canWrite'], isTrue);
    expect(newDevice['isPrimary'], isTrue);
  });
}

Future<Map<String, dynamic>> _post(
  HttpClient client,
  String path, {
  required String deviceId,
  required Map<String, dynamic> body,
}) async {
  final request = await client.postUrl(Uri.parse('http://127.0.0.1:9999/api$path'));
  request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
  request.headers.contentType = ContentType.json;
  request.headers.set(HttpHeaders.authorizationHeader, 'Bearer jwt-test-token');
  request.headers.set('x-device-id', deviceId);
  request.write(jsonEncode(body));
  final response = await request.close();
  final raw = await utf8.decoder.bind(response).join();
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  return decoded['data'] as Map<String, dynamic>;
}

Future<Map<String, dynamic>> _get(
  HttpClient client,
  String path, {
  required String deviceId,
}) async {
  final request = await client.getUrl(Uri.parse('http://127.0.0.1:9999/api$path'));
  request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
  request.headers.set(HttpHeaders.authorizationHeader, 'Bearer jwt-test-token');
  request.headers.set('x-device-id', deviceId);
  final response = await request.close();
  final raw = await utf8.decoder.bind(response).join();
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  return decoded['data'] as Map<String, dynamic>;
}