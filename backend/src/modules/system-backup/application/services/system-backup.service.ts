import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';
import * as os from 'node:os';

import { resolveCloudBackupsDir } from '../../system-backup.paths';

export interface CloudBackupFileInfo {
  id: string;
  filename: string;
  sizeBytes: number;
  modifiedAt: string;
}

@Injectable()
export class SystemBackupService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(SystemBackupService.name);
  private readonly storageResolution = resolveCloudBackupsDir();
  private readonly storageDir = this.storageResolution.storageDir;
  private cleanupTimer?: NodeJS.Timeout;

  async onModuleInit(): Promise<void> {
    this.logStorageResolution();
    await this._ensureStorageDir({ warnIfCreated: true });

    await this.validateProductionStorageSafety();

    // Enforce retention periodically even if no requests are made.
    await this.cleanupOldBackups({ keepDays: 4 });

    // Low frequency to minimize resource usage.
    this.cleanupTimer = setInterval(() => {
      void this.cleanupOldBackups({ keepDays: 4 });
    }, 6 * 60 * 60 * 1000);

    // Do not keep the Node process alive just for this timer.
    this.cleanupTimer.unref?.();
  }

  onModuleDestroy(): void {
    if (this.cleanupTimer) {
      clearInterval(this.cleanupTimer);
      this.cleanupTimer = undefined;
    }
  }

  async ensureStorageDir(): Promise<void> {
    await this._ensureStorageDir({ warnIfCreated: false });
  }

  private async _ensureStorageDir({ warnIfCreated }: { warnIfCreated: boolean }): Promise<void> {
    let existed = true;
    try {
      await fs.access(this.storageDir);
    } catch {
      existed = false;
    }

    await fs.mkdir(this.storageDir, { recursive: true });
    if (!existed && warnIfCreated) {
      this.logger.warn(`Cloud backups directory did not exist; created: ${this.storageDir}`);
    }
  }

  private logStorageResolution(): void {
    const isProduction = (process.env.NODE_ENV || '').toLowerCase() === 'production';
    const envRaw = (process.env.CLOUD_BACKUPS_DIR || process.env.SYSTEM_BACKUP_STORAGE_DIR || '').trim();

    this.logger.log(
      `Cloud backups storage dir: ${this.storageDir} (source=${this.storageResolution.source})`,
    );

    if (isProduction) {
      if (!envRaw) {
        this.logger.warn(
          'CLOUD_BACKUPS_DIR is not set in production; using /cloud_backups. Mount a persistent volume to avoid data loss.',
        );
      }

      if (this.storageResolution.forcedFromUnsafeEnv) {
        this.logger.warn(
          `CLOUD_BACKUPS_DIR resolved to a temp directory (${this.storageResolution.envResolved}); ignoring in production and using ${this.storageDir}.`,
        );
      }

      const tmpBase = os.tmpdir();
      if (this.storageDir.startsWith(tmpBase)) {
        this.logger.warn(
          `Cloud backups directory is under OS temp (${tmpBase}). This is not recommended for production.`,
        );
      }
    }
  }

  private async validateProductionStorageSafety(): Promise<void> {
    const isProduction = (process.env.NODE_ENV || '').toLowerCase() === 'production';
    if (!isProduction) {
      return;
    }

    const tmpBase = os.tmpdir();
    if (this.storageDir.startsWith(tmpBase)) {
      // Hard guard: in production this must never be under OS temp.
      const message = `Invalid cloud backups directory in production (under temp): ${this.storageDir}`;
      this.logger.error(message);
      throw new Error(message);
    }

    // Fail fast if the container/user cannot write.
    const probeName = `.write_probe_${Date.now()}_${Math.random().toString(16).slice(2)}.tmp`;
    const probePath = path.join(this.storageDir, probeName);
    try {
      await fs.writeFile(probePath, 'ok', { encoding: 'utf8' });
      await fs.unlink(probePath);
      this.logger.log('Cloud backups directory write probe: OK');
    } catch (error) {
      const message = `Cloud backups directory is not writable in production: ${this.storageDir}`;
      this.logger.error(message, error instanceof Error ? error.stack : undefined);
      throw error;
    }
  }

  async listBackups(): Promise<CloudBackupFileInfo[]> {
    await this.ensureStorageDir();
    await this.cleanupOldBackups({ keepDays: 4 });

    const entries = await fs.readdir(this.storageDir, { withFileTypes: true });
    const items: CloudBackupFileInfo[] = [];

    for (const entry of entries) {
      if (!entry.isFile()) continue;
      const filename = entry.name;
      const fullPath = path.join(this.storageDir, filename);
      try {
        const stat = await fs.stat(fullPath);
        items.push({
          id: filename,
          filename,
          sizeBytes: stat.size,
          modifiedAt: stat.mtime.toISOString(),
        });
      } catch {
        // Skip unreadable entries.
      }
    }

    items.sort((a, b) => b.modifiedAt.localeCompare(a.modifiedAt));
    return items;
  }

  async deleteBackup(id: string): Promise<{ deleted: boolean }> {
    await this.ensureStorageDir();

    const safeName = path.basename(id);
    if (safeName !== id) {
      this.logger.warn(`Cloud backup delete rejected (unsafe id): ${id}`);
      return { deleted: false };
    }

    const fullPath = path.join(this.storageDir, safeName);
    try {
      await fs.unlink(fullPath);
      this.logger.log(`Cloud backup deleted: ${safeName}`);
      return { deleted: true };
    } catch {
      this.logger.warn(`Cloud backup delete failed (not found or no access): ${safeName}`);
      return { deleted: false };
    }
  }

  async cleanupOldBackups({ keepDays }: { keepDays: number }): Promise<void> {
    await this.ensureStorageDir();

    const cutoff = Date.now() - keepDays * 24 * 60 * 60 * 1000;
    const entries = await fs.readdir(this.storageDir, { withFileTypes: true });

    let deletedCount = 0;

    await Promise.all(
      entries.map(async (entry) => {
        if (!entry.isFile()) return;
        const filename = entry.name;
        const fullPath = path.join(this.storageDir, filename);
        try {
          const stat = await fs.stat(fullPath);
          if (stat.mtimeMs < cutoff) {
            await fs.unlink(fullPath);
            deletedCount++;
          }
        } catch {
          // Best effort.
        }
      }),
    );

    if (deletedCount > 0) {
      this.logger.log(
        `Cloud backup retention: deleted ${deletedCount} file(s) older than ${keepDays} day(s).`,
      );
    }
  }

  getStorageDir(): string {
    return this.storageDir;
  }

  resolveBackupPath(id: string): string {
    const safeName = path.basename(id);
    if (safeName !== id) {
      throw new Error('Invalid backup id.');
    }

    // storageDir is already resolved, but normalize final path anyway.
    return path.join(this.storageDir, safeName);
  }

  sanitizeUploadFilename(originalName: string): string {
    const base = path.basename(originalName || '').trim();
    if (!base) {
      return `backup_cloud_${new Date().toISOString().slice(0, 10)}.db.zip`;
    }

    // Avoid awkward characters on Windows filesystems.
    return base.replace(/[<>:"/\\|?*\x00-\x1F]/g, '_');
  }
}
