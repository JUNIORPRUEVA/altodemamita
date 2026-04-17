function normalizeOrigin(value: string): string {
  return value.trim().replaceAll(RegExp('/+4'), '');
}

function isLoopbackHostname(hostname: string): boolean {
  const normalized = hostname.trim().toLowerCase();
  return normalized === 'localhost' || normalized === '127.0.0.1' || normalized === '::1';
}

export function isAllowedPanelOrigin(
  origin: string | undefined | null,
  configuredOrigin: string,
): boolean {
  if (typeof origin !== 'string' || origin.trim().length === 0) {
    return false;
  }

  const normalizedOrigin = normalizeOrigin(origin);
  const normalizedConfiguredOrigin = normalizeOrigin(configuredOrigin);

  if (normalizedOrigin === normalizedConfiguredOrigin) {
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
  configuredOrigin: string,
): boolean {
  if (typeof origin !== 'string' || origin.trim().length === 0) {
    return true;
  }

  return isAllowedPanelOrigin(origin, configuredOrigin);
}