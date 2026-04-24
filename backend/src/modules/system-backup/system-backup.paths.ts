import * as os from 'node:os';
import * as path from 'node:path';

export type CloudBackupsDirSource = 'env' | 'default-production' | 'default-dev';

export interface CloudBackupsDirResolution {
  storageDir: string;
  source: CloudBackupsDirSource;
  envValue?: string;
  envResolved?: string;
  forcedFromUnsafeEnv?: boolean;
}

function isPathInside(parentDir: string, candidate: string): boolean {
  const parent = path.resolve(parentDir);
  const child = path.resolve(candidate);
  const relative = path.relative(parent, child);
  return relative === '' || (!relative.startsWith('..') && !path.isAbsolute(relative));
}

export function resolveCloudBackupsDir(): CloudBackupsDirResolution {
  const envRaw = (process.env.CLOUD_BACKUPS_DIR || process.env.SYSTEM_BACKUP_STORAGE_DIR || '').trim();
  const isProduction = (process.env.NODE_ENV || '').toLowerCase() === 'production';

  // Production safety: never store cloud backups under the OS temp directory.
  // Default in production is a fixed, mount-friendly path.
  const productionDefault = path.resolve('/cloud_backups');
  const tmpBase = os.tmpdir();

  if (envRaw) {
    const resolved = path.resolve(envRaw);
    if (isProduction && isPathInside(tmpBase, resolved)) {
      return {
        storageDir: productionDefault,
        source: 'default-production',
        envValue: envRaw,
        envResolved: resolved,
        forcedFromUnsafeEnv: true,
      };
    }
    return {
      storageDir: resolved,
      source: 'env',
      envValue: envRaw,
      envResolved: resolved,
    };
  }

  if (isProduction) {
    return {
      storageDir: productionDefault,
      source: 'default-production',
    };
  }

  // Dev/test default: use temp directory.
  return {
    storageDir: path.join(tmpBase, 'cloud_backups'),
    source: 'default-dev',
  };
}

export function getCloudBackupsDir(): string {
  return resolveCloudBackupsDir().storageDir;
}
