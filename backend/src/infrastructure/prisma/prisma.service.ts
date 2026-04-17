import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';

import { ensureDerivedEnvironmentVariables, resolveDatabaseUrl } from 'src/config/environment';

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit {
  private readonly logger = new Logger(PrismaService.name);

  constructor() {
    ensureDerivedEnvironmentVariables();

    const databaseUrl = resolveDatabaseUrl();
    super(
      databaseUrl
        ? {
            datasources: {
              db: {
                url: databaseUrl,
              },
            },
          }
        : undefined,
    );
  }

  async onModuleInit(): Promise<void> {
    const maxRetries = this.parsePositiveInt(
      process.env.PRISMA_CONNECT_MAX_RETRIES,
      10,
    );
    const retryDelayMs = this.parsePositiveInt(
      process.env.PRISMA_CONNECT_RETRY_DELAY_MS,
      3000,
    );

    let attempt = 1;
    while (attempt <= maxRetries) {
      try {
        await this.$connect();
        if (attempt > 1) {
          this.logger.log(`Conexion Prisma establecida en el intento ${attempt}.`);
        }
        return;
      } catch (error) {
        if (attempt >= maxRetries) {
          this.logger.error(
            `Prisma no pudo conectarse despues de ${maxRetries} intentos.`,
            error instanceof Error ? error.stack : undefined,
          );
          throw error;
        }

        this.logger.warn(
          `Prisma no pudo conectarse en el intento ${attempt}/${maxRetries}. Reintentando en ${retryDelayMs}ms.`,
        );
        await this.delay(retryDelayMs);
        attempt += 1;
      }
    }
  }

  private parsePositiveInt(rawValue: string | undefined, fallback: number): number {
    const parsed = Number(rawValue);
    if (!Number.isFinite(parsed) || parsed < 1) {
      return fallback;
    }

    return Math.floor(parsed);
  }

  private async delay(durationMs: number): Promise<void> {
    await new Promise((resolve) => setTimeout(resolve, durationMs));
  }
}