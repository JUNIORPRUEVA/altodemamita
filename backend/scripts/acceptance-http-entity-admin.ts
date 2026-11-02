/**
 * FASE 05 — Verificacion HTTP real de las rutas administrativas de CLIENTES y SOLARES.
 *
 * Complementa `acceptance-entity-admin.ts` (que ejercita el servicio) y
 * `acceptance-http-correction.ts` (que ejercita pagos, mora y ventas).
 *
 * Aqui se comprueba lo que solo puede verse por HTTP:
 *   - el middleware OWNER (`requireOwnerRole`) rechaza a un usuario TECH
 *     con 403 en previsualizacion, aplicacion y auditoria;
 *   - un TECH no puede saltarse la restriccion enviando el POST directamente
 *     (y el cliente queda intacto cuando lo intenta);
 *   - el OWNER si puede previsualizar, aplicar y leer la auditoria;
 *   - otra empresa no ve la entidad (404);
 *   - el motivo es obligatorio (400 CORRECTION_REASON_REQUIRED).
 *
 * Requisitos:
 *   - Backend local escuchando (por defecto http://127.0.0.1:4111).
 *   - ACCEPTANCE_DATABASE_URL apuntando a la MISMA base que usa el backend.
 *
 * Crea su propio fixture (empresa + OWNER + TECH + cliente + solar) y lo borra
 * al terminar. Se niega a ejecutarse contra una URL no local.
 */
import { randomUUID } from "node:crypto";
import { PrismaClient } from "@prisma/client";
import { hashPassword } from "../src/password";

const dbUrl = process.env.ACCEPTANCE_DATABASE_URL ?? "";
if (!dbUrl) {
  console.error("Falta ACCEPTANCE_DATABASE_URL.");
  process.exit(2);
}
if (!/(127\.0\.0\.1|localhost)/.test(dbUrl)) {
  console.error("Rechazado: solo Acceptance local.");
  process.exit(2);
}
const BASE = process.env.ACCEPTANCE_API_URL ?? "http://127.0.0.1:4111";

const prisma = new PrismaClient({ datasources: { db: { url: dbUrl } } });

const RUN = `acc-http-entity-${Date.now()}`;
const OWNER_PASSWORD = `Owner-${randomUUID()}`;
const TECH_PASSWORD = `Tech-${randomUUID()}`;
const results: { name: string; ok: boolean; detail: string }[] = [];

function check(name: string, ok: boolean, detail = "") {
  results.push({ name, ok, detail });
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? ` — ${detail}` : ""}`);
}

async function api(
  path: string,
  options: {
    method?: string;
    token?: string;
    tenantKey?: string;
    body?: unknown;
    idempotencyKey?: string;
  } = {},
) {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    ...(options.token ? { Authorization: `Bearer ${options.token}` } : {}),
    ...(options.tenantKey ? { "x-tenant-key": options.tenantKey } : {}),
    ...(options.idempotencyKey
      ? { "Idempotency-Key": options.idempotencyKey }
      : {}),
  };
  const response = await fetch(`${BASE}${path}`, {
    method: options.method ?? "GET",
    headers,
    ...(options.body ? { body: JSON.stringify(options.body) } : {}),
  });
  const text = await response.text();
  let json: any = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    json = null;
  }
  return { status: response.status, json, text };
}

async function login(email: string, password: string) {
  const response = await api("/auth/login", {
    method: "POST",
    body: { email, password },
  });
  return {
    status: response.status,
    token: response.json?.data?.accessToken ?? response.json?.accessToken,
    role: response.json?.data?.user?.role,
  };
}

async function main() {
  const company = await prisma.company.create({
    data: { tenantKey: RUN, name: `HTTP ENTITY ${RUN}` },
  });
  const otherCompany = await prisma.company.create({
    data: { tenantKey: `${RUN}-otra`, name: `Otra ${RUN}` },
  });
  const tenantKey = company.tenantKey;

  await prisma.user.create({
    data: {
      companyId: company.id,
      syncId: `${RUN}-owner`,
      email: `${RUN}-owner@acceptance.local`,
      name: "Owner Entidad",
      passwordHash: await hashPassword(OWNER_PASSWORD),
      role: "OWNER",
      localRole: "admin",
    },
  });
  await prisma.user.create({
    data: {
      companyId: company.id,
      syncId: `${RUN}-tech`,
      email: `${RUN}-tech@acceptance.local`,
      name: "Tecnico Entidad",
      passwordHash: await hashPassword(TECH_PASSWORD),
      role: "TECH",
      localRole: "vendedor",
    },
  });

  await prisma.user.create({
    data: {
      companyId: otherCompany.id,
      syncId: `${RUN}-otra-owner`,
      email: `${RUN}-otra-owner@acceptance.local`,
      name: "Owner Otra",
      passwordHash: await hashPassword(OWNER_PASSWORD),
      role: "OWNER",
      localRole: "admin",
    },
  });

  const client = await prisma.client.create({
    data: {
      companyId: company.id,
      syncId: `${RUN}-client`,
      name: "Cliente Original",
      document: "00100000001",
      phone: "8090000001",
    },
  });
  const lot = await prisma.lot.create({
    data: {
      companyId: company.id,
      syncId: `${RUN}-lot`,
      block: "Z",
      number: "99",
      status: "disponible",
    },
  });

  const ownerLogin = await login(`${RUN}-owner@acceptance.local`, OWNER_PASSWORD);
  const techLogin = await login(`${RUN}-tech@acceptance.local`, TECH_PASSWORD);
  check(
    "login OWNER y TECH contra el backend real",
    ownerLogin.status === 200 &&
      techLogin.status === 200 &&
      ownerLogin.role === "OWNER" &&
      techLogin.role === "TECH",
    `owner=${ownerLogin.status}/${ownerLogin.role} tech=${techLogin.status}/${techLogin.role}`,
  );
  const ownerToken = ownerLogin.token;
  const techToken = techLogin.token;

  for (const kind of ["clients", "lots"] as const) {
    const entityId = kind === "clients" ? client.id : lot.id;

    const techPreview = await api(
      `/authoritative/${kind}/${entityId}/admin-preview?action=update_identity`,
      { token: techToken, tenantKey },
    );
    check(
      `TECH recibe 403 al previsualizar ${kind}`,
      techPreview.status === 403 &&
        techPreview.json?.error?.code === "OWNER_ROLE_REQUIRED",
      `${techPreview.status} ${techPreview.json?.error?.code ?? ""}`,
    );

    const techAudit = await api(
      `/authoritative/${kind}/${entityId}/admin-audit`,
      { token: techToken, tenantKey },
    );
    check(
      `TECH recibe 403 al leer la auditoria de ${kind}`,
      techAudit.status === 403,
      `${techAudit.status}`,
    );
  }

  // Intento de saltarse la UI: POST directo con un usuario TECH.
  const techApply = await api(`/authoritative/clients/${client.id}/admin`, {
    method: "POST",
    token: techToken,
    tenantKey,
    idempotencyKey: `${RUN}-tech-apply`,
    body: {
      action: "update_identity",
      name: "Nombre Cambiado Por Tech",
      reason: "intento no autorizado",
    },
  });
  const clientAfterTech = await prisma.client.findUnique({
    where: { id: client.id },
    select: { name: true },
  });
  check(
    "TECH recibe 403 al aplicar un cambio directo por HTTP",
    techApply.status === 403,
    `${techApply.status} ${techApply.json?.error?.code ?? ""}`,
  );
  check(
    "el cliente NO cambia tras el intento del TECH",
    clientAfterTech?.name === "Cliente Original",
    `nombre=${clientAfterTech?.name}`,
  );

  const ownerPreview = await api(
    `/authoritative/clients/${client.id}/admin-preview?action=update_identity&name=Cliente%20Corregido&phone=8091112222`,
    { token: ownerToken, tenantKey },
  );
  check(
    "OWNER previsualiza el cambio de cliente (200)",
    ownerPreview.status === 200,
    `${ownerPreview.status}`,
  );

  const ownerApply = await api(`/authoritative/clients/${client.id}/admin`, {
    method: "POST",
    token: ownerToken,
    tenantKey,
    idempotencyKey: `${RUN}-owner-apply`,
    body: {
      action: "update_identity",
      name: "Cliente Corregido",
      phone: "8091112222",
      reason: "correccion de datos en aceptacion",
    },
  });
  check(
    "OWNER aplica el cambio de cliente (201)",
    ownerApply.status === 201,
    `${ownerApply.status}`,
  );

  const replay = await api(`/authoritative/clients/${client.id}/admin`, {
    method: "POST",
    token: ownerToken,
    tenantKey,
    idempotencyKey: `${RUN}-owner-apply`,
    body: {
      action: "update_identity",
      name: "Cliente Corregido",
      phone: "8091112222",
      reason: "correccion de datos en aceptacion",
    },
  });
  check(
    "el reintento con la misma Idempotency-Key es idempotente",
    replay.status === 200 && replay.json?.idempotentReplay === true,
    `${replay.status} replayed=${replay.json?.idempotentReplay}`,
  );

  const missingReason = await api(`/authoritative/lots/${lot.id}/admin`, {
    method: "POST",
    token: ownerToken,
    tenantKey,
    idempotencyKey: `${RUN}-owner-no-reason`,
    body: { action: "update_details", block: "Z", number: "98", reason: "" },
  });
  check(
    "el motivo sigue siendo obligatorio (400 CORRECTION_REASON_REQUIRED)",
    missingReason.status === 400 &&
      missingReason.json?.error?.code === "CORRECTION_REASON_REQUIRED",
    `${missingReason.status} ${missingReason.json?.error?.code ?? ""}`,
  );

  const ownerLotApply = await api(`/authoritative/lots/${lot.id}/admin`, {
    method: "POST",
    token: ownerToken,
    tenantKey,
    idempotencyKey: `${RUN}-owner-lot`,
    body: {
      action: "update_details",
      block: "Z",
      number: "98",
      area: 150,
      price: 5000,
      reason: "ajuste de solar en aceptacion",
    },
  });
  check(
    "OWNER aplica el cambio de solar (201)",
    ownerLotApply.status === 201,
    `${ownerLotApply.status}`,
  );

  const ownerAudit = await api(`/authoritative/clients/${client.id}/admin-audit`, {
    token: ownerToken,
    tenantKey,
  });
  const auditEntries = ownerAudit.json?.data?.history;
  check(
    "OWNER lee la auditoria del cliente",
    ownerAudit.status === 200 &&
      Array.isArray(auditEntries) &&
      auditEntries.length >= 2,
    `${ownerAudit.status} eventos=${Array.isArray(auditEntries) ? auditEntries.length : "n/d"}`,
  );

  const otherOwnerLogin = await login(
    `${RUN}-otra-owner@acceptance.local`,
    OWNER_PASSWORD,
  );
  const crossCompany = await api(
    `/authoritative/clients/${client.id}/admin-preview?action=update_identity`,
    { token: otherOwnerLogin.token, tenantKey: otherCompany.tenantKey },
  );
  check(
    "un OWNER de otra empresa no ve el cliente (404)",
    crossCompany.status === 404,
    `${crossCompany.status} ${crossCompany.json?.error?.code ?? ""}`,
  );

  // Limpieza del fixture completo (solo la empresa creada por esta prueba).
  // La auditoria de estas correcciones vive en `raw.corrections` de la entidad
  // y en `AuthoritativeOperation`; no hay tabla AuditLog en este esquema.
  await prisma.authoritativeOperation.deleteMany({
    where: { companyId: company.id },
  });
  await prisma.lot.deleteMany({ where: { companyId: company.id } });
  await prisma.client.deleteMany({ where: { companyId: company.id } });
  await prisma.user.deleteMany({ where: { companyId: company.id } });
  await prisma.company.deleteMany({
    where: { id: { in: [company.id, otherCompany.id] } },
  });

  const failed = results.filter((result) => !result.ok);
  console.log("");
  for (const failure of failed) {
    console.log(`FALLO: ${failure.name} — ${failure.detail}`);
  }
  console.log(
    `RESULTADO HTTP ENTIDADES: ${results.length - failed.length}/${results.length} PASS`,
  );

  await prisma.$disconnect();
  process.exit(failed.length === 0 ? 0 : 1);
}

main().catch(async (error) => {
  console.error(error);
  await prisma.$disconnect();
  process.exit(1);
});
