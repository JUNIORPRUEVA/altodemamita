import { bootstrapUsers } from './bootstrap';
import { config, validateConfig } from './config';
import { createApp } from './app';

function getDatabaseName(): string {
  const databaseUrl = process.env.DATABASE_URL || '';
  try {
    const match = databaseUrl.match(
      /postgresql:\/\/[^:]+:[^@]+@([^/]+)\/([^?]+)/,
    );
    if (match) {
      return match[2]; // database name
    }
  } catch {
    // ignore parse errors
  }
  return 'unknown';
}

async function main() {
  validateConfig();
  await bootstrapUsers();

  const databaseName = getDatabaseName();
  const app = createApp();
  app.listen(config.port, () => {
    console.log(`[Backend] listening on port ${config.port}`);
    console.log(`[Backend] databaseName=${databaseName}`);
    console.log(`[Backend] NODE_ENV=${process.env.NODE_ENV || 'development'}`);
  });
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
