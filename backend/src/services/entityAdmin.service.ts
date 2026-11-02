import { Prisma, PrismaClient } from "@prisma/client";
import { AuthoritativeError } from "./authoritativeErrors.service";
import { decimal, toNumber } from "./authoritativeSale.service";
import { roundCurrency } from "./financing.service";
import {
  IdempotentResult,
  requireIdempotencyKey,
  runIdempotentOperation,
} from "./idempotency.service";

/**
 * FASE 04 — Administracion OWNER de CLIENTES y SOLARES.
 *
 * Reglas de integridad (validadas en preview y en apply):
 *
 *  C1. Un cliente con ventas ACTIVAS no se desactiva ni se fusiona como origen:
 *      su historia financiera debe seguir resolviendo a una venta viva.
 *  C2. La cedula/documento de un cliente activo es unica dentro de la empresa.
 *  C3. Fusionar duplicados NO borra: reapunta ventas y pagos al cliente destino
 *      y marca el origen como fusionado (deletedAt + `mergedIntoClientId`).
 *  L1. Un solar con venta ACTIVA no puede pasar a 'disponible' ni desactivarse:
 *      se libera con la correccion de venta (03), no aqui.
 *  L2. 'vendido' no se fija a mano: lo determina la venta.
 *  L3. Bloque+numero de un solar activo es unico dentro de la empresa.
 *  E1. Toda operacion es atomica, idempotente, con version optimista, motivo
 *      obligatorio y auditoria en `raw.corrections` + AuthoritativeOperation.
 */

export type EntityKind = "client" | "lot";

export type EntityAdminAction =
  | "update_identity"
  | "update_details"
  | "update_status"
  | "deactivate"
  | "reactivate"
  | "merge_duplicates";

const CLIENT_ACTIONS: readonly EntityAdminAction[] = [
  "update_identity",
  "deactivate",
  "reactivate",
  "merge_duplicates",
];

const LOT_ACTIONS: readonly EntityAdminAction[] = [
  "update_details",
  "update_status",
  "deactivate",
  "reactivate",
];

export function isEntityAdminAction(
  kind: EntityKind,
  value: unknown,
): value is EntityAdminAction {
  if (typeof value !== "string") return false;
  const list = kind === "client" ? CLIENT_ACTIONS : LOT_ACTIONS;
  return (list as readonly string[]).includes(value);
}

/** Estados de solar que el OWNER puede fijar manualmente. */
export const MANUAL_LOT_STATUSES = [
  "disponible",
  "reservado",
  "bloqueado",
  "mantenimiento",
] as const;

export type EntityAdminInput = {
  companyId: string;
  kind: EntityKind;
  entityId: string;
  action: EntityAdminAction;
  /** cliente */
  name?: string | null;
  document?: string | null;
  phone?: string | null;
  address?: string | null;
  mergeSourceId?: string | null;
  /** solar */
  block?: string | null;
  number?: string | null;
  area?: number | null;
  price?: number | null;
  status?: string | null;
};

export type ApplyEntityAdminInput = EntityAdminInput & {
  performedByUserId: string;
  reason: string;
  idempotencyKey: string;
  expectedVersion?: number | null;
};

export function normalizeIdentifier(value: string | null | undefined) {
  return (value ?? "").trim().toUpperCase().replace(/\s+/g, " ");
}

export function validateClientIdentity(input: {
  name: string;
  document: string;
}): { code: string; message: string } | null {
  if (input.name.trim().length < 3) {
    return {
      code: "INVALID_CLIENT_NAME",
      message: "El nombre del cliente debe tener al menos 3 caracteres.",
    };
  }
  return null;
}

export function validateLotDetails(input: {
  block: string;
  number: string;
  area: number;
  price: number;
}): { code: string; message: string } | null {
  if (!input.block.trim() || !input.number.trim()) {
    return {
      code: "INVALID_LOT_IDENTIFIER",
      message: "El bloque y el numero del solar son obligatorios.",
    };
  }
  if (!Number.isFinite(input.area) || input.area <= 0) {
    return {
      code: "INVALID_LOT_AREA",
      message: "El area debe ser mayor que cero.",
    };
  }
  if (!Number.isFinite(input.price) || input.price < 0) {
    return {
      code: "INVALID_LOT_PRICE",
      message: "El precio no puede ser negativo.",
    };
  }
  return null;
}

/** Valida el cambio manual de estado de un solar. */
export function validateManualLotStatus(input: {
  status: string;
  hasActiveSale: boolean;
}): { code: string; message: string } | null {
  const status = input.status.trim().toLowerCase();
  if (status === "vendido") {
    return {
      code: "LOT_SOLD_STATUS_MANUAL",
      message:
        "El estado 'vendido' lo determina la venta. Usa la correccion de venta para liberarlo o reasignarlo.",
    };
  }
  if (!(MANUAL_LOT_STATUSES as readonly string[]).includes(status)) {
    return {
      code: "LOT_STATUS_UNSUPPORTED",
      message: `Estado de solar no soportado. Valores permitidos: ${MANUAL_LOT_STATUSES.join(", ")}.`,
    };
  }
  if (input.hasActiveSale && status === "disponible") {
    return {
      code: "LOT_HAS_ACTIVE_SALE",
      message:
        "El solar tiene una venta activa: liberalo cancelando o corrigiendo la venta, no desde Solares.",
    };
  }
  return null;
}

function appendAudit(raw: unknown, entry: Record<string, unknown>) {
  const base =
    raw && typeof raw === "object" && !Array.isArray(raw)
      ? { ...(raw as Record<string, unknown>) }
      : {};
  const previous = Array.isArray(base.corrections)
    ? (base.corrections as unknown[])
    : [];
  base.corrections = [...previous, entry].slice(-30);
  return base;
}

type Tx = Prisma.TransactionClient;

export class EntityAdminService {
  constructor(private readonly prisma: PrismaClient) {}

  async preview(input: EntityAdminInput): Promise<Prisma.JsonObject> {
    if (!isEntityAdminAction(input.kind, input.action)) {
      throw new AuthoritativeError(
        "CORRECTION_ACTION_UNSUPPORTED",
        "Accion administrativa no soportada.",
        400,
      );
    }
    const PREVIEW = Symbol("preview-rollback");
    try {
      await this.prisma.$transaction(async (tx) => {
        const result = await runAdmin(tx, input, {
          performedByUserId: "preview",
          reason: "preview",
          persistAudit: false,
        });
        throw { [PREVIEW]: true, result };
      });
    } catch (error: any) {
      if (error && error[PREVIEW]) {
        return { ...error.result, preview: true } as unknown as Prisma.JsonObject;
      }
      throw error;
    }
    throw new AuthoritativeError(
      "PREVIEW_FAILED",
      "No se pudo calcular la previsualizacion.",
      500,
    );
  }

  async apply(
    input: ApplyEntityAdminInput,
  ): Promise<IdempotentResult<Prisma.JsonObject>> {
    const operationKey = requireIdempotencyKey(input.idempotencyKey);
    if (!isEntityAdminAction(input.kind, input.action)) {
      throw new AuthoritativeError(
        "CORRECTION_ACTION_UNSUPPORTED",
        "Accion administrativa no soportada.",
        400,
      );
    }
    const reason = String(input.reason ?? "").trim();
    if (!reason) {
      throw new AuthoritativeError(
        "CORRECTION_REASON_REQUIRED",
        "Indica el motivo de la correccion.",
        400,
      );
    }
    return this.prisma.$transaction((tx) =>
      runIdempotentOperation(tx, {
        companyId: input.companyId,
        operationKey,
        operationType: `${input.kind}.admin.${input.action}`,
        requestPayload: {
          kind: input.kind,
          entityId: input.entityId,
          action: input.action,
          mergeSourceId: input.mergeSourceId ?? null,
          status: input.status ?? null,
          reason,
          performedByUserId: input.performedByUserId,
        },
        run: async () => {
          const current = await loadEntity(tx, input);
          if (
            input.expectedVersion != null &&
            current.version !== input.expectedVersion
          ) {
            throw new AuthoritativeError(
              "ENTITY_VERSION_CONFLICT",
              "El registro cambio desde que abriste el dialogo. Recarga e intentalo de nuevo.",
              409,
            );
          }
          const result = await runAdmin(tx, input, {
            performedByUserId: input.performedByUserId,
            reason,
            persistAudit: true,
          });
          return {
            response: {
              ...result,
              correction: {
                action: input.action,
                reason,
                performedByUserId: input.performedByUserId,
                performedAt: new Date().toISOString(),
              },
            } as unknown as Prisma.JsonObject,
            resourceType: input.kind,
            resourceId: input.entityId,
          };
        },
      }),
    );
  }

  /** Auditoria de solo lectura de una entidad. */
  async history(input: {
    companyId: string;
    kind: EntityKind;
    entityId: string;
  }): Promise<Prisma.JsonObject> {
    const table = input.kind === "client" ? "client" : "lot";
    const row = await (this.prisma as any)[table].findFirst({
      where: { id: input.entityId, companyId: input.companyId },
      select: { id: true, raw: true, version: true, deletedAt: true },
    });
    if (!row) {
      throw new AuthoritativeError(
        input.kind === "client" ? "CLIENT_NOT_FOUND" : "LOT_NOT_FOUND",
        "El registro no existe.",
        404,
      );
    }
    const operations = await this.prisma.authoritativeOperation.findMany({
      where: {
        companyId: input.companyId,
        resourceId: input.entityId,
        operationType: { startsWith: `${input.kind}.admin.` },
      },
      select: { operationType: true, createdAt: true, response: true },
      orderBy: { createdAt: "asc" },
    });
    type Entry = Record<string, unknown>;
    const history: Entry[] = [];
    const raw = (row.raw ?? {}) as Record<string, unknown>;
    if (Array.isArray(raw.corrections)) {
      for (const entry of raw.corrections as unknown[]) {
        if (entry && typeof entry === "object") {
          history.push({ kind: "manual_change", ...(entry as Entry) });
        }
      }
    }
    for (const operation of operations) {
      const response = (operation.response ?? {}) as Record<string, unknown>;
      const correction = (response.correction ?? {}) as Record<string, unknown>;
      history.push({
        kind: "authoritative_operation",
        at: operation.createdAt.toISOString(),
        action: String(operation.operationType).replace(
          `${input.kind}.admin.`,
          "",
        ),
        reason: correction.reason ?? null,
        performedByUserId: correction.performedByUserId ?? null,
      });
    }
    history.sort((a, b) => String(a.at ?? "").localeCompare(String(b.at ?? "")));
    return {
      entity: {
        id: row.id,
        version: row.version,
        deletedAt: row.deletedAt?.toISOString() ?? null,
      },
      history,
    } as unknown as Prisma.JsonObject;
  }
}

type LoadedEntity = {
  id: string;
  version: number;
  deletedAt: Date | null;
  raw: Prisma.JsonValue | null;
  [key: string]: unknown;
};

async function loadEntity(tx: Tx, input: EntityAdminInput): Promise<LoadedEntity> {
  if (input.kind === "client") {
    const client = await tx.client.findFirst({
      where: { id: input.entityId, companyId: input.companyId },
    });
    if (!client) {
      throw new AuthoritativeError(
        "CLIENT_NOT_FOUND",
        "El cliente no existe en la empresa.",
        404,
      );
    }
    return client as unknown as LoadedEntity;
  }
  const lot = await tx.lot.findFirst({
    where: { id: input.entityId, companyId: input.companyId },
  });
  if (!lot) {
    throw new AuthoritativeError(
      "LOT_NOT_FOUND",
      "El solar no existe en la empresa.",
      404,
    );
  }
  return lot as unknown as LoadedEntity;
}

async function activeSaleFor(
  tx: Tx,
  companyId: string,
  where: { clientId?: string; lotId?: string },
  exceptSaleId?: string,
) {
  return tx.sale.findFirst({
    where: {
      companyId,
      deletedAt: null,
      status: { notIn: ["cancelada"] },
      ...(where.clientId ? { clientId: where.clientId } : {}),
      ...(where.lotId ? { lotId: where.lotId } : {}),
      ...(exceptSaleId ? { id: { not: exceptSaleId } } : {}),
    },
    select: { id: true, syncId: true },
  });
}

async function runAdmin(
  tx: Tx,
  input: EntityAdminInput,
  audit: { performedByUserId: string; reason: string; persistAudit: boolean },
): Promise<Record<string, unknown>> {
  const entity = await loadEntity(tx, input);
  const now = new Date();
  const auditEntry = (extra: Record<string, unknown>) => ({
    action: input.action,
    performedByUserId: audit.performedByUserId,
    reason: audit.reason,
    performedAt: now.toISOString(),
    ...extra,
  });
  const persist = audit.persistAudit;
  let detail: Record<string, unknown> = {};

  if (input.kind === "client") {
    const activeSale = await activeSaleFor(tx, input.companyId, {
      clientId: entity.id,
    });
    switch (input.action) {
      case "update_identity": {
        const name = String(input.name ?? "").trim();
        const document = String(input.document ?? "").trim();
        const validation = validateClientIdentity({ name, document });
        if (validation) {
          throw new AuthoritativeError(validation.code, validation.message, 400);
        }
        if (document) {
          const duplicated = await tx.client.findFirst({
            where: {
              companyId: input.companyId,
              deletedAt: null,
              id: { not: entity.id },
              document: { equals: document, mode: "insensitive" },
            },
            select: { id: true, name: true },
          });
          if (duplicated) {
            throw new AuthoritativeError(
              "CLIENT_DOCUMENT_TAKEN",
              `Esa cedula/documento ya pertenece a ${duplicated.name}. Usa 'Fusionar duplicados' si es el mismo cliente.`,
              409,
            );
          }
        }
        await tx.client.update({
          where: { id: entity.id },
          data: {
            name,
            document: document || null,
            phone: String(input.phone ?? "").trim() || null,
            address: String(input.address ?? "").trim() || null,
            raw: persist
              ? (appendAudit(entity.raw, auditEntry({ role: "identity" })) as unknown as Prisma.InputJsonValue)
              : (entity.raw ?? Prisma.JsonNull),
            version: { increment: 1 },
          },
        });
        detail = { name, document };
        break;
      }
      case "deactivate": {
        if (activeSale) {
          throw new AuthoritativeError(
            "CLIENT_HAS_ACTIVE_SALES",
            "El cliente tiene ventas activas: cancela o corrige esas ventas antes de desactivarlo.",
            409,
          );
        }
        await tx.client.update({
          where: { id: entity.id },
          data: {
            deletedAt: now,
            raw: persist
              ? (appendAudit(entity.raw, auditEntry({ role: "deactivate" })) as unknown as Prisma.InputJsonValue)
              : (entity.raw ?? Prisma.JsonNull),
            version: { increment: 1 },
          },
        });
        detail = { deactivatedAt: now.toISOString() };
        break;
      }
      case "reactivate": {
        if (entity.deletedAt === null) {
          throw new AuthoritativeError(
            "CLIENT_ALREADY_ACTIVE",
            "El cliente ya esta activo.",
            409,
          );
        }
        const document = String(entity.document ?? "").trim();
        if (document) {
          const duplicated = await tx.client.findFirst({
            where: {
              companyId: input.companyId,
              deletedAt: null,
              id: { not: entity.id },
              document: { equals: document, mode: "insensitive" },
            },
            select: { id: true, name: true },
          });
          if (duplicated) {
            throw new AuthoritativeError(
              "CLIENT_DOCUMENT_TAKEN",
              `No se puede reactivar: la cedula/documento esta activa en ${duplicated.name}.`,
              409,
            );
          }
        }
        await tx.client.update({
          where: { id: entity.id },
          data: {
            deletedAt: null,
            raw: persist
              ? (appendAudit(entity.raw, auditEntry({ role: "reactivate" })) as unknown as Prisma.InputJsonValue)
              : (entity.raw ?? Prisma.JsonNull),
            version: { increment: 1 },
          },
        });
        detail = { reactivated: true };
        break;
      }
      case "merge_duplicates": {
        const sourceId = String(input.mergeSourceId ?? "").trim();
        if (!sourceId) {
          throw new AuthoritativeError(
            "MERGE_SOURCE_REQUIRED",
            "Selecciona el cliente duplicado que se fusionara en este.",
            400,
          );
        }
        if (sourceId === entity.id) {
          throw new AuthoritativeError(
            "MERGE_SAME_CLIENT",
            "El cliente destino y el duplicado no pueden ser el mismo.",
            400,
          );
        }
        const source = await tx.client.findFirst({
          where: { id: sourceId, companyId: input.companyId },
        });
        if (!source) {
          throw new AuthoritativeError(
            "CLIENT_NOT_FOUND",
            "El cliente duplicado no existe en la empresa.",
            404,
          );
        }
        const targetSyncId = (entity.syncId as string | null) ?? null;
        const movedSales = await tx.sale.updateMany({
          where: { companyId: input.companyId, clientId: source.id },
          data: {
            clientId: entity.id,
            clientSyncId: targetSyncId,
            version: { increment: 1 },
          },
        });
        const movedPayments = await tx.payment.updateMany({
          where: { companyId: input.companyId, clientId: source.id },
          data: {
            clientId: entity.id,
            clientSyncId: targetSyncId,
            version: { increment: 1 },
          },
        });
        const mergedRaw = appendAudit(source.raw, {
          ...auditEntry({ role: "merged_source", mergedIntoClientId: entity.id }),
        });
        // Se guarda en la RAIZ de `raw` para poder rastrear el origen fusionado
        // sin depender del historial de correcciones.
        mergedRaw.mergedIntoClientId = entity.id;
        await tx.client.update({
          where: { id: source.id },
          data: {
            deletedAt: now,
            raw: persist
              ? (mergedRaw as unknown as Prisma.InputJsonValue)
              : (source.raw ?? Prisma.JsonNull),
            version: { increment: 1 },
          },
        });
        await tx.client.update({
          where: { id: entity.id },
          data: {
            raw: persist
              ? (appendAudit(entity.raw, auditEntry({
                  role: "merge_target",
                  mergedFromClientId: source.id,
                  movedSales: movedSales.count,
                  movedPayments: movedPayments.count,
                })) as unknown as Prisma.InputJsonValue)
              : (entity.raw ?? Prisma.JsonNull),
            version: { increment: 1 },
          },
        });
        detail = {
          mergedFromClientId: source.id,
          movedSales: movedSales.count,
          movedPayments: movedPayments.count,
        };
        break;
      }
      default:
        throw new AuthoritativeError(
          "CORRECTION_ACTION_UNSUPPORTED",
          "Accion de cliente no soportada.",
          400,
        );
    }
  } else {
    const activeSale = await activeSaleFor(tx, input.companyId, {
      lotId: entity.id,
    });
    switch (input.action) {
      case "update_details": {
        const block = String(input.block ?? (entity.block as string | null) ?? "").trim();
        const number = String(input.number ?? (entity.number as string | null) ?? "").trim();
        const area =
          input.area == null ? toNumber(entity.area) : Number(input.area);
        const price =
          input.price == null ? toNumber(entity.price) : Number(input.price);
        const validation = validateLotDetails({ block, number, area, price });
        if (validation) {
          throw new AuthoritativeError(validation.code, validation.message, 400);
        }
        const duplicated = await tx.lot.findFirst({
          where: {
            companyId: input.companyId,
            deletedAt: null,
            id: { not: entity.id },
            block: { equals: block, mode: "insensitive" },
            number: { equals: number, mode: "insensitive" },
          },
          select: { id: true },
        });
        if (duplicated) {
          throw new AuthoritativeError(
            "LOT_IDENTIFIER_TAKEN",
            "Ya existe otro solar activo con ese bloque y numero.",
            409,
          );
        }
        await tx.lot.update({
          where: { id: entity.id },
          data: {
            block,
            number,
            area: decimal(roundCurrency(area)),
            price: decimal(roundCurrency(price)),
            raw: persist
              ? (appendAudit(entity.raw, auditEntry({ role: "details" })) as unknown as Prisma.InputJsonValue)
              : (entity.raw ?? Prisma.JsonNull),
            version: { increment: 1 },
          },
        });
        detail = { block, number, area: roundCurrency(area), price: roundCurrency(price) };
        break;
      }
      case "update_status": {
        const status = String(input.status ?? "").trim().toLowerCase();
        const validation = validateManualLotStatus({
          status,
          hasActiveSale: activeSale !== null,
        });
        if (validation) {
          throw new AuthoritativeError(validation.code, validation.message, 409);
        }
        await tx.lot.update({
          where: { id: entity.id },
          data: {
            status,
            raw: persist
              ? (appendAudit(entity.raw, auditEntry({
                  role: "status",
                  previousStatus: entity.status ?? null,
                  newStatus: status,
                })) as unknown as Prisma.InputJsonValue)
              : (entity.raw ?? Prisma.JsonNull),
            version: { increment: 1 },
          },
        });
        detail = { previousStatus: entity.status ?? null, newStatus: status };
        break;
      }
      case "deactivate": {
        if (activeSale) {
          throw new AuthoritativeError(
            "LOT_HAS_ACTIVE_SALE",
            "El solar tiene una venta activa: liberalo corrigiendo o cancelando la venta.",
            409,
          );
        }
        await tx.lot.update({
          where: { id: entity.id },
          data: {
            deletedAt: now,
            status: "inactivo",
            raw: persist
              ? (appendAudit(entity.raw, auditEntry({ role: "deactivate" })) as unknown as Prisma.InputJsonValue)
              : (entity.raw ?? Prisma.JsonNull),
            version: { increment: 1 },
          },
        });
        detail = { deactivatedAt: now.toISOString() };
        break;
      }
      case "reactivate": {
        if (entity.deletedAt === null) {
          throw new AuthoritativeError(
            "LOT_ALREADY_ACTIVE",
            "El solar ya esta activo.",
            409,
          );
        }
        const block = String((entity.block as string | null) ?? "").trim();
        const number = String((entity.number as string | null) ?? "").trim();
        const duplicated = await tx.lot.findFirst({
          where: {
            companyId: input.companyId,
            deletedAt: null,
            id: { not: entity.id },
            block: { equals: block, mode: "insensitive" },
            number: { equals: number, mode: "insensitive" },
          },
          select: { id: true },
        });
        if (duplicated) {
          throw new AuthoritativeError(
            "LOT_IDENTIFIER_TAKEN",
            "No se puede reactivar: otro solar activo usa ese bloque y numero.",
            409,
          );
        }
        await tx.lot.update({
          where: { id: entity.id },
          data: {
            deletedAt: null,
            status: "disponible",
            raw: persist
              ? (appendAudit(entity.raw, auditEntry({ role: "reactivate" })) as unknown as Prisma.InputJsonValue)
              : (entity.raw ?? Prisma.JsonNull),
            version: { increment: 1 },
          },
        });
        detail = { reactivated: true, status: "disponible" };
        break;
      }
      default:
        throw new AuthoritativeError(
          "CORRECTION_ACTION_UNSUPPORTED",
          "Accion de solar no soportada.",
          400,
        );
    }
  }

  return {
    entityId: entity.id,
    entityVersion: entity.version,
    kind: input.kind,
    action: input.action,
    detail,
    impact: {
      deletedBefore: entity.deletedAt !== null,
      deletedAfter:
        (await (tx as any)[input.kind].findUnique({
          where: { id: entity.id },
          select: { deletedAt: true },
        }))?.deletedAt !== null,
    },
  };
}
