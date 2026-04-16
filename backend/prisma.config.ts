import 'dotenv/config';
import { defineConfig, env } from 'prisma/config';

import { ensureDerivedEnvironmentVariables } from './src/config/environment';

ensureDerivedEnvironmentVariables();

export default defineConfig({
  schema: 'prisma/schema.prisma',
  migrations: {
    path: 'prisma/migrations',
  },
  engine: 'classic',
  datasource: {
    url: env('DATABASE_URL'),
  },
  seed: 'tsx prisma/seed.ts',
});