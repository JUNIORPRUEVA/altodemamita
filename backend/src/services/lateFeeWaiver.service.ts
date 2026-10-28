/**
 * Fase 3 — Carga de condonaciones de mora para el calculo autoritativo.
 *
 * `LateFeeCalculationService.calculateSaleSummary({ ..., waivers })` es el UNICO
 * punto donde se aplica la condonacion. Cualquier consumidor (pago autoritativo,
 * liquidacion, recordatorios, reportes) que pase estas condonaciones obtiene la
 * mora EXIGIBLE, no la bruta.
 *
 * No sustituye pagos ni crea movimientos de caja: la mora cobrada historica
 * sigue viviendo en `Payment.lateFeeApplied`.
 */
import { Prisma } from '@prisma/client';
import { LateFeeWaiverInput } from './lateFeeCalculation.service';

type WaiverReader = {
  lateFeeWaiver: {
    findMany(args: {
      where: { companyId: string; saleId: string };
      select: { installmentSyncId: true; waivedAmount: true; cutoffAt: true };
    }): Promise<
      Array<{
        installmentSyncId: string | null;
        waivedAmount: Prisma.Decimal;
        cutoffAt: Date;
      }>
    >;
  };
};

export async function loadSaleLateFeeWaivers(
  db: WaiverReader,
  companyId: string,
  saleId: string,
): Promise<LateFeeWaiverInput[]> {
  const rows = await db.lateFeeWaiver.findMany({
    where: { companyId, saleId },
    select: { installmentSyncId: true, waivedAmount: true, cutoffAt: true },
  });
  return rows.map((row) => ({
    installmentSyncId: row.installmentSyncId,
    waivedAmount: row.waivedAmount,
    cutoffAt: row.cutoffAt,
  }));
}

/** Suma total condonada de una venta (para reportes). */
export function sumWaivedLateFee(waivers: LateFeeWaiverInput[]): number {
  return waivers.reduce((total, waiver) => total + Number(waiver.waivedAmount ?? 0), 0);
}
