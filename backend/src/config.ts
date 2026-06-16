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
  if (!process.env.DATABASE_URL || process.env.DATABASE_URL.trim().length === 0) {
    missing.push('DATABASE_URL');
  }
  if (missing.length > 0) {
    throw new Error(`Variables requeridas invalidas: ${missing.join(', ')}`);
  }
}
