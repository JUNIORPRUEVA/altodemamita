/**
 * FASE 02 — Prueba END-TO-END de la gestion OWNER de cuotas contra PostgreSQL.
 *
 * Crea un fixture aislado (empresa/cliente/solar/venta con 4 cuotas: la primera
 * pagada y tres abiertas), ejercita preview/apply de TODAS las acciones y
 * verifica las invariantes financieras:
 *
 *  I1. `Sale.balance` == capital pendiente de las cuotas activas.
 *  I2. Una cuota con pagos NUNCA se edita ni se elimina.
 *  I3. El capital total del contrato no cambia al editar cuotas.
 *
 * Uso: $env:ACCEPTANCE_DATABASE_URL="postgresql://..."; npx tsx scripts/...
 */
import { PrismaClient } from "@prisma/client";
import { InstallmentCorrectionService } from "../src/services/installmentCorrection.service";

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
const service = new InstallmentCorrectionService(prisma);
const RUN = `acc-inst-${Date.now()}`;
const results: { name: string; ok: boolean; detail: string }[] = [];

function check(name: string, ok: boolean, detail = "") {
  results.push({ name, ok, detail });
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? ` — ${detail}` : ""}`);
}

function money(value: unknown): number {
  return Math.round(Number(value ?? 0) * 100) / 100;
}

async function outstanding(saleId: string) {
  const rows = await prisma.installment.findMany({
    where: { saleId, deletedAt: null },
    select: { principalAmount: true, paidPrincipalAmount: true },
  });
  return money(
    rows.reduce(
      (sum, row) =>
        sum +
        Math.max(money(row.principalAmount) - money(row.paidPrincipalAmount), 0),
      0,
    ),
  );
}

async function openInstallments(saleId: string) {
  return prisma.installment.findMany({
    where: {
      saleId,
      deletedAt: null,
      status: { notIn: ["pagada", "ajustada", "cancelada"] },
    },
    orderBy: { installmentNumber: "asc" },
  });
}

async function main() {
  const company = await prisma.company.create({
    data: { tenantKey: RUN, name: `Cuotas ${RUN}` },
  });
  const owner = await prisma.user.create({
    data: {
      companyId: company.id,
      syncId: `${RUN}-owner`,
      email: `${RUN}-owner@acceptance.local`,
      name: "Owner Cuotas",
      passwordHash: "not-used",
      role: "OWNER",
      localRole: "admin",
    },
  });
  const client = await prisma.client.create({
    data: { companyId: company.id, syncId: `${RUN}-client`, name: "Cliente Cuotas" },
  });
  const lot = await prisma.lot.create({
    data: { companyId: company.id, syncId: `${RUN}-lot`, block: "D", number: "01", status: "vendido" },
  });
  const sale = await prisma.sale.create({
    data: {
      companyId: company.id,
      syncId: `${RUN}-sale`,
      clientId: client.id,
      lotId: lot.id,
      clientSyncId: client.syncId,
      lotSyncId: lot.syncId,
      saleDate: new Date("2026-08-01T00:00:00.000Z"),
      status: "activa",
      total: 40000,
      initialRequiredAmount: 0,
      initialPaid: 0,
      initialPendingAmount: 0,
      financedBalance: 40000,
      balance: 30000,
      monthlyInterestRate: 0,
      installmentCount: 4,
    },
  });

  const dueDates = [
    "2026-09-01",
    "2026-10-01",
    "2026-11-01",
    "2026-12-01",
  ];
  const created: string[] = [];
  for (let index = 0; index < 4; index += 1) {
    const paid = index === 0;
    const row = await prisma.installment.create({
      data: {
        companyId: company.id,
        syncId: `${RUN}-inst-${index + 1}`,
        saleId: sale.id,
        saleSyncId: sale.syncId,
        installmentNumber: index + 1,
        dueDate: new Date(`${dueDates[index]}T00:00:00.000Z`),
        openingBalance: 40000 - index * 10000,
        principalAmount: 10000,
        interestAmount: 0,
        totalAmount: 10000,
        paidAmount: paid ? 10000 : 0,
        paidPrincipalAmount: paid ? 10000 : 0,
        paidInterestAmount: 0,
        endingBalance: 40000 - (index + 1) * 10000,
        status: paid ? "pagada" : "pendiente",
      },
      select: { id: true },
    });
    created.push(row.id);
  }
  const payment = await prisma.payment.create({
    data: {
      companyId: company.id,
      syncId: `${RUN}-pay-1`,
      saleId: sale.id,
      clientId: client.id,
      installmentId: created[0],
      saleSyncId: sale.syncId,
      installmentSyncId: `${RUN}-inst-1`,
      paidAt: new Date("2026-09-01T00:00:00.000Z"),
      amount: 10000,
      method: "efectivo",
      paymentType: "cuota",
      principalApplied: 10000,
      interestApplied: 0,
      lateFeeApplied: 0,
    },
  });

  try {
    const initialOutstanding = await outstanding(sale.id);
    check(
      "el fixture arranca con saldo igual al capital de cuotas abiertas",
      initialOutstanding === 30000 &&
        money((await prisma.sale.findUnique({ where: { id: sale.id } }))?.balance) === 30000,
      String(initialOutstanding),
    );

    // ── 1. Preview de cambio de vencimiento ───────────────────────────────
    const open = await openInstallments(sale.id);
    const cuota2 = open[0];
    const preview = (await service.previewInstallmentCorrection({
      companyId: company.id,
      saleId: sale.id,
      action: "change_due_date",
      installmentId: cuota2.id,
      dueDate: "2026-10-20T00:00:00.000Z",
    })) as any;
    check(
      "preview informa el capital y el proximo vencimiento",
      preview?.impact?.outstandingPrincipalBefore === 30000 &&
        preview?.impact?.outstandingPrincipalAfter === 30000 &&
        preview?.impact?.principalPreserved === true,
      `antes=${preview?.impact?.outstandingPrincipalBefore} despues=${preview?.impact?.outstandingPrincipalAfter}`,
    );
    const cuotaAfterPreview = await prisma.installment.findUnique({
      where: { id: cuota2.id },
    });
    check(
      "el preview NO escribe nada (rollback)",
      cuotaAfterPreview?.dueDate?.toISOString() === "2026-10-01T00:00:00.000Z",
      String(cuotaAfterPreview?.dueDate?.toISOString()),
    );

    // ── 2. Aplicar cambio de vencimiento ──────────────────────────────────
    const moved = (await service.applyInstallmentCorrection({
      companyId: company.id,
      saleId: sale.id,
      action: "change_due_date",
      installmentId: cuota2.id,
      dueDate: "2026-10-20T00:00:00.000Z",
      reason: "Vencimiento mal capturado",
      performedByUserId: owner.id,
      idempotencyKey: `${RUN}-due`,
      expectedSaleVersion: (await prisma.sale.findUnique({ where: { id: sale.id } }))!.version,
    })) as any;
    const cuotaMoved = await prisma.installment.findUnique({
      where: { id: cuota2.id },
    });
    check(
      "aplica el cambio de vencimiento",
      cuotaMoved?.dueDate?.toISOString() === "2026-10-20T00:00:00.000Z" &&
        moved?.replayed === false,
      String(cuotaMoved?.dueDate?.toISOString()),
    );
    check(
      "el saldo de la venta no cambia al mover un vencimiento",
      (await outstanding(sale.id)) === 30000 &&
        money((await prisma.sale.findUnique({ where: { id: sale.id } }))?.balance) === 30000,
    );

    // ── 3. Rechazos de integridad ─────────────────────────────────────────
    let paidCode = "";
    try {
      await service.applyInstallmentCorrection({
        companyId: company.id,
        saleId: sale.id,
        action: "change_due_date",
        installmentId: created[0],
        dueDate: "2026-09-15T00:00:00.000Z",
        reason: "intento sobre cuota pagada",
        performedByUserId: owner.id,
        idempotencyKey: `${RUN}-paid`,
      });
    } catch (error: any) {
      paidCode = String(error?.code ?? "");
    }
    check(
      "una cuota con pagos no se puede mover (409)",
      paidCode === "INSTALLMENT_HAS_PAYMENTS",
      paidCode,
    );

    let orderCode = "";
    try {
      await service.applyInstallmentCorrection({
        companyId: company.id,
        saleId: sale.id,
        action: "change_due_date",
        installmentId: cuota2.id,
        dueDate: "2026-12-15T00:00:00.000Z",
        reason: "fecha fuera de orden",
        performedByUserId: owner.id,
        idempotencyKey: `${RUN}-order`,
      });
    } catch (error: any) {
      orderCode = String(error?.code ?? "");
    }
    check(
      "rechaza un vencimiento fuera de orden (409)",
      orderCode === "DUE_DATE_OUT_OF_ORDER",
      orderCode,
    );

    let reasonCode = "";
    try {
      await service.applyInstallmentCorrection({
        companyId: company.id,
        saleId: sale.id,
        action: "change_due_date",
        installmentId: cuota2.id,
        dueDate: "2026-10-10T00:00:00.000Z",
        reason: "  ",
        performedByUserId: owner.id,
        idempotencyKey: `${RUN}-noreason`,
      });
    } catch (error: any) {
      reasonCode = String(error?.code ?? "");
    }
    check("exige motivo", reasonCode === "CORRECTION_REASON_REQUIRED", reasonCode);

    let versionCode = "";
    try {
      await service.applyInstallmentCorrection({
        companyId: company.id,
        saleId: sale.id,
        action: "change_due_date",
        installmentId: cuota2.id,
        dueDate: "2026-10-11T00:00:00.000Z",
        reason: "version obsoleta",
        performedByUserId: owner.id,
        idempotencyKey: `${RUN}-ver`,
        expectedSaleVersion: 999,
      });
    } catch (error: any) {
      versionCode = String(error?.code ?? "");
    }
    check("version obsoleta (409 SALE_VERSION_CONFLICT)", versionCode === "SALE_VERSION_CONFLICT", versionCode);

    // ── 4. Cambio de montos con compensacion ──────────────────────────────
    const openNow = await openInstallments(sale.id);
    const amountResult = (await service.applyInstallmentCorrection({
      companyId: company.id,
      saleId: sale.id,
      action: "change_amounts",
      installmentId: openNow[0].id,
      principalAmount: 12000,
      reason: "Distribucion de capital corregida",
      performedByUserId: owner.id,
      idempotencyKey: `${RUN}-amounts`,
    })) as any;
    const compensated = await prisma.installment.findUnique({
      where: { id: openNow[openNow.length - 1].id },
    });
    check(
      "mover capital compensa la ultima cuota abierta",
      money(compensated?.principalAmount) === 8000 &&
        (await outstanding(sale.id)) === 30000,
      `compensada=${compensated?.principalAmount} saldo=${await outstanding(sale.id)}`,
    );
    check(
      "el impacto marca capital preservado",
      amountResult?.response?.impact?.principalPreserved === true,
    );

    // Cambiar el capital de la ULTIMA cuota abierta traslada la diferencia a la
    // anterior: el capital total del contrato sigue intacto.
    const refreshedOpen = await openInstallments(sale.id);
    const lastOpen = refreshedOpen[refreshedOpen.length - 1];
    const previousOpen = refreshedOpen[refreshedOpen.length - 2];
    const lastBefore = money(lastOpen.principalAmount);
    const previousBefore = money(previousOpen.principalAmount);
    await service.applyInstallmentCorrection({
      companyId: company.id,
      saleId: sale.id,
      action: "change_amounts",
      installmentId: lastOpen.id,
      principalAmount: lastBefore - 2000,
      reason: "Ajuste de la ultima cuota con compensacion",
      performedByUserId: owner.id,
      idempotencyKey: `${RUN}-last-adjust`,
    });
    const previousAfter = await prisma.installment.findUnique({
      where: { id: previousOpen.id },
    });
    check(
      "el cambio en la ultima abierta se compensa en la anterior",
      money(previousAfter?.principalAmount) === previousBefore + 2000 &&
        (await outstanding(sale.id)) === 30000,
      `anterior=${previousAfter?.principalAmount} saldo=${await outstanding(sale.id)}`,
    );

    // ── 5. Agregar cuota (division, sin crear deuda) ──────────────────────
    const beforeAdd = (await openInstallments(sale.id)).length;
    await service.applyInstallmentCorrection({
      companyId: company.id,
      saleId: sale.id,
      action: "add_installment",
      principalAmount: 4000,
      reason: "Se agrega una cuota al final del plan",
      performedByUserId: owner.id,
      idempotencyKey: `${RUN}-add`,
    });
    const afterAdd = await openInstallments(sale.id);
    check(
      "agrega una cuota sin alterar el capital total",
      afterAdd.length === beforeAdd + 1 && (await outstanding(sale.id)) === 30000,
      `cuotas=${afterAdd.length} saldo=${await outstanding(sale.id)}`,
    );

    // ── 6. Eliminar cuota (traslada capital, conserva historia) ───────────
    const target = afterAdd[afterAdd.length - 1];
    await service.applyInstallmentCorrection({
      companyId: company.id,
      saleId: sale.id,
      action: "remove_installment",
      installmentId: target.id,
      reason: "Cuota agregada por error",
      performedByUserId: owner.id,
      idempotencyKey: `${RUN}-remove`,
    });
    const removedRow = await prisma.installment.findUnique({
      where: { id: target.id },
    });
    check(
      "elimina la cuota de forma logica y conserva la historia",
      removedRow?.deletedAt !== null && (await outstanding(sale.id)) === 30000,
      `deletedAt=${removedRow?.deletedAt?.toISOString() ?? null} saldo=${await outstanding(sale.id)}`,
    );
    check(
      "el numero de cuotas abiertas vuelve al valor previo",
      (await openInstallments(sale.id)).length === beforeAdd,
    );

    // ── 7. Reprogramacion completa ────────────────────────────────────────
    const rescheduled = (await service.applyInstallmentCorrection({
      companyId: company.id,
      saleId: sale.id,
      action: "reschedule",
      installmentCount: 4,
      firstDueDate: "2026-12-01T00:00:00.000Z",
      reason: "Reprogramacion solicitada por el cliente",
      performedByUserId: owner.id,
      idempotencyKey: `${RUN}-reschedule`,
    })) as any;
    const rescheduledOpen = await openInstallments(sale.id);
    const sumPrincipal = money(
      rescheduledOpen.reduce((sum, row) => sum + money(row.principalAmount), 0),
    );
    check(
      "reprograma a 4 cuotas conservando el capital pendiente",
      rescheduledOpen.length === 4 && sumPrincipal === 30000,
      `cuotas=${rescheduledOpen.length} capital=${sumPrincipal}`,
    );
    check(
      "la reprogramacion informa el impacto de mora",
      typeof rescheduled?.response?.impact?.grossLateFeesAfter === "number",
      `mora_antes=${rescheduled?.response?.impact?.grossLateFeesBefore} mora_despues=${rescheduled?.response?.impact?.grossLateFeesAfter}`,
    );

    // ── 8. Idempotencia ───────────────────────────────────────────────────
    const replay = (await service.applyInstallmentCorrection({
      companyId: company.id,
      saleId: sale.id,
      action: "reschedule",
      installmentCount: 4,
      firstDueDate: "2026-12-01T00:00:00.000Z",
      reason: "Reprogramacion solicitada por el cliente",
      performedByUserId: owner.id,
      idempotencyKey: `${RUN}-reschedule`,
    })) as any;
    check(
      "reintento con la misma clave es idempotente",
      replay?.replayed === true && (await openInstallments(sale.id)).length === 4,
      `replayed=${replay?.replayed}`,
    );

    // ── 9. Invariantes finales ────────────────────────────────────────────
    const finalSale = await prisma.sale.findUnique({ where: { id: sale.id } });
    check(
      "el saldo de la venta sigue coincidiendo con las cuotas",
      money(finalSale?.balance) === (await outstanding(sale.id)),
      `balance=${finalSale?.balance} cuotas=${await outstanding(sale.id)}`,
    );
    const paymentAfter = await prisma.payment.findUnique({
      where: { id: payment.id },
    });
    check(
      "los pagos existentes no se modificaron",
      money(paymentAfter?.amount) === 10000 &&
        paymentAfter?.paidAt?.toISOString() === "2026-09-01T00:00:00.000Z" &&
        paymentAfter?.annulledAt === null,
      `monto=${paymentAfter?.amount}`,
    );
    const paidInstallment = await prisma.installment.findUnique({
      where: { id: created[0] },
    });
    check(
      "la cuota pagada conserva su monto y estado",
      money(paidInstallment?.paidAmount) === 10000 &&
        paidInstallment?.status === "pagada",
      `${paidInstallment?.status}/${paidInstallment?.paidAmount}`,
    );
    const negatives = await prisma.installment.count({
      where: {
        saleId: sale.id,
        OR: [
          { principalAmount: { lt: 0 } },
          { totalAmount: { lt: 0 } },
          { paidAmount: { lt: 0 } },
        ],
      },
    });
    check("ninguna cuota queda con montos negativos", negatives === 0);

    // ── 10. Auditoria de solo lectura ─────────────────────────────────────
    const audit = (await service.getInstallmentCorrectionHistory({
      companyId: company.id,
      saleId: sale.id,
    })) as any;
    const history = Array.isArray(audit?.history) ? audit.history : [];
    check(
      "la auditoria registra las correcciones aplicadas",
      history.length >= 5 &&
        history.some((entry: any) => entry.action === "reschedule") &&
        history.some((entry: any) => entry.kind === "installment_change"),
      `${history.length} evento(s)`,
    );
  } finally {
    const ids = [company.id];
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
