import { ensureDerivedEnvironmentVariables } from './environment';

function parsePanelOrigins(env: NodeJS.ProcessEnv): string[] {
  const candidates = [
    env.PANEL_WEB_ORIGIN,
    ...(env.PANEL_WEB_ORIGINS ?? '').split(','),
  ];

  return [
    ...new Set(
      candidates
        .map((value) => value?.trim() ?? '')
        .filter((value) => value.length > 0),
    ),
  ];
}

export const appConfig = () => {
  const env = ensureDerivedEnvironmentVariables();
  const panelWebOrigins = parsePanelOrigins(env);

  return ({
  app: {
    nodeEnv: env.NODE_ENV ?? 'development',
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
    panelWebOrigin: panelWebOrigins[0] ?? 'http://localhost:8080',
    panelWebOrigins,
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