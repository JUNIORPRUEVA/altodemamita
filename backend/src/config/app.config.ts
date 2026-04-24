import { ensureDerivedEnvironmentVariables } from './environment';

const PROJECT_PANEL_DEFAULT_ORIGINS = [
  'https://altodemamita.com',
  'https://www.altodemamita.com',
  'https://altodemanita.com',
  'https://www.altodemanita.com',
  'https://altodemanita-altodemamita-pwa.onqyr1.easypanel.host',
];

function isValidHttpOrigin(value: string): boolean {
  try {
    const parsed = new URL(value);
    return parsed.protocol === 'http:' || parsed.protocol === 'https:';
  } catch {
    return false;
  }
}

function parsePanelOrigins(env: NodeJS.ProcessEnv): string[] {
  const candidates = [
    env.PANEL_WEB_ORIGIN,
    ...(env.PANEL_WEB_ORIGINS ?? '').split(','),
    ...PROJECT_PANEL_DEFAULT_ORIGINS,
  ];

  return [
    ...new Set(
      candidates
        .map((value) => value?.trim() ?? '')
        .filter((value) => isValidHttpOrigin(value))
        .filter((value) => value.length > 0),
    ),
  ];
}

export const appConfig = () => {
  const env = ensureDerivedEnvironmentVariables();
  const panelWebOrigins = parsePanelOrigins(env);
  const nodeEnv = env.NODE_ENV ?? 'development';

  return ({
  app: {
    nodeEnv,
    port: Number(env.PORT ?? 3000),
    apiPrefix: env.API_PREFIX ?? 'api',
    appName: env.APP_NAME ?? 'Sistema Solares Backend',
  },
  database: {
    url: env.DATABASE_URL,
    host: env.DB_HOST,
    port: Number(env.DB_PORT ?? 5432),
    username: env.DB_USERNAME,
    name: env.DB_NAME,
  },
  jwt: {
    secret: env.JWT_SECRET,
    expiresIn: env.JWT_EXPIRES_IN ?? '1d',
  },
  security: {
    // In production, never default to localhost.
    // For local development, developers can set PANEL_WEB_ORIGIN(S) explicitly.
    panelWebOrigin:
      panelWebOrigins[0] ??
      (nodeEnv === 'development' ? 'http://localhost:8080' : ''),
    panelWebOrigins:
      nodeEnv === 'development'
        ? [...new Set([...panelWebOrigins, 'http://localhost:8080'])]
        : panelWebOrigins,
  },
  storage: {
    driver: env.STORAGE_DRIVER ?? 'local',
    r2Endpoint: env.R2_ENDPOINT,
    r2Bucket: env.R2_BUCKET,
  },
  system: {
    readOnlyMode: env.READ_ONLY_MODE === 'true',
  },
  });
};