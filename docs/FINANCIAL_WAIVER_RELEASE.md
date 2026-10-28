# Release financiero — Condonación de mora + liquidación con mora

Estado: **PREPARADO, NO DESPLEGADO**. Requiere autorización explícita (ver §10).

## 1. Alcance

Este release contiene únicamente:

1. Tabla aditiva `LateFeeWaiver` (condonación persistente de mora con corte).
2. Asignación **única** de condonaciones en el pago autoritativo (corrige la
   reutilización del monto condonado en varias cuotas).
3. Liquidación total (`getSettlementQuote` / `settleSale`) que incluye la mora
   **exigible** y excluye la condonada y la ya cobrada.
4. Endpoint de mora autoritativa `GET /authoritative/sales/:saleId/late-fee-summary`.
5. Endpoint administrativo de condonación `POST /authoritative/sales/:saleId/late-fee-waiver` (solo OWNER).
6. Windows: la mora cobrable y la condonada se muestran con datos del backend
   cuando está disponible; se bloquea la mutación si la venta tiene condonación
   conocida y el backend no responde.

**Fuera de alcance:** hardening de "venta nueva" (`agent/sale-form-hardening`),
tablas overlay de agenda administrativa, scripts de Acceptance, credenciales.

## 2. Archivos del release

Backend:

```
backend/prisma/schema.prisma
backend/prisma/migrations/20261010130000_add_late_fee_waiver/migration.sql
backend/src/services/lateFeeCalculation.service.ts
backend/src/services/lateFeeWaiver.service.ts
backend/src/services/lateFeeWaiver.service.test.ts
backend/src/services/authoritativePayment.service.ts
backend/src/services/authoritativePayment.service.test.ts
backend/src/services/paymentReminder.service.ts
backend/src/routes/authoritative.routes.ts
```

Windows (`app_local`):

```
lib/features/payments/domain/authoritative_late_fee.dart
lib/features/payments/data/payments_repository.dart
lib/features/payments/presentation/payments_controller.dart
lib/features/payments/presentation/payments_page.dart
lib/features/payments/presentation/payment_form_dialog.dart
test/authoritative_late_fee_test.dart
test/payment_form_dialog_authoritative_late_fee_test.dart
```

## 3. Migración

| # | Nombre | Tipo | Efecto |
|---|---|---|---|
| 1 | `20261010130000_add_late_fee_waiver` | Aditiva | Crea `LateFeeWaiver` + 1 índice único + 4 índices + FK a `Company` |

Producción tiene hoy **8** migraciones; tras aplicar quedan **9**.
No se reescribe historial ni se modifica ningún modelo existente.
No incluye `20261010120000_add_admin_schedule_adjustment` (fuera de alcance).

## 4. Compatibilidad backend ↔ Windows

| Escenario | Resultado |
|---|---|
| Backend nuevo + Windows actual | Compatible. El contrato no cambia; `lateFees` ya existía en la cotización. La app actual **no** consulta la mora autoritativa, por lo que en ventas con condonación mostrará la mora **bruta** en el preview local hasta actualizarse. El **cobro real** lo decide el backend (correcto). |
| Backend nuevo + Windows nuevo | Compatible y consistente: el preview usa la mora autoritativa. |
| Backend actual + Windows nuevo | **No soportado**: `late-fee-summary` devuelve 404 → la app degrada a cálculo local con aviso; si la venta tuviera condonación conocida, bloquearía el pago. No desplegar el cliente antes que el backend. |

**Regla de secuencia:** backend primero, cliente después.

**Riesgo residual:** con Windows antiguo, una venta con mora condonada podría
mostrar un total recomendado superior al cobrable. El monto **cobrado** sigue
siendo el autoritativo, pero el operador verá una cifra distinta. Si el cliente
no se actualiza en la misma ventana, se recomienda no condonar ventas que ese
equipo vaya a cobrar hasta actualizar el cliente.

## 5. Cambio de comportamiento que requiere aprobación

`settleSale` ahora cobra la **mora exigible** al liquidar. Antes liquidaba sin
mora. Es un cambio económico real: una liquidación puede costar más que antes.
Debe aprobarse explícitamente antes del despliegue.

## 6. Backup previo (obligatorio)

```bash
# En el host de producción, con la app cerrada y sin procesos activos.
TS=$(date -u +%Y%m%dT%H%M%SZ)
DIR=/root/ss_deploy_prod/backups
DB=$(docker ps --format '{{.Names}}' | grep -E '^altomamita_altomamita-db\.' | head -n1)

docker exec $DB bash -lc 'PGPASSWORD=$POSTGRES_PASSWORD pg_dump -U $POSTGRES_USER -d altomamita -Fc -Z6 -f /tmp/pre_waiver.dump'
docker cp $DB:/tmp/pre_waiver.dump $DIR/altomamita_pre_waiver_$TS.dump

# Integridad
docker exec $DB bash -lc 'PGPASSWORD=$POSTGRES_PASSWORD pg_restore -l /tmp/pre_waiver.dump | head -5'
sha256sum $DIR/altomamita_pre_waiver_$TS.dump
ls -l  $DIR/altomamita_pre_waiver_$TS.dump
```

Backup lógico adicional sólo de las tablas afectadas:

```sql
COPY (SELECT * FROM "LateFeeWaiver") TO STDOUT WITH CSV HEADER;   -- vacía antes del release
COPY (SELECT * FROM "_prisma_migrations") TO STDOUT WITH CSV HEADER;
```

## 7. Despliegue

1. Verificar rama y commit del release; construir imagen inmutable con tag nuevo.
2. Aplicar migración: `npx prisma migrate deploy` (idempotente; sólo la pendiente).
3. Verificar migraciones aplicadas:

```sql
SELECT migration_name, finished_at FROM "_prisma_migrations"
 WHERE finished_at IS NOT NULL AND rolled_back_at IS NULL
 ORDER BY finished_at;
-- Esperado: 9 filas, la última 20261010130000_add_late_fee_waiver
```

4. Verificar tabla:

```sql
SELECT to_regclass('"LateFeeWaiver"') IS NOT NULL AS existe;
SELECT count(*) FROM "LateFeeWaiver";   -- 0 al desplegar
```

5. Arranque del backend: `/system/status` responde; los logs no muestran errores de Prisma.
6. Distribuir el instalador de Windows actualizado.

## 8. Condonación de Carlos (procedimiento)

Ventas:

- `da1018c4-968a-47c9-ae94-d9ada1b037f0`
- `0098d093-7bdd-418c-b176-816d692653e3`

**Nunca** usar montos fijos históricos: recalcular al instante real del corte.

```bash
# 1) Estado autoritativo de la venta (sólo lectura). Devuelve bruto/cobrado/condonado/exigible.
curl -sS "$API/authoritative/sales/<SALE_ID>/late-fee-summary?asOfDate=<CUTOFF_ISO>" \
  -H "authorization: Bearer <TOKEN_OWNER>"

# 2) Registrar la condonación. El backend recalcula el monto.
curl -sS -X POST "$API/authoritative/sales/<SALE_ID>/late-fee-waiver" \
  -H "authorization: Bearer <TOKEN_OWNER>" \
  -H "content-type: application/json" \
  -H "idempotency-key: carlos-waiver-<SALE_ID>-<CUTOFF_YYYYMMDD>" \
  -d '{"cutoffAt":"<CUTOFF_ISO>","confirmSaleSyncId":"<SALE_SYNC_ID>","reason":"Condonacion aprobada por el propietario"}'

# 3) Verificar que el exigible quedó en 0 al corte y que la mora posterior sigue acumulando.
curl -sS "$API/authoritative/sales/<SALE_ID>/late-fee-summary?asOfDate=<CUTOFF_ISO>" -H "authorization: Bearer <TOKEN_OWNER>"
curl -sS "$API/authoritative/sales/<SALE_ID>/late-fee-summary?asOfDate=<CUTOFF_PLUS_2D>" -H "authorization: Bearer <TOKEN_OWNER>"
```

Verificaciones de integridad (deben permanecer sin cambios): `Payment`,
`PaymentReceipt`, `Sale.principal/financedBalance`, cuotas ya pagadas.

## 9. Smoke tests post-despliegue

1. `GET /system/status` → 200.
2. `GET /authoritative/sales/<sale>/late-fee-summary` → 200 y totales coherentes.
3. `POST .../late-fee-waiver` con usuario **no** OWNER → **403**.
4. Repetir el mismo `idempotency-key` → 200 `idempotentReplay: true`, sin fila nueva.
5. Cotización de liquidación de una venta sin condonación → `lateFees > 0` y
   `settlementAmount = principal + interés + mora`.
6. Registrar un pago → `lateFeeApplied` igual al exigible, nunca superior.
7. Reconciliación: `financedBalance − Σ principalApplied = balance`.

## 10. Autorizaciones requeridas antes de producción

1. Migración `20261010130000_add_late_fee_waiver`.
2. Despliegue del backend.
3. Distribución del instalador de Windows.
4. **Cambio de comportamiento de liquidación** (ahora cobra mora exigible).
5. Corte exacto y monto recalculado de la condonación de Carlos.

## 11. Rollback

1. Restaurar imagen anterior del backend (tag previo). La tabla `LateFeeWaiver`
   queda inerte: el código anterior no la consulta.
2. Si se desea revertir el esquema: `DROP TABLE "LateFeeWaiver";` y eliminar la
   fila de `_prisma_migrations` correspondiente. **Sólo** si aún no hay
   condonaciones reales registradas.
3. Si ya se registraron condonaciones, restaurar desde el dump: `pg_restore`
   selectivo de `LateFeeWaiver` no aplica; usar el dump completo en una ventana
   de mantenimiento.
4. Revertir el cliente Windows al instalador anterior sólo si el backend también
   revierte (ver §4).
