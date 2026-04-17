function normalizeOrigin(value: string): string {
  return value.trim().replace(/\/+$/, '');
}

function normalizeConfiguredOrigins(configuredOrigin: string | string[]): string[] {
  const values = Array.isArray(configuredOrigin)
    ? configuredOrigin
    : configuredOrigin.split(',');

  return [...new Set(
    values
      .map((value) => value.trim())
      .filter((value) => value.length > 0)
      .map(normalizeOrigin),
  )];
}

function isLoopbackHostname(hostname: string): boolean {
  const normalized = hostname.trim().toLowerCase();
  return normalized === 'localhost' || normalized === '127.0.0.1' || normalized === '::1';
}

export function isAllowedPanelOrigin(
  origin: string | undefined | null,
  configuredOrigin: string | string[],
): boolean {
  if (typeof origin !== 'string' || origin.trim().length === 0) {
    return false;
  }

  const normalizedOrigin = normalizeOrigin(origin);
  const normalizedConfiguredOrigins = normalizeConfiguredOrigins(configuredOrigin);

  if (normalizedConfiguredOrigins.includes(normalizedOrigin)) {
    return true;
  }

  try {
    const parsed = new URL(normalizedOrigin);
    return parsed.protocol === 'http:' && isLoopbackHostname(parsed.hostname);
  } catch {
    return false;
  }
}

export function isCorsOriginAllowed(
  origin: string | undefined,
  configuredOrigin: string | string[],
): boolean {
  if (typeof origin !== 'string' || origin.trim().length === 0) {
    return true;
  }

  return isAllowedPanelOrigin(origin, configuredOrigin);
}