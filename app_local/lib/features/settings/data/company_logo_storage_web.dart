import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<Uint8List?> readLogoBytesFromLocalPath(String? localPath) async {
  return null;
}

Future<String?> persistCompanyLogoLocally(Uint8List? bytes) async {
  return null;
}

Future<Uint8List?> readPickedLogoBytes(PlatformFile file) async {
  final bytes = file.bytes;
  if (bytes == null || bytes.isEmpty) {
    return null;
  }
  return bytes;
}
