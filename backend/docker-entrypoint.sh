#!/bin/sh
set -eu

exec su-exec nestjs:nodejs sh -c "npx prisma migrate deploy && node dist/main.js"
