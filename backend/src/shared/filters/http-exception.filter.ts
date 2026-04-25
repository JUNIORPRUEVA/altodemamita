import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import { Request, Response } from 'express';

const REDACTED = '[REDACTED]';
const SENSITIVE_KEYS = new Set([
  'authorization',
  'Authorization',
  'password',
  'pass',
  'token',
  'accessToken',
  'refreshToken',
  'jwt',
  'secret',
]);

function truncateString(value: string, maxLen = 500): string {
  if (value.length <= maxLen) return value;
  return `${value.slice(0, maxLen)}…(truncated)`;
}

function redactShallow(value: unknown): unknown {
  if (!value || typeof value !== 'object') {
    if (typeof value === 'string') return truncateString(value);
    return value;
  }

  if (Array.isArray(value)) {
    return { _type: 'array', count: value.length };
  }

  const obj = value as Record<string, unknown>;
  const out: Record<string, unknown> = {};
  for (const [key, raw] of Object.entries(obj)) {
    if (SENSITIVE_KEYS.has(key)) {
      out[key] = REDACTED;
      continue;
    }
    if (typeof raw === 'string') {
      out[key] = truncateString(raw);
      continue;
    }
    if (Array.isArray(raw)) {
      out[key] = { _type: 'array', count: raw.length };
      continue;
    }
    if (raw && typeof raw === 'object') {
      out[key] = { _type: 'object', keys: Object.keys(raw as object) };
      continue;
    }
    out[key] = raw;
  }
  return out;
}

function summarizeRequestBody(path: string, body: unknown): unknown {
  // Never log raw bodies (can be huge + contain sensitive data).
  // Keep a small summary useful for debugging.
  if (!body || typeof body !== 'object') return redactShallow(body);

  const obj = body as Record<string, unknown>;
  const keys = Object.keys(obj);

  // Special-case sync uploads: only keep device + record counts.
  if (path.includes('/api/sync/upload')) {
    const records = obj.records as unknown;
    const recordsSummary: Record<string, unknown> = {};

    if (records && typeof records === 'object' && !Array.isArray(records)) {
      for (const [scope, payload] of Object.entries(records as Record<string, unknown>)) {
        if (Array.isArray(payload)) {
          recordsSummary[scope] = { count: payload.length };
        } else if (payload && typeof payload === 'object') {
          recordsSummary[scope] = { _type: 'object', keys: Object.keys(payload as object) };
        } else {
          recordsSummary[scope] = typeof payload;
        }
      }
    }

    return {
      _keys: keys,
      device_id: typeof obj.device_id === 'string' ? truncateString(obj.device_id, 128) : obj.device_id ?? null,
      records: recordsSummary,
    };
  }

  return { _keys: keys, ...((redactShallow(body) as object) ?? {}) };
}

@Catch()
export class HttpExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(HttpExceptionFilter.name);

  catch(exception: unknown, host: ArgumentsHost): void {
    const context = host.switchToHttp();
    const response = context.getResponse<Response>();
    const request = context.getRequest<Request>();

    const status = exception instanceof HttpException
      ? exception.getStatus()
      : HttpStatus.INTERNAL_SERVER_ERROR;

    const exceptionResponse = exception instanceof HttpException
      ? exception.getResponse()
      : { message: 'Internal server error' };

    const authorizationHeader = request.headers.authorization;
    const sanitizedAuthorization = authorizationHeader ? REDACTED : null;
    const sanitizedQuery = redactShallow(request.query);
    const sanitizedBody = summarizeRequestBody(request.url, request.body);
    const sanitizedError = redactShallow(exceptionResponse);

    this.logger.error(
      JSON.stringify({
        method: request.method,
        path: request.url,
        statusCode: status,
        authorization: sanitizedAuthorization,
        query: sanitizedQuery,
        body: sanitizedBody,
        error: sanitizedError,
      }),
    );

    response.status(status).json({
      success: false,
      statusCode: status,
      path: request.url,
      timestamp: new Date().toISOString(),
      error: exceptionResponse,
    });
  }
}