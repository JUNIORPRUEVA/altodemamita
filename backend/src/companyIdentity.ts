import { Request } from 'express';
import { prisma } from './prisma';
import { config } from './config';

export function requestedTenantKey(req: Request) {
  const header =
    req.header('x-company-tenant-key') ??
    req.header('x-tenant-key') ??
    req.header('x-cloud-company-id');
  const body = req.body as Record<string, unknown> | undefined;
  const query = req.query as Record<string, unknown>;
  return (
    stringValue(header) ??
    stringValue(body?.companyTenantKey) ??
    stringValue(body?.company_tenant_key) ??
    stringValue(body?.companyCloudId) ??
    stringValue(body?.company_cloud_id) ??
    stringValue(query.companyTenantKey) ??
    stringValue(query.company_tenant_key) ??
    config.companyTenantKey
  ).toLowerCase();
}

export async function resolveCompanyForRequest(req: Request) {
  return resolveCompanyByTenantKey(requestedTenantKey(req));
}

export async function resolveCompanyByTenantKey(tenantKey: string) {
  const normalized = (tenantKey || config.companyTenantKey).trim().toLowerCase();
  return prisma.company.upsert({
    where: { tenantKey: normalized },
    update: { active: true },
    create: {
      tenantKey: normalized,
      name: config.companyName,
      active: true,
    },
  });
}

function stringValue(value: unknown) {
  const text = String(value ?? '').trim();
  return text.length === 0 ? null : text;
}
