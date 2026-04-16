import 'dart:io';
import 'dart:async';

import '../domain/disk_info.dart';

class DiskDetectionService {
  String? extractDriveLetter(String path) {
    final trimmed = path.trim();
    if (trimmed.length < 2 || trimmed[1] != ':') {
      return null;
    }
    return '${trimmed[0].toUpperCase()}:';
  }

  String getSystemDrive() {
    final executablePath = Platform.resolvedExecutable;
    return extractDriveLetter(executablePath) ?? 'C:';
  }

  bool isPathOnSystemDrive(String path) {
    final drive = extractDriveLetter(path);
    if (drive == null) {
      return false;
    }
    return drive == getSystemDrive();
  }

  Future<bool> canAccessBackupPath(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return false;
    }

    final directory = Directory(trimmed);
    if (await directory.exists()) {
      return true;
    }

    final drive = extractDriveLetter(trimmed);
    if (drive == null) {
      return false;
    }

    return Directory('$drive\\').exists();
  }

  Future<bool> openInFileExplorer(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return false;
    }

    final created = await createBackupDirectory(trimmed);
    if (!created) {
      return false;
    }

    try {
      ProcessResult result;
      if (Platform.isWindows) {
        result = await Process.run('explorer', [trimmed]);
      } else if (Platform.isMacOS) {
        result = await Process.run('open', [trimmed]);
      } else if (Platform.isLinux) {
        result = await Process.run('xdg-open', [trimmed]);
      } else {
        return false;
      }

      return result.exitCode == 0;
    } catch (e) {
      print('Error opening backup folder $trimmed: $e');
      return false;
    }
  }

  /// Detects all available drives on Windows with proper error handling and validation
  Future<List<DiskInfo>> detectAvailableDrives() async {
    final drives = <DiskInfo>[];

    // On Windows, check all drive letters from C: to Z:
    for (int i = 67; i <= 90; i++) {
      final drive = String.fromCharCode(i) + ':';

      try {
        final directory = Directory(drive + '\\');

        // Check if drive exists and is accessible
        if (await directory.exists()) {
          try {
            // Get volume size and free space using PowerShell with timeout
            final sizeResult =
                await Process.run('powershell', [
                  '-NoProfile',
                  '-Command',
                  '(Get-Volume -DriveLetter ${drive[0]} | Select-Object -ExpandProperty Size)',
                ]).timeout(
                  const Duration(seconds: 5),
                  onTimeout: () =>
                      ProcessResult(0, 1, '', 'PowerShell timeout'),
                );

            if (sizeResult.exitCode != 0) {
              continue; // Skip drives that don't respond
            }

            final totalSizeStr = sizeResult.stdout.toString().trim();
            final totalSize = int.tryParse(totalSizeStr) ?? 0;

            if (totalSize <= 0) {
              continue; // Skip empty or invalid drives
            }

            // Get free space
            final freeResult =
                await Process.run('powershell', [
                  '-NoProfile',
                  '-Command',
                  '(Get-Volume -DriveLetter ${drive[0]} | Select-Object -ExpandProperty SizeRemaining)',
                ]).timeout(
                  const Duration(seconds: 5),
                  onTimeout: () =>
                      ProcessResult(0, 1, '', 'PowerShell timeout'),
                );

            final freeStr = freeResult.stdout.toString().trim();
            final freeSize = int.tryParse(freeStr) ?? 0;

            // Get drive label using fsutil
            final labelResult =
                await Process.run('fsutil', [
                  'volume',
                  'diskfree',
                  '${drive}\\',
                ]).timeout(
                  const Duration(seconds: 5),
                  onTimeout: () => ProcessResult(0, 1, '', 'fsutil timeout'),
                );

            String driveLabel = _getDriveLabel(drive);
            if (labelResult.exitCode == 0) {
              // Try to extract label from fsutil output
              try {
                final lines = labelResult.stdout.toString().split('\n');
                if (lines.length > 1) {
                  driveLabel = lines[0]
                      .replaceAll(RegExp(r'[^\w\s]'), '')
                      .trim();
                  if (driveLabel.isEmpty) {
                    driveLabel = _getDriveLabel(drive);
                  }
                }
              } catch (e) {
                // Use default label
              }
            }

            drives.add(
              DiskInfo(
                drive: drive,
                label: driveLabel,
                totalSize: totalSize,
                freeSize: freeSize,
                isAvailable: true,
                isSystemDrive: drive[0].toUpperCase() == 'C',
              ),
            );
          } catch (e) {
            print('Error getting disk info for $drive: $e');
            // Skip this drive and continue
          }
        }
      } catch (e) {
        // Drive doesn't exist or is not accessible, continue
      }
    }

    return drives;
  }

  /// Get the primary/system drive
  Future<DiskInfo?> getPrimaryDrive(List<DiskInfo> drives) async {
    try {
      // Get the drive where exe is running
      final applicationPath = Platform.resolvedExecutable;
      final driveLetter = applicationPath[0].toUpperCase();

      return drives.firstWhere(
        (d) => d.drive.startsWith(driveLetter),
        orElse: () => drives.firstWhere(
          (d) => d.isSystemDrive,
          orElse: () => drives.isNotEmpty
              ? drives.first
              : DiskInfo(
                  drive: 'C:',
                  label: 'System',
                  totalSize: 0,
                  freeSize: 0,
                  isAvailable: false,
                  isSystemDrive: true,
                ),
        ),
      );
    } catch (e) {
      return null;
    }
  }

  /// Get recommended secondary drive for backups
  /// Prefers larger, non-system drives
  Future<DiskInfo?> getSecondaryDrive(List<DiskInfo> drives) async {
    final nonSystemDrives = drives
        .where((d) => !d.isSystemDrive && d.isAvailable && d.hasEnoughSpace)
        .toList();

    if (nonSystemDrives.isEmpty) {
      return null;
    }

    // Sort by free space descending
    nonSystemDrives.sort((a, b) => b.freeSize.compareTo(a.freeSize));
    return nonSystemDrives.first;
  }

  /// Check if a specific path is available
  Future<bool> isPathAvailable(String path) async {
    try {
      final directory = Directory(path);
      return await directory.exists();
    } catch (e) {
      return false;
    }
  }

  /// Create a backup directory if it doesn't exist
  Future<bool> createBackupDirectory(String path) async {
    try {
      final directory = Directory(path);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Get drive label/name from Windows with better defaults
  String _getDriveLabel(String drive) {
    try {
      // Map common drive letters to more descriptive names
      switch (drive[0].toUpperCase()) {
        case 'C':
          return 'Windows (Sistema)';
        case 'D':
          return 'Datos/Almacenamiento';
        case 'E':
          return 'Unidad Externa';
        case 'F':
          return 'Backup/Externa';
        default:
          return 'Disco ${drive[0]}';
      }
    } catch (e) {
      return drive;
    }
  }
}
