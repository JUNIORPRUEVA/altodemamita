const DEFAULT_DB_PORT = '5432';
const DEFAULT_DB_SCHEMA = 'public';

function hasText(value: string | undefined): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

export function resolveDatabaseUrl(
  env: NodeJS.ProcessEnv = process.env,
): string | undefined {
  if (hasText(env.DATABASE_URL)) {
    return env.DATABASE_URL.trim();
  }

  const host = env.DB_HOST?.trim();
  const port = env.DB_PORT?.trim() || DEFAULT_DB_PORT;
  const username = env.DB_USERNAME?.trim();
  const password = env.DB_PASSWORD;
  const databaseName = env.DB_NAME?.trim();
  const schema = env.DB_SCHEMA?.trim() || DEFAULT_DB_SCHEMA;

  if (!host || !username || password == null || !databaseName) {
    return undefined;
  }

  const encodedUsername = encodeURIComponent(username);
  const encodedPassword = encodeURIComponent(password);
  const credentials = password.length > 0
    ? `${encodedUsername}:${encodedPassword}`
    : encodedUsername;

  return `postgresql://${credentials}@${host}:${port}/${databaseName}?schema=${encodeURIComponent(schema)}`;
}

export function ensureDerivedEnvironmentVariables(
  env: NodeJS.ProcessEnv = process.env,
): NodeJS.ProcessEnv {
  const databaseUrl = resolveDatabaseUrl(env);
  if (databaseUrl && !hasText(env.DATABASE_URL)) {
    env.DATABASE_URL = databaseUrl;
  }

  return env;
}