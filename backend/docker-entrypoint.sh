#!/bin/sh
set -eu

# Ensure the cloud backups directory exists and is writable.
mkdir -p /cloud_backups

# When a host volume is mounted, ownership/permissions might change.
# Best-effort fix before dropping privileges.
chown -R nestjs:nodejs /cloud_backups 2>/dev/null || true
chmod -R 777 /cloud_backups 2>/dev/null || true

exec su-exec nestjs:nodejs sh -c "npx prisma migrate deploy && node dist/main.js"
