-- Condonaciones de mora registradas desde la app.
select
  "saleSyncId",
  "calculatedFee"  as mora_calculada,
  "waivedAmount"   as mora_condonada,
  left(coalesce("reason", ''), 40) as motivo,
  "appliedAt"::timestamp(0) as cuando
from "LateFeeWaiver"
order by "appliedAt" desc
limit 5;

-- Mora acumulada por cuota en la venta UAT 05.
select
  "installmentSyncId",
  sum("calculatedLateFee") as mora_calculada,
  count(*) as eventos
from "LateFeeSnapshot"
where "saleSyncId" = 'uat-fixture-sale-parciales'
group by "installmentSyncId";
