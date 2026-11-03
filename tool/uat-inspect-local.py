import sqlite3

db = r"C:\src\ss-uat-profile\SistemaSolares\data\database\sistema_solares.db"
con = sqlite3.connect(db)
cur = con.cursor()

print("== venta ==")
for row in cur.execute(
    "select id, sync_id, saldo_pendiente, estado, fecha_venta from ventas where sync_id='uat-fixture-sale'"
):
    print(row)

print("== cuotas ==")
for row in cur.execute(
    """
    select numero_cuota, monto_cuota, monto_pagado, capital_pagado, estado, sync_id
    from cuotas
    where venta_id = (select id from ventas where sync_id='uat-fixture-sale')
    order by numero_cuota
    """
):
    print(row)

print("== pagos de la venta ==")
for row in cur.execute(
    """
    select id, sync_id, monto_pagado, tipo_pago, deleted_at, cuota_id
    from pagos
    where venta_id = (select id from ventas where sync_id='uat-fixture-sale')
    """
):
    print(row)

print("== total pagos locales ==")
print(cur.execute("select count(*) from pagos").fetchone())

print("== ultimos sync_status de pagos ==")
for row in cur.execute("select sync_status, count(*) from pagos group by sync_status"):
    print(row)

con.close()
