/**
 * FASE 01C — Prueba END-TO-END del motor de correccion contra PostgreSQL real.
 *
 * NO es una prueba de `npm test`: escribe datos y requiere una base de
 * Acceptance LOCAL. Crea su propio fixture aislado (empresa/cliente/solar/venta
 * con 3 cuotas y 3 pagos), ejecuta preview/apply, verifica invariantes y borra
 * TODO al final.
 *
 * Uso:
 *   $env:ACCEPTANCE_DATABASE_URL="postgresql://user:pass@host:port/db"
 *   npx tsx scripts/acceptance-payment-correction.ts
 *
 * Nunca apunta a produccion: si la URL no contiene "127.0.0.1"/"localhost" el
 * script se niega a ejecutarse.
 */
import { PrismaClient } from "@prisma/client";
import { AuthoritativePaymentService } from "../src/services/authoritativePayment.service";

const url = process.env.ACCEPTANCE_DATABASE_URL ?? "";
if (!url) {
  console.error("Falta ACCEPTANCE_DATABASE_URL.");
  process.exit(2);
}
if (!/(127\.0\.0\.1|localhost)/.test(url)) {
  console.error("Rechazado: la URL no es local. Este script solo corre en Acceptance local.");
  process.exit(2);
}

const prisma = new PrismaClient({ datasources: { db: { url } } });
const service = new AuthoritativePaymentService(prisma);

const RUN = `acc-corr-${Date.now()}`;
const results: { name: string; ok: boolean; detail: string }[] = [];

function check(name: string, ok: boolean, detail = "") {
  results.push({ name, ok, detail });
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? ` — ${detail}` : ""}`);
}

function money(value: unknown): number {
  const n = Number(value ?? 0);
  return Math.round(n * 100) / 100;
}

async function outstandingPrincipal(saleId: string) {
  const rows = await prisma.installment.findMany({
    where: { saleId, deletedAt: null },
    select: { principalAmount: true, paidPrincipalAmount: true, status: true },
  });
  const sum = rows
    .filter((r) => !["ajustada", "cancelada"].includes(r.status ?? ""))
    .reduce(
      (acc, r) =>
        acc + Math.max(money(r.principalAmount) - money(r.paidPrincipalAmount), 0),
      0,
    );
  return Math.round(sum * 100) / 100;
}

async function main() {
  // ── Fixture aislado ───────────────────────────────────────────────────────
  const company = await prisma.company.create({
    data: { tenantKey: RUN, name: `Correccion ${RUN}` },
  });
  const otherCompany = await prisma.company.create({
    data: { tenantKey: `${RUN}-b`, name: `Correccion B ${RUN}` },
  });
  const client = await prisma.client.create({
    data: { companyId: company.id, syncId: `${RUN}-client`, name: "Cliente Correccion" },
  });
  const owner = await prisma.user.create({
    data: {
      companyId: company.id,
      syncId: `${RUN}-owner`,
      email: `${RUN}@acceptance.local`,
      name: "Owner Acceptance",
      passwordHash: "not-used",
      role: "OWNER",
      localRole: "admin",
    },
  });
  const actor = owner.id;
  const lot = await prisma.lot.create({
    data: { companyId: company.id, syncId: `${RUN}-lot`, block: "A", number: "01", status: "vendido" },
  });
  const sale = await prisma.sale.create({
    data: {
      companyId: company.id,
      syncId: `${RUN}-sale`,
      clientId: client.id,
      lotId: lot.id,
      clientSyncId: client.syncId,
      lotSyncId: lot.syncId,
      saleDate: new Date("2026-09-01T00:00:00.000Z"),
      status: "activa",
      total: 30000,
      initialRequiredAmount: 0,
      initialPaid: 0,
      initialPendingAmount: 0,
      financedBalance: 30000,
      balance: 30000,
      monthlyInterestRate: 0,
      installmentCount: 3,
    },
  });

  const specs = [
    { n: 1, due: "2026-10-01", principal: 10000, paid: 10000, paidAt: "2026-10-02" },
    { n: 2, due: "2026-11-01", principal: 10000, paid: 10000, paidAt: "2026-11-01" },
    { n: 3, due: "2026-12-01", principal: 10000, paid: 10000, paidAt: "2026-12-01" },
  ];
  const installments: Record<number, string> = {};
  const payments: Record<number, { id: string; version: number }> = {};
  for (const spec of specs) {
    const installment = await prisma.installment.create({
      data: {
        companyId: company.id,
        syncId: `${RUN}-inst-${spec.n}`,
        saleId: sale.id,
        saleSyncId: sale.syncId,
        installmentNumber: spec.n,
        dueDate: new Date(`${spec.due}T00:00:00.000Z`),
        openingBalance: 30000 - (spec.n - 1) * 10000,
        principalAmount: spec.principal,
        interestAmount: 0,
        totalAmount: spec.principal,
        paidAmount: spec.paid,
        paidPrincipalAmount: spec.paid,
        paidInterestAmount: 0,
        endingBalance: 30000 - spec.n * 10000,
        status: "pagada",
      },
    });
    installments[spec.n] = installment.id;
    const payment = await prisma.payment.create({
      data: {
        companyId: company.id,
        syncId: `${RUN}-pay-${spec.n}`,
        saleId: sale.id,
        clientId: client.id,
        installmentId: installment.id,
        saleSyncId: sale.syncId,
        installmentSyncId: installment.syncId,
        paidAt: new Date(`${spec.paidAt}T00:00:00.000Z`),
        amount: spec.paid,
        method: "efectivo",
        paymentType: "cuota",
        principalApplied: spec.principal,
        interestApplied: 0,
        lateFeeApplied: 0,
      },
      select: { id: true, version: true },
    });
    payments[spec.n] = payment;
  }
  await prisma.sale.update({ where: { id: sale.id }, data: { balance: 0, status: "pagada" } });

  try {
    // ── 1. Preview de anulacion HISTORICA (primer pago, con 2 posteriores) ──
    const preview = (await service.previewPaymentCorrection({
      companyId: company.id,
      paymentId: payments[1].id,
      action: "annul",
    })) as any;
    check(
      "preview permite anular un pago historico",
      preview?.correction?.allowed === true,
      preview?.correction?.code,
    );
    check(
      "preview informa el impacto (restaura 10000)",
      money(preview?.impact?.amountRestoredToBalance) === 10000,
      String(preview?.impact?.amountRestoredToBalance),
    );

    // ── 2. Apply de anulacion historica ─────────────────────────────────────
    const applied = (await service.applyPaymentCorrection({
      companyId: company.id,
      paymentId: payments[1].id,
      action: "annul",
      reason: "Pago historico registrado por error",
      performedByUserId: actor,
      idempotencyKey: `${RUN}-annul-1`,
      expectedPaymentVersion: payments[1].version,
    })) as any;
    check("apply anula el pago historico", applied?.replayed === false);

    const annulled = await prisma.payment.findUnique({ where: { id: payments[1].id } });
    check("el pago queda anulado (annulledAt + deletedAt)", !!annulled?.annulledAt && !!annulled?.deletedAt);
    check(
      "se conserva el motivo de anulacion",
      (annulled?.annulmentReason ?? "").includes("registrado por error"),
    );

    const inst1 = await prisma.installment.findUnique({ where: { id: installments[1] } });
    check("la cuota 1 vuelve a estar impaga", money(inst1?.paidAmount) === 0, String(inst1?.paidAmount));
    check("la cuota 1 deja de estar pagada", inst1?.status !== "pagada", String(inst1?.status));

    const saleAfter = await prisma.sale.findUnique({ where: { id: sale.id } });
    const expectedOutstanding = await outstandingPrincipal(sale.id);
    check(
      "el saldo de la venta se restaura y coincide con el saldo de cuotas",
      money(saleAfter?.balance) === expectedOutstanding && expectedOutstanding === 10000,
      `balance=${saleAfter?.balance} cuotas=${expectedOutstanding}`,
    );
    check("la venta vuelve a estado activo", saleAfter?.status === "activa", String(saleAfter?.status));

    // ── 3. Idempotencia: mismo operationKey no duplica efectos ──────────────
    const replay = (await service.applyPaymentCorrection({
      companyId: company.id,
      paymentId: payments[1].id,
      action: "annul",
      reason: "Pago historico registrado por error",
      performedByUserId: actor,
      idempotencyKey: `${RUN}-annul-1`,
      expectedPaymentVersion: payments[1].version,
    })) as any;
    const saleAfterReplay = await prisma.sale.findUnique({ where: { id: sale.id } });
    check(
      "reintento con la misma clave es idempotente (no suma dos veces)",
      replay?.replayed === true && money(saleAfterReplay?.balance) === 10000,
      `replayed=${replay?.replayed} balance=${saleAfterReplay?.balance}`,
    );

    // ── 4. Doble anulacion con clave nueva: rechazo controlado ──────────────
    let doubleCode = "";
    try {
      await service.applyPaymentCorrection({
        companyId: company.id,
        paymentId: payments[1].id,
        action: "annul",
        reason: "otro intento",
        performedByUserId: actor,
        idempotencyKey: `${RUN}-annul-1b`,
      });
    } catch (error: any) {
      doubleCode = String(error?.code ?? "");
    }
    check("segunda anulacion devuelve 409 PAYMENT_ALREADY_ANNULLED", doubleCode === "PAYMENT_ALREADY_ANNULLED", doubleCode);

    // ── 5. Control de version ───────────────────────────────────────────────
    let versionCode = "";
    try {
      await service.applyPaymentCorrection({
        companyId: company.id,
        paymentId: payments[2].id,
        action: "change_date",
        newDate: "2026-11-02T00:00:00.000Z",
        reason: "fecha",
        performedByUserId: actor,
        idempotencyKey: `${RUN}-ver`,
        expectedPaymentVersion: 999,
      });
    } catch (error: any) {
      versionCode = String(error?.code ?? "");
    }
    check("version obsoleta devuelve 409 PAYMENT_VERSION_CONFLICT", versionCode === "PAYMENT_VERSION_CONFLICT", versionCode);

    // ── 6. Cambio de fecha efectiva conservando createdAt ──────────────────
    const before = await prisma.payment.findUnique({ where: { id: payments[2].id } });
    await service.applyPaymentCorrection({
      companyId: company.id,
      paymentId: payments[2].id,
      action: "change_date",
      newDate: "2026-10-15T00:00:00.000Z",
      reason: "Fecha efectiva mal capturada",
      performedByUserId: actor,
      idempotencyKey: `${RUN}-date`,
      expectedPaymentVersion: payments[2].version,
    });
    const after = await prisma.payment.findUnique({ where: { id: payments[2].id } });
    check(
      "cambia paidAt a la nueva fecha",
      after?.paidAt?.toISOString() === "2026-10-15T00:00:00.000Z",
      String(after?.paidAt?.toISOString()),
    );
    check(
      "conserva createdAt original",
      before?.createdAt.getTime() === after?.createdAt.getTime(),
    );
    check(
      "deja auditoria de la correccion en raw",
      Array.isArray((after?.raw as any)?.corrections) &&
        (after?.raw as any).corrections.length === 1,
    );

    // ── 7. Correccion de monto: anula + reemplazo enlazado ─────────────────
    const amountFix = (await service.applyPaymentCorrection({
      companyId: company.id,
      paymentId: payments[3].id,
      action: "correct_amount",
      newAmount: 4000,
      newDate: "2026-12-01T00:00:00.000Z",
      reason: "Monto capturado incorrecto",
      performedByUserId: actor,
      idempotencyKey: `${RUN}-amount`,
      expectedPaymentVersion: payments[3].version,
    })) as any;
    const original = await prisma.payment.findUnique({ where: { id: payments[3].id } });
    const replacements = await prisma.payment.findMany({
      where: { companyId: company.id, saleId: sale.id, reversesPaymentId: payments[3].id },
    });
    check("el pago original queda anulado", !!original?.annulledAt);
    check(
      "se crea un pago de reemplazo enlazado",
      replacements.length > 0 && money(replacements[0].amount) === 4000,
      `${replacements.length} reemplazo(s)`,
    );
    check(
      "el reemplazo queda auditado",
      JSON.stringify(amountFix ?? {}).includes("correct_amount"),
    );

    const finalSale = await prisma.sale.findUnique({ where: { id: sale.id } });
    const finalOutstanding = await outstandingPrincipal(sale.id);
    check(
      "el saldo final sigue coincidiendo con las cuotas",
      money(finalSale?.balance) === finalOutstanding,
      `balance=${finalSale?.balance} cuotas=${finalOutstanding}`,
    );
    const negative = await prisma.installment.count({
      where: { saleId: sale.id, OR: [{ paidAmount: { lt: 0 } }, { paidPrincipalAmount: { lt: 0 } }] },
    });
    check("ninguna cuota queda con montos negativos", negative === 0);

    // ── 8. Concurrencia: dos correcciones simultaneas, solo una aplica ─────
    const concurrentBase = await prisma.payment.findUnique({
      where: { id: payments[2].id },
      select: { version: true },
    });
    const concurrent = await Promise.allSettled([
      service.applyPaymentCorrection({
        companyId: company.id,
        paymentId: payments[2].id,
        action: "change_date",
        newDate: "2026-10-20T00:00:00.000Z",
        reason: "Intento concurrente A",
        performedByUserId: actor,
        idempotencyKey: `${RUN}-race-a`,
        expectedPaymentVersion: concurrentBase?.version ?? 0,
      }),
      service.applyPaymentCorrection({
        companyId: company.id,
        paymentId: payments[2].id,
        action: "change_date",
        newDate: "2026-10-21T00:00:00.000Z",
        reason: "Intento concurrente B",
        performedByUserId: actor,
        idempotencyKey: `${RUN}-race-b`,
        expectedPaymentVersion: concurrentBase?.version ?? 0,
      }),
    ]);
    const fulfilled = concurrent.filter((r) => r.status === "fulfilled").length;
    const conflicts = concurrent.filter(
      (r) =>
        r.status === "rejected" &&
        String((r.reason as any)?.code ?? "") === "PAYMENT_VERSION_CONFLICT",
    ).length;
    check(
      "dos correcciones simultaneas: exactamente una se aplica",
      fulfilled === 1 && conflicts === 1,
      `ok=${fulfilled} conflictos=${conflicts}`,
    );

    // ── 9. IDOR: el pago no se puede tocar desde otra empresa ──────────────
    let idorCode = "";
    try {
      await service.previewPaymentCorrection({
        companyId: otherCompany.id,
        paymentId: payments[2].id,
        action: "annul",
      });
    } catch (error: any) {
      idorCode = String(error?.code ?? "");
    }
    check("aislamiento por empresa (IDOR) → PAYMENT_NOT_FOUND", idorCode === "PAYMENT_NOT_FOUND", idorCode);

    // ── 9. Sin motivo no se aplica ninguna correccion ──────────────────────
    let reasonCode = "";
    try {
      await service.applyPaymentCorrection({
        companyId: company.id,
        paymentId: payments[2].id,
        action: "annul",
        reason: "   ",
        performedByUserId: actor,
        idempotencyKey: `${RUN}-noreason`,
      });
    } catch (error: any) {
      reasonCode = String(error?.code ?? "");
    }
    check("exige motivo (CORRECTION_REASON_REQUIRED)", reasonCode === "CORRECTION_REASON_REQUIRED", reasonCode);

    // ═══ FASE 01D ══════════════════════════════════════════════════════════
    // 10. Mora: condonacion PARCIAL y rechazo de exceso
    // ══════════════════════════════════════════════════════════════════════
    const moraLot = await prisma.lot.create({
      data: {
        companyId: company.id,
        syncId: `${RUN}-mora-lot`,
        block: "B",
        number: "02",
        status: "vendido",
      },
    });
    const moraSale = await prisma.sale.create({
      data: {
        companyId: company.id,
        syncId: `${RUN}-mora-sale`,
        clientId: client.id,
        lotId: moraLot.id,
        clientSyncId: client.syncId,
        lotSyncId: moraLot.syncId,
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
        syncId: `${RUN}-mora-inst`,
        saleId: moraSale.id,
        saleSyncId: moraSale.syncId,
        installmentNumber: 1,
        dueDate: new Date("2026-06-01T00:00:00.000Z"),
        openingBalance: 10000,
        principalAmount: 10000,
        interestAmount: 0,
        totalAmount: 10000,
        paidAmount: 0,
        paidPrincipalAmount: 0,
        paidInterestAmount: 0,
        endingBalance: 0,
        status: "vencida",
      },
    });
    const moraSummaryBefore = (await service.getLateFeeSummary({
      companyId: company.id,
      saleId: moraSale.id,
    })) as any;
    const outstandingBefore = money(moraSummaryBefore.outstandingLateFees);
    if (outstandingBefore <= 0) {
      check("mora habilitada para probar condonaciones", false, "policy sin mora exigible");
    } else {
      const partial = Math.round((outstandingBefore / 2) * 100) / 100;
      const partialResult = (await service.waiveLateFees({
        companyId: company.id,
        saleId: moraSale.id,
        operatorUserId: actor,
        idempotencyKey: `${RUN}-waive-partial`,
        confirmSaleSyncId: moraSale.syncId,
        cutoffAt: new Date().toISOString(),
        reason: "Condonacion parcial aprobada",
        waivedAmount: partial,
      })) as any;
      check(
        "condonacion PARCIAL persiste solo el monto indicado",
        money(partialResult?.response?.waivedAmount) === partial &&
          partialResult?.response?.isPartial === true,
        `waived=${partialResult?.response?.waivedAmount} esperado=${partial}`,
      );
      const moraSummaryAfter = (await service.getLateFeeSummary({
        companyId: company.id,
        saleId: moraSale.id,
      })) as any;
      check(
        "la mora exigible baja exactamente lo condonado",
        Math.abs(money(moraSummaryAfter.outstandingLateFees) - (outstandingBefore - partial)) < 0.02,
        `antes=${outstandingBefore} despues=${moraSummaryAfter.outstandingLateFees}`,
      );
      check(
        "la mora condonada acumulada refleja el monto parcial",
        Math.abs(money(moraSummaryAfter.waivedLateFees) - partial) < 0.02,
        String(moraSummaryAfter.waivedLateFees),
      );

      let exceedCode = "";
      try {
        await service.waiveLateFees({
          companyId: company.id,
          saleId: moraSale.id,
          operatorUserId: actor,
          idempotencyKey: `${RUN}-waive-exceed`,
          confirmSaleSyncId: moraSale.syncId,
          cutoffAt: new Date(Date.now() + 60000).toISOString(),
          reason: "Intento excesivo",
          waivedAmount: outstandingBefore * 10,
        });
      } catch (error: any) {
        exceedCode = String(error?.code ?? "");
      }
      check(
        "condonacion mayor que la mora exigible se rechaza",
        exceedCode === "WAIVED_AMOUNT_EXCEEDS_OUTSTANDING",
        exceedCode,
      );
    }

    // ══════════════════════════════════════════════════════════════════════
    // 11. Cambio de fecha: recalcula mora y estado de la cuota
    // ══════════════════════════════════════════════════════════════════════
    const dateLot = await prisma.lot.create({
      data: {
        companyId: company.id,
        syncId: `${RUN}-date-lot`,
        block: "C",
        number: "03",
        status: "vendido",
      },
    });
    const dateSale = await prisma.sale.create({
      data: {
        companyId: company.id,
        syncId: `${RUN}-date-sale`,
        clientId: client.id,
        lotId: dateLot.id,
        clientSyncId: client.syncId,
        lotSyncId: dateLot.syncId,
        saleDate: new Date("2026-06-01T00:00:00.000Z"),
        status: "activa",
        total: 10000,
        initialRequiredAmount: 0,
        initialPaid: 0,
        initialPendingAmount: 0,
        financedBalance: 10000,
        balance: 6000,
        monthlyInterestRate: 0,
        installmentCount: 1,
      },
    });
    // Cuota PARCIALMENTE pagada y vencida: el motor acumula mora real sobre el
    // saldo pendiente, de modo que se puede comprobar que cambiar la fecha
    // efectiva no duplica ni pierde esa mora.
    const dateInstallment = await prisma.installment.create({
      data: {
        companyId: company.id,
        syncId: `${RUN}-date-inst`,
        saleId: dateSale.id,
        saleSyncId: dateSale.syncId,
        installmentNumber: 1,
        dueDate: new Date("2026-07-01T00:00:00.000Z"),
        openingBalance: 10000,
        principalAmount: 10000,
        interestAmount: 0,
        totalAmount: 10000,
        paidAmount: 4000,
        paidPrincipalAmount: 4000,
        paidInterestAmount: 0,
        endingBalance: 6000,
        status: "parcial",
      },
    });
    const latePayment = await prisma.payment.create({
      data: {
        companyId: company.id,
        syncId: `${RUN}-date-pay`,
        saleId: dateSale.id,
        clientId: client.id,
        installmentId: dateInstallment.id,
        saleSyncId: dateSale.syncId,
        installmentSyncId: dateInstallment.syncId,
        paidAt: new Date("2026-10-01T00:00:00.000Z"),
        amount: 4000,
        method: "efectivo",
        paymentType: "cuota",
        principalApplied: 4000,
        interestApplied: 0,
        lateFeeApplied: 0,
      },
    });
    const lateSummary = (await service.getLateFeeSummary({
      companyId: company.id,
      saleId: dateSale.id,
    })) as any;
    const moraWhenLate = money(lateSummary.grossLateFees);
    await service.applyPaymentCorrection({
      companyId: company.id,
      paymentId: latePayment.id,
      action: "change_date",
      newDate: "2026-07-02T00:00:00.000Z",
      reason: "Fecha efectiva corregida al dia real de pago",
      performedByUserId: actor,
      idempotencyKey: `${RUN}-date-fix`,
      expectedPaymentVersion: latePayment.version,
    });
    const onTimeSummary = (await service.getLateFeeSummary({
      companyId: company.id,
      saleId: dateSale.id,
    })) as any;
    const moraWhenOnTime = money(onTimeSummary.grossLateFees);
    const paymentAfterDate = await prisma.payment.findUnique({
      where: { id: latePayment.id },
    });
    const installmentAfterDate = await prisma.installment.findUnique({
      where: { id: dateInstallment.id },
    });
    check(
      "el cambio de fecha se persiste en paidAt",
      paymentAfterDate?.paidAt?.toISOString() === "2026-07-02T00:00:00.000Z",
      String(paymentAfterDate?.paidAt?.toISOString()),
    );
    check(
      "adelantar la fecha del pago reduce la mora acumulada",
      moraWhenLate > 0 && moraWhenOnTime < moraWhenLate,
      `mora con fecha tarde=${moraWhenLate} mora con fecha temprana=${moraWhenOnTime}`,
    );
    check(
      "el cambio de fecha conserva createdAt y las porciones aplicadas",
      paymentAfterDate?.createdAt.getTime() === latePayment.createdAt.getTime() &&
        money(paymentAfterDate?.principalApplied) === 4000 &&
        money(paymentAfterDate?.lateFeeApplied) === 0,
      `principal=${paymentAfterDate?.principalApplied} mora=${paymentAfterDate?.lateFeeApplied}`,
    );
    check(
      "el estado de la cuota sigue coherente tras cambiar la fecha",
      installmentAfterDate?.status === "parcial",
      String(installmentAfterDate?.status),
    );

    // Retrasar la fecha debe volver a subir la mora (efecto simetrico).
    await service.applyPaymentCorrection({
      companyId: company.id,
      paymentId: latePayment.id,
      action: "change_date",
      newDate: "2026-09-15T00:00:00.000Z",
      reason: "Fecha efectiva retrasada (prueba simetrica)",
      performedByUserId: actor,
      idempotencyKey: `${RUN}-date-fix-2`,
      expectedPaymentVersion: (paymentAfterDate?.version ?? 0) as number,
    });
    const delayedSummary = (await service.getLateFeeSummary({
      companyId: company.id,
      saleId: dateSale.id,
    })) as any;
    const moraWhenDelayed = money(delayedSummary.grossLateFees);
    check(
      "retrasar la fecha del pago vuelve a subir la mora",
      moraWhenDelayed > moraWhenOnTime,
      `mora temprana=${moraWhenOnTime} mora retrasada=${moraWhenDelayed}`,
    );

    // ══════════════════════════════════════════════════════════════════════
    // 12. Invariante global: porciones aplicadas = monto del pago
    // ══════════════════════════════════════════════════════════════════════
    for (const targetSale of [sale.id, dateSale.id]) {
      const activePayments = await prisma.payment.findMany({
        where: { companyId: company.id, saleId: targetSale, deletedAt: null, annulledAt: null },
        select: {
          id: true,
          amount: true,
          principalApplied: true,
          interestApplied: true,
          lateFeeApplied: true,
        },
      });
      const inconsistent = activePayments.filter(
        (row) =>
          Math.abs(
            money(row.principalApplied) +
              money(row.interestApplied) +
              money(row.lateFeeApplied) -
              money(row.amount),
          ) > 0.011,
      );
      check(
        `porciones (capital+interes+mora) conservadas en venta ${targetSale.slice(-6)}`,
        inconsistent.length === 0,
        `${inconsistent.length} pago(s) inconsistente(s)`,
      );
    }

    // ══════════════════════════════════════════════════════════════════════
    // 13. Auditoria de solo lectura reconstruida desde el backend
    // ══════════════════════════════════════════════════════════════════════
    const audit = (await service.getPaymentCorrectionHistory({
      companyId: company.id,
      paymentId: payments[1].id,
    })) as any;
    const auditEntries = Array.isArray(audit?.history) ? audit.history : [];
    check(
      "la auditoria incluye alta, anulacion y operacion autoritativa",
      auditEntries.some((entry: any) => entry.kind === "created") &&
        auditEntries.some((entry: any) => entry.kind === "annulment") &&
        auditEntries.some((entry: any) => entry.kind === "authoritative_operation"),
      `${auditEntries.length} evento(s)`,
    );
    check(
      "la auditoria conserva el motivo de la correccion",
      auditEntries.some(
        (entry: any) =>
          String(entry.reason ?? "").includes("registrado por error"),
      ),
    );
  } finally {
    // ── Limpieza total del fixture ─────────────────────────────────────────
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
    console.log("FALLOS:");
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
