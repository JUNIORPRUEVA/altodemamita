/**
 * FASE 01D — Verificacion HTTP real de las rutas administrativas de pagos.
 *
 * Ejercita el SERVIDOR Express (no solo el servicio): autenticacion, middleware
 * OWNER, cabecera Idempotency-Key, body y resolucion de empresa por tenant.
 *
 * Requisitos:
 *   - Backend local escuchando (por defecto http://127.0.0.1:4111).
 *   - ACCEPTANCE_DATABASE_URL apuntando a la MISMA base que usa el backend.
 *
 * Crea su propio fixture (empresa + OWNER + TECH + ventas/cuotas/pagos) y lo
 * borra al final. Se niega a ejecutarse contra una URL no local.
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

const RUN = `acc-http-${Date.now()}`;
// Credenciales del fixture generadas en runtime: el repo no contiene ninguna.
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
    data: { tenantKey: RUN, name: `HTTP ${RUN}` },
  });
  const tenantKey = company.tenantKey;
  const owner = await prisma.user.create({
    data: {
      companyId: company.id,
      syncId: `${RUN}-owner`,
      email: `${RUN}-owner@acceptance.local`,
      name: "Owner HTTP",
      passwordHash: await hashPassword(OWNER_PASSWORD),
      role: "OWNER",
      localRole: "admin",
    },
  });
  const tech = await prisma.user.create({
    data: {
      companyId: company.id,
      syncId: `${RUN}-tech`,
      email: `${RUN}-tech@acceptance.local`,
      name: "Tecnico HTTP",
      passwordHash: await hashPassword(TECH_PASSWORD),
      role: "TECH",
      localRole: "vendedor",
    },
  });
  const client = await prisma.client.create({
    data: { companyId: company.id, syncId: `${RUN}-client`, name: "Cliente HTTP" },
  });

  // Venta 1: cuota pagada con DOS pagos (segundo pago activo).
  const lot1 = await prisma.lot.create({
    data: { companyId: company.id, syncId: `${RUN}-lot-1`, block: "A", number: "11", status: "vendido" },
  });
  const sale1 = await prisma.sale.create({
    data: {
      companyId: company.id,
      syncId: `${RUN}-sale-1`,
      clientId: client.id,
      lotId: lot1.id,
      clientSyncId: client.syncId,
      lotSyncId: lot1.syncId,
      saleDate: new Date("2026-08-01T00:00:00.000Z"),
      status: "pagada",
      total: 20000,
      initialRequiredAmount: 0,
      initialPaid: 0,
      initialPendingAmount: 0,
      financedBalance: 20000,
      balance: 0,
      monthlyInterestRate: 0,
      installmentCount: 1,
    },
  });
  const inst1 = await prisma.installment.create({
    data: {
      companyId: company.id,
      syncId: `${RUN}-inst-1`,
      saleId: sale1.id,
      saleSyncId: sale1.syncId,
      installmentNumber: 1,
      dueDate: new Date("2026-09-01T00:00:00.000Z"),
      openingBalance: 20000,
      principalAmount: 20000,
      interestAmount: 0,
      totalAmount: 20000,
      paidAmount: 20000,
      paidPrincipalAmount: 20000,
      paidInterestAmount: 0,
      endingBalance: 0,
      status: "pagada",
    },
  });
  const pay1 = await prisma.payment.create({
    data: {
      companyId: company.id,
      syncId: `${RUN}-pay-1`,
      saleId: sale1.id,
      clientId: client.id,
      installmentId: inst1.id,
      saleSyncId: sale1.syncId,
      installmentSyncId: inst1.syncId,
      paidAt: new Date("2026-09-02T00:00:00.000Z"),
      amount: 10000,
      method: "efectivo",
      paymentType: "cuota",
      principalApplied: 10000,
      interestApplied: 0,
      lateFeeApplied: 0,
    },
  });
  await prisma.payment.create({
    data: {
      companyId: company.id,
      syncId: `${RUN}-pay-2`,
      saleId: sale1.id,
      clientId: client.id,
      installmentId: inst1.id,
      saleSyncId: sale1.syncId,
      installmentSyncId: inst1.syncId,
      paidAt: new Date("2026-10-02T00:00:00.000Z"),
      amount: 10000,
      method: "efectivo",
      paymentType: "cuota",
      principalApplied: 10000,
      interestApplied: 0,
      lateFeeApplied: 0,
    },
  });

  // Venta 2: cuota vencida sin pagar (para condonacion de mora).
  const lot2 = await prisma.lot.create({
    data: { companyId: company.id, syncId: `${RUN}-lot-2`, block: "B", number: "12", status: "vendido" },
  });
  const sale2 = await prisma.sale.create({
    data: {
      companyId: company.id,
      syncId: `${RUN}-sale-2`,
      clientId: client.id,
      lotId: lot2.id,
      clientSyncId: client.syncId,
      lotSyncId: lot2.syncId,
      saleDate: new Date("2026-05-01T00:00:00.000Z"),
      status: "activa",
      total: 10000,
      initialRequiredAmount: 0,
      initialPaid: 0,
      initialPendingAmount: 0,
      financedBalance: 10000,
      balance: 10000,
      monthlyInterestRate: 0,
      installmentCount: 1,
    },
  });
  await prisma.installment.create({
    data: {
      companyId: company.id,
      syncId: `${RUN}-inst-2`,
      saleId: sale2.id,
      saleSyncId: sale2.syncId,
      installmentNumber: 1,
      dueDate: new Date("2026-06-01T00:00:00.000Z"),
      openingBalance: 10000,
      principalAmount: 10000,
      interestAmount: 0,
      totalAmount: 10000,
      paidAmount: 0,
      paidPrincipalAmount: 0,
      paidInterestAmount: 0,
      endingBalance: 10000,
      status: "vencida",
    },
  });

  try {
    // ── Autenticacion ─────────────────────────────────────────────────────
    const ownerLogin = await login(`${RUN}-owner@acceptance.local`, OWNER_PASSWORD);
    const techLogin = await login(`${RUN}-tech@acceptance.local`, TECH_PASSWORD);
    check(
      "login OWNER y TECH contra el backend real",
      ownerLogin.status === 200 && ownerLogin.role === "OWNER" && !!ownerLogin.token,
      `owner=${ownerLogin.status}/${ownerLogin.role} tech=${techLogin.status}/${techLogin.role}`,
    );
    const ownerToken = ownerLogin.token as string;
    const techToken = techLogin.token as string;

    const previewPath = `/authoritative/payments/${pay1.id}/correction-preview?action=annul`;

    // ── Permisos: TECH no puede previsualizar ni aplicar ───────────────────
    const techPreview = await api(previewPath, { token: techToken, tenantKey });
    check(
      "TECH recibe 403 al previsualizar una correccion",
      techPreview.status === 403 &&
        techPreview.json?.error?.code === "OWNER_ROLE_REQUIRED",
      `${techPreview.status} ${techPreview.json?.error?.code ?? ""}`,
    );
    const techApply = await api(`/authoritative/payments/${pay1.id}/correct`, {
      method: "POST",
      token: techToken,
      tenantKey,
      idempotencyKey: `${RUN}-tech-apply`,
      body: { action: "annul", reason: "intento no autorizado" },
    });
    check(
      "TECH recibe 403 al aplicar una correccion",
      techApply.status === 403,
      String(techApply.status),
    );

    // ── OWNER: preview historico permitido ────────────────────────────────
    const ownerPreview = await api(previewPath, { token: ownerToken, tenantKey });
    check(
      "OWNER previsualiza la anulacion del pago historico",
      ownerPreview.status === 200 &&
        ownerPreview.json?.data?.correction?.allowed === true,
      `${ownerPreview.status} ${ownerPreview.json?.data?.correction?.code ?? ""}`,
    );

    // ── Motivo obligatorio ────────────────────────────────────────────────
    const noReason = await api(`/authoritative/payments/${pay1.id}/correct`, {
      method: "POST",
      token: ownerToken,
      tenantKey,
      idempotencyKey: `${RUN}-no-reason`,
      body: { action: "annul", reason: "  " },
    });
    check(
      "el backend exige motivo (400 CORRECTION_REASON_REQUIRED)",
      noReason.status === 400 &&
        noReason.json?.error?.code === "CORRECTION_REASON_REQUIRED",
      `${noReason.status} ${noReason.json?.error?.code ?? ""}`,
    );

    // ── OWNER: aplicar con Idempotency-Key ────────────────────────────────
    const key = `${RUN}-apply`;
    const applied = await api(`/authoritative/payments/${pay1.id}/correct`, {
      method: "POST",
      token: ownerToken,
      tenantKey,
      idempotencyKey: key,
      body: {
        action: "annul",
        reason: "Pago historico duplicado",
        expectedPaymentVersion: 1,
      },
    });
    check(
      "OWNER aplica la anulacion (201)",
      applied.status === 201 &&
        applied.json?.data?.correction?.action === "annul",
      `${applied.status}`,
    );
    const replay = await api(`/authoritative/payments/${pay1.id}/correct`, {
      method: "POST",
      token: ownerToken,
      tenantKey,
      idempotencyKey: key,
      body: {
        action: "annul",
        reason: "Pago historico duplicado",
        expectedPaymentVersion: 1,
      },
    });
    check(
      "reintento con la misma Idempotency-Key es idempotente (200)",
      replay.status === 200 && replay.json?.idempotentReplay === true,
      `${replay.status} replayed=${replay.json?.idempotentReplay}`,
    );

    const pay1After = await prisma.payment.findUnique({ where: { id: pay1.id } });
    const inst1After = await prisma.installment.findUnique({ where: { id: inst1.id } });
    const sale1After = await prisma.sale.findUnique({ where: { id: sale1.id } });
    check(
      "la anulacion revierte la cuota y el saldo reales",
      !!pay1After?.annulledAt &&
        Number(inst1After?.paidAmount) === 10000 &&
        Number(sale1After?.balance) === 10000,
      `cuota=${inst1After?.paidAmount} saldo=${sale1After?.balance}`,
    );

    // ── IDOR por tenant: otra empresa no ve el pago ───────────────────────
    const idor = await api(previewPath, {
      token: ownerToken,
      tenantKey: `${RUN}-otra`,
    });
    check(
      "otra empresa no puede previsualizar el pago (404)",
      idor.status === 404,
      String(idor.status),
    );

    // ── Auditoria de solo lectura ─────────────────────────────────────────
    const history = await api(
      `/authoritative/payments/${pay1.id}/correction-history`,
      { token: ownerToken, tenantKey },
    );
    const entries = Array.isArray(history.json?.data?.history)
      ? history.json.data.history
      : [];
    check(
      "la auditoria HTTP devuelve la traza del pago",
      history.status === 200 &&
        entries.some((e: any) => e.kind === "annulment") &&
        entries.some((e: any) => e.kind === "authoritative_operation"),
      `${history.status} eventos=${entries.length}`,
    );

    // ── Condonacion PARCIAL de mora por HTTP ──────────────────────────────
    const summary = await api(
      `/authoritative/sales/${sale2.id}/late-fee-summary`,
      { token: ownerToken, tenantKey },
    );
    const outstanding = Number(summary.json?.data?.outstandingLateFees ?? 0);
    if (outstanding <= 0) {
      check("mora disponible para condonacion parcial", false, "mora=0");
    } else {
      const partial = Math.round((outstanding / 2) * 100) / 100;
      const waiver = await api(
        `/authoritative/sales/${sale2.id}/late-fee-waiver`,
        {
          method: "POST",
          token: ownerToken,
          tenantKey,
          idempotencyKey: `${RUN}-waive`,
          body: {
            cutoffAt: new Date().toISOString(),
            confirmSaleSyncId: sale2.syncId,
            reason: "Condonacion parcial via HTTP",
            waivedAmount: partial,
          },
        },
      );
      check(
        "OWNER condona PARCIALMENTE la mora (201)",
        waiver.status === 201 &&
          Number(waiver.json?.data?.waivedAmount) === partial &&
          waiver.json?.data?.isPartial === true,
        `${waiver.status} waived=${waiver.json?.data?.waivedAmount}`,
      );
      const summaryAfter = await api(
        `/authoritative/sales/${sale2.id}/late-fee-summary`,
        { token: ownerToken, tenantKey },
      );
      const remaining = Number(
        summaryAfter.json?.data?.outstandingLateFees ?? -1,
      );
      check(
        "la mora exigible baja exactamente lo condonado por HTTP",
        Math.abs(remaining - (outstanding - partial)) < 0.02,
        `antes=${outstanding} despues=${remaining}`,
      );
      const techWaiver = await api(
        `/authoritative/sales/${sale2.id}/late-fee-waiver`,
        {
          method: "POST",
          token: techToken,
          tenantKey,
          idempotencyKey: `${RUN}-waive-tech`,
          body: {
            cutoffAt: new Date().toISOString(),
            confirmSaleSyncId: sale2.syncId,
            reason: "intento no autorizado",
            waivedAmount: 1,
          },
        },
      );
      check(
        "TECH recibe 403 al condonar mora",
        techWaiver.status === 403,
        String(techWaiver.status),
      );
    }

    // ═══ FASE 02 — Gestion OWNER del cronograma por HTTP ══════════════════
    const lot3 = await prisma.lot.create({
      data: { companyId: company.id, syncId: `${RUN}-lot-3`, block: "E", number: "13", status: "vendido" },
    });
    const sale3 = await prisma.sale.create({
      data: {
        companyId: company.id,
        syncId: `${RUN}-sale-3`,
        clientId: client.id,
        lotId: lot3.id,
        clientSyncId: client.syncId,
        lotSyncId: lot3.syncId,
        saleDate: new Date("2026-08-01T00:00:00.000Z"),
        status: "activa",
        total: 20000,
        initialRequiredAmount: 0,
        initialPaid: 0,
        initialPendingAmount: 0,
        financedBalance: 20000,
        balance: 20000,
        monthlyInterestRate: 0,
        installmentCount: 2,
      },
    });
    const inst3a = await prisma.installment.create({
      data: {
        companyId: company.id,
        syncId: `${RUN}-inst-3a`,
        saleId: sale3.id,
        saleSyncId: sale3.syncId,
        installmentNumber: 1,
        dueDate: new Date("2026-09-01T00:00:00.000Z"),
        openingBalance: 20000,
        principalAmount: 10000,
        interestAmount: 0,
        totalAmount: 10000,
        paidAmount: 0,
        paidPrincipalAmount: 0,
        paidInterestAmount: 0,
        endingBalance: 10000,
        status: "pendiente",
      },
    });
    await prisma.installment.create({
      data: {
        companyId: company.id,
        syncId: `${RUN}-inst-3b`,
        saleId: sale3.id,
        saleSyncId: sale3.syncId,
        installmentNumber: 2,
        dueDate: new Date("2026-10-01T00:00:00.000Z"),
        openingBalance: 10000,
        principalAmount: 10000,
        interestAmount: 0,
        totalAmount: 10000,
        paidAmount: 0,
        paidPrincipalAmount: 0,
        paidInterestAmount: 0,
        endingBalance: 0,
        status: "pendiente",
      },
    });

    const previewPath3 =
      `/authoritative/sales/${sale3.id}/installment-corrections/preview` +
      `?action=change_due_date&installmentId=${inst3a.id}&dueDate=2026-09-20T00:00:00.000Z`;

    const techInstallmentPreview = await api(previewPath3, {
      token: techToken,
      tenantKey,
    });
    check(
      "TECH recibe 403 al previsualizar la correccion de cronograma",
      techInstallmentPreview.status === 403,
      String(techInstallmentPreview.status),
    );

    const ownerInstallmentPreview = await api(previewPath3, {
      token: ownerToken,
      tenantKey,
    });
    check(
      "OWNER previsualiza el cambio de vencimiento",
      ownerInstallmentPreview.status === 200 &&
        ownerInstallmentPreview.json?.data?.impact?.principalPreserved === true,
      `${ownerInstallmentPreview.status}`,
    );

    const installmentKey = `${RUN}-inst-apply`;
    const installmentApply = await api(
      `/authoritative/sales/${sale3.id}/installment-corrections`,
      {
        method: "POST",
        token: ownerToken,
        tenantKey,
        idempotencyKey: installmentKey,
        body: {
          action: "change_due_date",
          installmentId: inst3a.id,
          dueDate: "2026-09-20T00:00:00.000Z",
          reason: "Vencimiento mal capturado",
          expectedSaleVersion: sale3.version,
        },
      },
    );
    check(
      "OWNER aplica la correccion de cronograma (201)",
      installmentApply.status === 201,
      `${installmentApply.status} ${JSON.stringify(installmentApply.json?.error ?? {})}`,
    );
    const installmentReplay = await api(
      `/authoritative/sales/${sale3.id}/installment-corrections`,
      {
        method: "POST",
        token: ownerToken,
        tenantKey,
        idempotencyKey: installmentKey,
        body: {
          action: "change_due_date",
          installmentId: inst3a.id,
          dueDate: "2026-09-20T00:00:00.000Z",
          reason: "Vencimiento mal capturado",
          expectedSaleVersion: sale3.version,
        },
      },
    );
    check(
      "reintento de cronograma es idempotente (200)",
      installmentReplay.status === 200 &&
        installmentReplay.json?.idempotentReplay === true,
      `${installmentReplay.status}`,
    );

    const installmentAudit = await api(
      `/authoritative/sales/${sale3.id}/installment-corrections/audit`,
      { token: ownerToken, tenantKey },
    );
    const installmentEntries = Array.isArray(
      installmentAudit.json?.data?.history,
    )
      ? installmentAudit.json.data.history
      : [];
    check(
      "la auditoria de cronograma devuelve la traza",
      installmentAudit.status === 200 && installmentEntries.length >= 2,
      `${installmentAudit.status} eventos=${installmentEntries.length}`,
    );
  } finally {
    // El backend crea (upsert) una empresa al recibir un tenant desconocido; la
    // prueba de IDOR genera `${RUN}-otra`, que tambien debe eliminarse.
    const stray = await prisma.company.findUnique({
      where: { tenantKey: `${RUN}-otra` },
      select: { id: true },
    });
    const ids = [company.id, ...(stray ? [stray.id] : [])];
    await prisma.authoritativeOperation.deleteMany({ where: { companyId: { in: ids } } });
    await prisma.lateFeeWaiver.deleteMany({ where: { companyId: { in: ids } } });
    await prisma.lateFeeSnapshot.deleteMany({ where: { companyId: { in: ids } } });
    await prisma.payment.deleteMany({ where: { companyId: { in: ids } } });
    await prisma.installment.deleteMany({ where: { companyId: { in: ids } } });
    await prisma.sale.deleteMany({ where: { companyId: { in: ids } } });
    await prisma.lot.deleteMany({ where: { companyId: { in: ids } } });
    await prisma.client.deleteMany({ where: { companyId: { in: ids } } });
    await prisma.user.deleteMany({ where: { companyId: { in: ids } } });
    await prisma.company.deleteMany({ where: { id: { in: ids } } });
  }

  const failed = results.filter((r) => !r.ok);
  console.log(`\nRESULTADO HTTP: ${results.length - failed.length}/${results.length} PASS`);
  if (failed.length > 0) {
    for (const f of failed) console.log(` - ${f.name} ${f.detail}`);
    process.exitCode = 1;
  }
  void owner;
  void tech;
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
