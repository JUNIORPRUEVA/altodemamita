import 'dotenv/config';

export const config = {
  port: Number(process.env.PORT ?? 3000),
  jwtSecret: process.env.JWT_SECRET ?? '',
  jwtExpiresIn: process.env.JWT_EXPIRES_IN ?? '12h',
  syncDeviceToken: process.env.SYNC_DEVICE_TOKEN ?? '',
  ownerEmail: process.env.OWNER_EMAIL ?? '',
  ownerPassword: process.env.OWNER_PASSWORD ?? '',
  ownerName: process.env.OWNER_NAME ?? 'Dueno',
  techEmail: process.env.TECH_EMAIL ?? '',
  techPassword: process.env.TECH_PASSWORD ?? '',
  techName: process.env.TECH_NAME ?? 'Tecnico',
};

export function validateConfig() {
  const missing = [];
  if (!config.jwtSecret || config.jwtSecret.length < 24) missing.push('JWT_SECRET');
  if (!config.syncDeviceToken || config.syncDeviceToken.length < 16) {
    missing.push('SYNC_DEVICE_TOKEN');
  }
  if (missing.length > 0) {
    throw new Error(`Variables requeridas invalidas: ${missing.join(', ')}`);
  }
}
