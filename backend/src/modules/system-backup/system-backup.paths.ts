import * as os from 'node:os';
import * as path from 'node:path';

export function getCloudBackupsDir(): string {
  const fromEnv = (process.env.CLOUD_BACKUPS_DIR || process.env.SYSTEM_BACKUP_STORAGE_DIR || '').trim();
  if (fromEnv) {
    return path.resolve(fromEnv);
  }

  // In containers this resolves to "/tmp" (writable for non-root users).
  return path.join(os.tmpdir(), 'cloud_backups');
}
