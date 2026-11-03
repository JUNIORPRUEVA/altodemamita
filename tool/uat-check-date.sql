-- Verifica el cambio de fecha aplicado desde la app (25/08/2026).
select
  p."amount",
  p."paidAt"::date          as fecha_efectiva,
  p."createdAt"::date       as fecha_creacion,
  (p."annulledAt" is not null) as anulado
from "Payment" p
where p."saleSyncId" = 'uat-fixture-sale'
order by p."createdAt";

-- La correccion debe dejar rastro con el motivo.
select
  left(e."action", 40)  as accion,
  left(e."reason", 40)  as motivo,
  e."createdAt"::timestamp(0) as cuando
from "AuditLog" e
where e."entityId" in ('uat-fixture-sale')
   or e."entityId" like '%uat-fixture-sale%'
order by e."createdAt" desc
limit 5;
