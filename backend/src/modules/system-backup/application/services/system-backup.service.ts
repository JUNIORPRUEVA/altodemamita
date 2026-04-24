import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import * as fs from 'node:fs/promises';
import * as path from 'node:path';

import { getCloudBackupsDir } from '../../system-backup.paths';

export interface CloudBackupFileInfo {
  id: string;
  filename: string;
  sizeBytes: number;
  modifiedAt: string;
}

@Injectable()
export class SystemBackupService implements OnModuleInit, OnModuleDestroy {
  private readonly storageDir = getCloudBackupsDir();
  private cleanupTimer?: NodeJS.Timeout;

  async onModuleInit(): Promise<void> {
    await this.ensureStorageDir();
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
    await fs.mkdir(this.storageDir, { recursive: true });
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
      return { deleted: false };
    }

    const fullPath = path.join(this.storageDir, safeName);
    try {
      await fs.unlink(fullPath);
      return { deleted: true };
    } catch {
      return { deleted: false };
    }
  }

  async cleanupOldBackups({ keepDays }: { keepDays: number }): Promise<void> {
    await this.ensureStorageDir();

    const cutoff = Date.now() - keepDays * 24 * 60 * 60 * 1000;
    const entries = await fs.readdir(this.storageDir, { withFileTypes: true });

    await Promise.all(
      entries.map(async (entry) => {
        if (!entry.isFile()) return;
        const filename = entry.name;
        const fullPath = path.join(this.storageDir, filename);
        try {
          const stat = await fs.stat(fullPath);
          if (stat.mtimeMs < cutoff) {
            await fs.unlink(fullPath);
          }
        } catch {
          // Best effort.
        }
      }),
    );
  }

  getStorageDir(): string {
    return this.storageDir;
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
