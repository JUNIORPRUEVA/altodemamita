import { ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { ConfigService } from '@nestjs/config';

import { AppModule } from './app.module';
import { HttpExceptionFilter } from './shared/filters/http-exception.filter';
import { ResponseInterceptor } from './shared/interceptors/response.interceptor';
import { isCorsOriginAllowed } from './shared/utils/panel-origin.util';

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(AppModule, { cors: false });
  const configService = app.get(ConfigService);
  const apiPrefix = configService.get<string>('app.apiPrefix', 'api');
  const port = configService.get<number>('app.port', 3000);
  const nodeEnv = configService.get<string>('app.nodeEnv', 'development');
  const configuredOrigins = configService.get<string[]>('security.panelWebOrigins') ?? [];
  const panelWebOrigins =
    nodeEnv === 'development'
      ? Array.from(new Set([...configuredOrigins, 'http://localhost:8080']))
      : configuredOrigins;

  app.enableCors({
    origin: (
      origin: string | undefined,
      callback: (error: Error | null, allow?: boolean) => void,
    ) => {
      if (isCorsOriginAllowed(origin, panelWebOrigins)) {
        callback(null, true);
        return;
      }

      callback(new Error('Origen no autorizado por CORS.'), false);
    },
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: [
      'Content-Type',
      'Authorization',
      'Accept',
      'Origin',
      'x-admin-key',
    ],
    credentials: false,
    optionsSuccessStatus: 204,
  });

  // Root health checks (no /api prefix) for reverse proxies/load balancers.
  // Keep the normal Nest routes available under /api/health as well.
  // We use the underlying HTTP adapter so these stay outside the global prefix.
  const payload = () => ({ ok: true, timestamp: new Date().toISOString() });
  const http: any = app.getHttpAdapter().getInstance();
  if (http && typeof http.get === 'function') {
    http.get('/health', (_req: any, res: any) => res.status(200).json(payload()));
    http.get('/ping', (_req: any, res: any) => res.status(200).json(payload()));
  }

  app.setGlobalPrefix(apiPrefix);
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      transform: true,
      forbidNonWhitelisted: true,
    }),
  );
  app.useGlobalFilters(new HttpExceptionFilter());
  app.useGlobalInterceptors(new ResponseInterceptor());
  app.enableShutdownHooks();

  await app.listen(port);
}

void bootstrap();