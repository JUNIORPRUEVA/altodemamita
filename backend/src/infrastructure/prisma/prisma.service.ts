import { Injectable, OnModuleInit } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';

import { ensureDerivedEnvironmentVariables, resolveDatabaseUrl } from 'src/config/environment';

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit {
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
    await this.$connect();
  }
}