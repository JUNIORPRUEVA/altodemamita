select (select count(*) from "Client") as clientes, (select count(*) from "Sale") as ventas, (select count(*) from "Payment") as pagos, (select count(*) from "Installment") as cuotas, (select count(*) from "Lot") as solares;
select c.name, s."syncId" as venta, s.status, s.balance, s."initialPaid", s."initialPendingAmount", s."installmentCount",
       (select count(*) from "Payment" p where p."saleId"=s.id and p."annulledAt" is null) as pagos_activos,
       (select count(*) from "Payment" p where p."saleId"=s.id and p."annulledAt" is not null) as pagos_anulados
from "Client" c left join "Sale" s on s."clientId"=c.id
order by c.name;
