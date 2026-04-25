import { ensureDerivedEnvironmentVariables } from './environment';

const PROJECT_PANEL_DEFAULT_ORIGINS = [
  'https://altodemamita.com',
  'https://www.altodemamita.com',
  'https://altodemanita.com',
  'https://www.altodemanita.com',
  'https://altodemanita-altodemamita-pwa.onqyr1.easypanel.host',
];

const MIN_JWT_EXPIRES_IN_SECONDS = 7 * 24 * 60 * 60;

function parseJwtExpiresInToSeconds(value: string): number | null {
  const normalized = (value ?? '').trim();
  if (!normalized) {
    return null;
  }

  if (/^\d+$/.test(normalized)) {
    const seconds = Number(normalized);
    return Number.isFinite(seconds) ? seconds : null;
  }

  const match = normalized.match(/^([0-9]+)\s*(s|m|h|d)$/i);
  if (!match) {
    return null;
  }

  const amount = Number(match[1]);
  if (!Number.isFinite(amount) || amount <= 0) {
    return null;
  }

  const unit = match[2].toLowerCase();
  switch (unit) {
    case 's':
      return amount;
    case 'm':
      return amount * 60;
    case 'h':
      return amount * 60 * 60;
    case 'd':
      return amount * 24 * 60 * 60;
    default:
      return null;
  }
}

function resolveJwtExpiresIn(envValue: string | undefined): string {
  const configured = (envValue ?? '').trim();
  if (!configured) {
    return '7d';
  }

  const seconds = parseJwtExpiresInToSeconds(configured);
  if (seconds == null) {
    return '7d';
  }

  if (seconds < MIN_JWT_EXPIRES_IN_SECONDS) {
    return '7d';
  }

  return configured;
}

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
    expiresIn: resolveJwtExpiresIn(env.JWT_EXPIRES_IN),
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
  system: {
    readOnlyMode: env.READ_ONLY_MODE === 'true',
  },
  });
};