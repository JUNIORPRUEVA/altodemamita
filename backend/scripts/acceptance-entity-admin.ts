/**
 * FASE 04 — E2E de la administracion OWNER de clientes y solares.
 *
 * Verifica guardas de integridad, fusion de duplicados con conservacion de
 * ventas/pagos, desactivacion/reactivacion logica y aislamiento por empresa.
 */
import { PrismaClient } from "@prisma/client";
import { EntityAdminService } from "../src/services/entityAdmin.service";

const url = process.env.ACCEPTANCE_DATABASE_URL ?? "";
if (!url) {
  console.error("Falta ACCEPTANCE_DATABASE_URL.");
  process.exit(2);
}
if (!/(127\.0\.0\.1|localhost)/.test(url)) {
  console.error("Rechazado: solo Acceptance local.");
  process.exit(2);
}

const prisma = new PrismaClient({ datasources: { db: { url } } });
const admin = new EntityAdminService(prisma);
const RUN = `acc-ent-${Date.now()}`;
const results: { name: string; ok: boolean; detail: string }[] = [];

function check(name: string, ok: boolean, detail = "") {
  results.push({ name, ok, detail });
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? ` — ${detail}` : ""}`);
}

async function errorCode(promise: Promise<unknown>) {
  try {
    await promise;
    return "";
  } catch (error: any) {
    return String(error?.code ?? "");
  }
}

async function main() {
  const company = await prisma.company.create({
    data: { tenantKey: RUN, name: `Entidades ${RUN}` },
  });
  const otherCompany = await prisma.company.create({
    data: { tenantKey: `${RUN}-otra`, name: "Otra" },
  });
  const owner = await prisma.user.create({
    data: {
      companyId: company.id,
      syncId: `${RUN}-owner`,
      email: `${RUN}-owner@acceptance.local`,
      name: "Owner Entidades",
      passwordHash: "not-used",
      role: "OWNER",
    },
  });
  const client = await prisma.client.create({
    data: {
      companyId: company.id,
      syncId: `${RUN}-client`,
      name: "Cliente Original",
      document: "001-0000001-1",
      phone: "8090000000",
    },
  });
  const duplicate = await prisma.client.create({
    data: {
      companyId: company.id,
      syncId: `${RUN}-client-dup`,
      name: "Cliente Duplicado",
      document: "001-0000002-2",
    },
  });
  const lot = await prisma.lot.create({
    data: {
      companyId: company.id,
      syncId: `${RUN}-lot`,
      block: "A",
      number: "01",
      area: 120,
      price: 500000,
      status: "vendido",
    },
  });
  const freeLot = await prisma.lot.create({
    data: {
      companyId: company.id,
      syncId: `${RUN}-lot-free`,
      block: "A",
      number: "02",
      area: 130,
      price: 520000,
      status: "disponible",
    },
  });
  const sale = await prisma.sale.create({
    data: {
      companyId: company.id,
      syncId: `${RUN}-sale`,
      clientId: duplicate.id,
      clientSyncId: duplicate.syncId,
      lotId: lot.id,
      lotSyncId: lot.syncId,
      saleDate: new Date("2026-08-01T00:00:00.000Z"),
      status: "activa",
      total: 500000,
      initialRequiredAmount: 50000,
      initialPaid: 50000,
      initialPendingAmount: 0,
      financedBalance: 450000,
      balance: 450000,
      monthlyInterestRate: 1,
      installmentCount: 12,
    },
  });
  const payment = await prisma.payment.create({
    data: {
      companyId: company.id,
      syncId: `${RUN}-pay`,
      saleId: sale.id,
      clientId: duplicate.id,
      clientSyncId: duplicate.syncId,
      saleSyncId: sale.syncId,
      paidAt: new Date("2026-08-01T00:00:00.000Z"),
      amount: 50000,
      method: "efectivo",
      paymentType: "abono_inicial",
      principalApplied: 0,
      interestApplied: 0,
      lateFeeApplied: 0,
    },
  });

  try {
    // ── Clientes: identidad ───────────────────────────────────────────────
    await admin.apply({
      companyId: company.id,
      kind: "client",
      entityId: client.id,
      action: "update_identity",
      name: "Cliente Corregido",
      document: "001-0000001-1",
      phone: "8091112222",
      address: "Calle 1",
      reason: "Datos de contacto corregidos",
      performedByUserId: owner.id,
      idempotencyKey: `${RUN}-client-update`,
    });
    const clientAfter = await prisma.client.findUnique({ where: { id: client.id } });
    check(
      "actualiza la identidad del cliente",
      clientAfter?.name === "Cliente Corregido" &&
        clientAfter?.phone === "8091112222",
      `${clientAfter?.name}/${clientAfter?.phone}`,
    );

    const docCode = await errorCode(
      admin.apply({
        companyId: company.id,
        kind: "client",
        entityId: duplicate.id,
        action: "update_identity",
        name: "Cliente Duplicado",
        document: "001-0000001-1",
        reason: "documento repetido",
        performedByUserId: owner.id,
        idempotencyKey: `${RUN}-client-doc`,
      }),
    );
    check(
      "rechaza una cedula duplicada (409)",
      docCode === "CLIENT_DOCUMENT_TAKEN",
      docCode,
    );

    const deactivateCode = await errorCode(
      admin.apply({
        companyId: company.id,
        kind: "client",
        entityId: duplicate.id,
        action: "deactivate",
        reason: "intento con venta activa",
        performedByUserId: owner.id,
        idempotencyKey: `${RUN}-client-deact`,
      }),
    );
    check(
      "no desactiva un cliente con venta activa (409)",
      deactivateCode === "CLIENT_HAS_ACTIVE_SALES",
      deactivateCode,
    );

    // ── Clientes: fusión de duplicados ────────────────────────────────────
    await admin.apply({
      companyId: company.id,
      kind: "client",
      entityId: client.id,
      action: "merge_duplicates",
      mergeSourceId: duplicate.id,
      reason: "Cliente duplicado fusionado",
      performedByUserId: owner.id,
      idempotencyKey: `${RUN}-merge`,
    });
    const saleAfterMerge = await prisma.sale.findUnique({ where: { id: sale.id } });
    const paymentAfterMerge = await prisma.payment.findUnique({
      where: { id: payment.id },
    });
    const sourceAfterMerge = await prisma.client.findUnique({
      where: { id: duplicate.id },
    });
    check(
      "la fusion reapunta ventas y pagos al cliente destino",
      saleAfterMerge?.clientId === client.id &&
        paymentAfterMerge?.clientId === client.id,
      `venta=${saleAfterMerge?.clientId === client.id} pago=${paymentAfterMerge?.clientId === client.id}`,
    );
    check(
      "el duplicado se conserva como historico (borrado logico)",
      sourceAfterMerge?.deletedAt !== null &&
        (sourceAfterMerge?.raw as any)?.mergedIntoClientId === client.id,
      String(sourceAfterMerge?.deletedAt?.toISOString()),
    );
    check(
      "los pagos y sus montos no se alteran",
      Number(paymentAfterMerge?.amount) === 50000 &&
        paymentAfterMerge?.annulledAt === null,
    );

    const reactivateCode = await errorCode(
      admin.apply({
        companyId: company.id,
        kind: "client",
        entityId: duplicate.id,
        action: "reactivate",
        reason: "intento de reactivar fusionado con cedula libre",
        performedByUserId: owner.id,
        idempotencyKey: `${RUN}-client-react`,
      }),
    );
    check(
      "reactivar un cliente fusionado sin ventas activas es posible",
      reactivateCode === "",
      reactivateCode,
    );
    await admin.apply({
      companyId: company.id,
      kind: "client",
      entityId: duplicate.id,
      action: "deactivate",
      reason: "se vuelve a desactivar el duplicado",
      performedByUserId: owner.id,
      idempotencyKey: `${RUN}-client-deact2`,
    });

    // ── Solares: datos y guardas ──────────────────────────────────────────
    await admin.apply({
      companyId: company.id,
      kind: "lot",
      entityId: freeLot.id,
      action: "update_details",
      block: "B",
      number: "07",
      area: 140,
      price: 560000,
      reason: "Datos del solar corregidos",
      performedByUserId: owner.id,
      idempotencyKey: `${RUN}-lot-update`,
    });
    const freeLotAfter = await prisma.lot.findUnique({ where: { id: freeLot.id } });
    check(
      "actualiza bloque, numero, area y precio",
      freeLotAfter?.block === "B" &&
        freeLotAfter?.number === "07" &&
        Number(freeLotAfter?.area) === 140 &&
        Number(freeLotAfter?.price) === 560000,
      `${freeLotAfter?.block}-${freeLotAfter?.number}`,
    );

    const dupLotCode = await errorCode(
      admin.apply({
        companyId: company.id,
        kind: "lot",
        entityId: freeLot.id,
        action: "update_details",
        block: "A",
        number: "01",
        reason: "identificador duplicado",
        performedByUserId: owner.id,
        idempotencyKey: `${RUN}-lot-dup`,
      }),
    );
    check(
      "rechaza un bloque+numero ya usado por otro solar activo (409)",
      dupLotCode === "LOT_IDENTIFIER_TAKEN",
      dupLotCode,
    );

    const soldCode = await errorCode(
      admin.apply({
        companyId: company.id,
        kind: "lot",
        entityId: freeLot.id,
        action: "update_status",
        status: "vendido",
        reason: "intento de marcar vendido a mano",
        performedByUserId: owner.id,
        idempotencyKey: `${RUN}-lot-sold`,
      }),
    );
    check(
      "no se puede fijar 'vendido' manualmente (409)",
      soldCode === "LOT_SOLD_STATUS_MANUAL",
      soldCode,
    );

    const availableCode = await errorCode(
      admin.apply({
        companyId: company.id,
        kind: "lot",
        entityId: lot.id,
        action: "update_status",
        status: "disponible",
        reason: "intento de liberar con venta activa",
        performedByUserId: owner.id,
        idempotencyKey: `${RUN}-lot-available`,
      }),
    );
    check(
      "no se libera un solar con venta activa (409)",
      availableCode === "LOT_HAS_ACTIVE_SALE",
      availableCode,
    );

    const lotDeactivateCode = await errorCode(
      admin.apply({
        companyId: company.id,
        kind: "lot",
        entityId: lot.id,
        action: "deactivate",
        reason: "intento de desactivar con venta activa",
        performedByUserId: owner.id,
        idempotencyKey: `${RUN}-lot-deact-busy`,
      }),
    );
    check(
      "no se desactiva un solar con venta activa (409)",
      lotDeactivateCode === "LOT_HAS_ACTIVE_SALE",
      lotDeactivateCode,
    );

    await admin.apply({
      companyId: company.id,
      kind: "lot",
      entityId: freeLot.id,
      action: "deactivate",
      reason: "Solar retirado del listado",
      performedByUserId: owner.id,
      idempotencyKey: `${RUN}-lot-deact`,
    });
    const deactivatedLot = await prisma.lot.findUnique({ where: { id: freeLot.id } });
    check(
      "desactiva logicamente el solar conservando su historia",
      deactivatedLot?.deletedAt !== null && deactivatedLot?.status === "inactivo",
      `${deactivatedLot?.status}/${deactivatedLot?.deletedAt?.toISOString() ?? null}`,
    );

    await admin.apply({
      companyId: company.id,
      kind: "lot",
      entityId: freeLot.id,
      action: "reactivate",
      reason: "Solar vuelve al inventario",
      performedByUserId: owner.id,
      idempotencyKey: `${RUN}-lot-react`,
    });
    const reactivatedLot = await prisma.lot.findUnique({ where: { id: freeLot.id } });
    check(
      "reactiva el solar como disponible",
      reactivatedLot?.deletedAt === null && reactivatedLot?.status === "disponible",
      String(reactivatedLot?.status),
    );

    // ── Seguridad y auditoría ─────────────────────────────────────────────
    const crossCode = await errorCode(
      admin.preview({
        companyId: otherCompany.id,
        kind: "client",
        entityId: client.id,
        action: "deactivate",
      }),
    );
    check(
      "otra empresa no ve el cliente (404)",
      crossCode === "CLIENT_NOT_FOUND",
      crossCode,
    );

    const reasonCode = await errorCode(
      admin.apply({
        companyId: company.id,
        kind: "lot",
        entityId: freeLot.id,
        action: "update_details",
        area: 100,
        reason: "   ",
        performedByUserId: owner.id,
        idempotencyKey: `${RUN}-no-reason`,
      }),
    );
    check("exige motivo", reasonCode === "CORRECTION_REASON_REQUIRED", reasonCode);

    const versionCode = await errorCode(
      admin.apply({
        companyId: company.id,
        kind: "lot",
        entityId: freeLot.id,
        action: "update_details",
        area: 100,
        reason: "version obsoleta",
        performedByUserId: owner.id,
        idempotencyKey: `${RUN}-version`,
        expectedVersion: 999,
      }),
    );
    check("version obsoleta (409)", versionCode === "ENTITY_VERSION_CONFLICT", versionCode);

    const clientAudit = (await admin.history({
      companyId: company.id,
      kind: "client",
      entityId: client.id,
    })) as any;
    const lotAudit = (await admin.history({
      companyId: company.id,
      kind: "lot",
      entityId: freeLot.id,
    })) as any;
    check(
      "la auditoria registra cambios de cliente y de solar",
      Array.isArray(clientAudit?.history) &&
        clientAudit.history.some((entry: any) => entry.action === "merge_duplicates") &&
        Array.isArray(lotAudit?.history) &&
        lotAudit.history.some((entry: any) => entry.action === "update_details"),
      `cliente=${clientAudit?.history?.length} solar=${lotAudit?.history?.length}`,
    );
  } finally {
    const ids = [company.id, otherCompany.id];
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
  console.log(`\nRESULTADO: ${results.length - failed.length}/${results.length} PASS`);
  if (failed.length > 0) {
    for (const f of failed) console.log(` - ${f.name} ${f.detail}`);
    process.exitCode = 1;
  }
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
