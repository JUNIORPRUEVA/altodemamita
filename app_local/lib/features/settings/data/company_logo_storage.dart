import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'company_logo_storage_io.dart'
    if (dart.library.js_interop) 'company_logo_storage_web.dart'
    as platform;

Future<Uint8List?> readLogoBytesFromLocalPath(String? localPath) {
  return platform.readLogoBytesFromLocalPath(localPath);
}

Future<String?> persistCompanyLogoLocally(Uint8List? bytes) {
  return platform.persistCompanyLogoLocally(bytes);
}

Future<Uint8List?> readPickedLogoBytes(PlatformFile file) {
  return platform.readPickedLogoBytes(file);
}
