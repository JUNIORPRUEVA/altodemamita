select (select count(*) from "Client") as clientes, (select count(*) from "Sale") as ventas, (select count(*) from "Payment") as pagos, (select count(*) from "Lot") as solares;
select count(*) as ventas_borradas from "Sale" where "deletedAt" is not null;
