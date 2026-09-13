import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;

import '../../../core/resilience/app_paths.dart';

Future<Uint8List?> readLogoBytesFromLocalPath(String? localPath) async {
  final normalized = localPath?.trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }

  final file = File(normalized);
  if (!await file.exists()) {
    return null;
  }

  return file.readAsBytes();
}

Future<String?> persistCompanyLogoLocally(Uint8List? bytes) async {
  if (bytes == null || bytes.isEmpty) {
    return null;
  }

  final appPaths = AppPaths();
  await Directory(appPaths.mediaDirectory).create(recursive: true);
  final filename = 'company_logo_${DateTime.now().millisecondsSinceEpoch}.png';
  final filePath = path.join(appPaths.mediaDirectory, filename);
  final file = File(filePath);
  await file.writeAsBytes(bytes, flush: true);
  return filePath;
}

Future<Uint8List?> readPickedLogoBytes(PlatformFile file) async {
  final bytes = file.bytes;
  if (bytes != null && bytes.isNotEmpty) {
    return bytes;
  }

  final filePath = file.path;
  if (filePath == null || filePath.trim().isEmpty) {
    return null;
  }

  return File(filePath).readAsBytes();
}
