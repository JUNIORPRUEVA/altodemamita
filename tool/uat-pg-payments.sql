select count(*) as total_payments from "Payment";
select p."syncId", p.amount, p."principalApplied", p."interestApplied", p."lateFeeApplied",
       p."paymentType", p."clientId", c."syncId" as client_sync, p."installmentId", p."annulledAt"
from "Payment" p
join "Sale" s on s.id = p."saleId"
left join "Client" c on c.id = p."clientId"
where s."syncId" = 'uat-fixture-sale';
