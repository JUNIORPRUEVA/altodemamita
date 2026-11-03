"""Compara el identificador local de la venta con el del backend.

La app envia `ventas.sync_id` a los endpoints /authoritative/sales/:id/...
que el backend resuelve por `Sale.id`. Si ambos valores no coinciden, el
editor de contrato falla con "La venta seleccionada no existe".
"""
import sqlite3

DB = r"C:\src\ss-uat-profile\SistemaSolares\data\database\sistema_solares.db"

con = sqlite3.connect(DB)
cur = con.cursor()

print("== ventas locales ==")
for row in cur.execute(
    "select sync_id, saldo_pendiente, estado from ventas order by sync_id"
):
    print("  sync_id=%s saldo=%s estado=%s" % row)
