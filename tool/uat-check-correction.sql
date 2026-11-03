-- Cronograma vigente vs historico de la venta UAT 01.
select
  i."installmentNumber" as cuota,
  i."totalAmount"       as monto,
  i."principalAmount"   as capital,
  i."paidAmount"        as pagado,
  i."status",
  (i."deletedAt" is not null) as historico
from "Installment" i
where i."saleSyncId" = 'uat-fixture-sale'
order by i."installmentNumber", i."deletedAt" nulls first;

select key, value
from "SyncSetting"
limit 1;

-- Invariante sobre el cronograma VIGENTE.
select
  s."balance" as saldo_venta,
  (
    select coalesce(sum(i."principalAmount" - i."paidPrincipalAmount"), 0)
    from "Installment" i
    where i."saleSyncId" = s."syncId" and i."deletedAt" is null
  ) as capital_pendiente_vigente
from "Sale" s
where s."syncId" = 'uat-fixture-sale';
