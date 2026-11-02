import assert from "node:assert/strict";
import test from "node:test";
import {
  isEntityAdminAction,
  normalizeIdentifier,
  validateClientIdentity,
  validateLotDetails,
  validateManualLotStatus,
} from "./entityAdmin.service";

/** FASE 04 — reglas puras de la administracion de clientes y solares. */
test("separa las acciones validas de cliente y de solar", () => {
  assert.equal(isEntityAdminAction("client", "merge_duplicates"), true);
  assert.equal(isEntityAdminAction("client", "update_identity"), true);
  assert.equal(isEntityAdminAction("client", "update_status"), false);
  assert.equal(isEntityAdminAction("lot", "update_status"), true);
  assert.equal(isEntityAdminAction("lot", "merge_duplicates"), false);
  assert.equal(isEntityAdminAction("lot", "delete_forever"), false);
});

test("normaliza identificadores de solar", () => {
  assert.equal(normalizeIdentifier("  a -  01 "), "A - 01");
  assert.equal(normalizeIdentifier(null), "");
});

test("valida la identidad minima del cliente", () => {
  assert.equal(validateClientIdentity({ name: "Ana Perez", document: "" }), null);
  assert.equal(
    validateClientIdentity({ name: "Al", document: "" })?.code,
    "INVALID_CLIENT_NAME",
  );
});

test("valida los datos del solar", () => {
  assert.equal(
    validateLotDetails({ block: "A", number: "01", area: 120, price: 500000 }),
    null,
  );
  assert.equal(
    validateLotDetails({ block: "", number: "01", area: 120, price: 1 })?.code,
    "INVALID_LOT_IDENTIFIER",
  );
  assert.equal(
    validateLotDetails({ block: "A", number: "01", area: 0, price: 1 })?.code,
    "INVALID_LOT_AREA",
  );
  assert.equal(
    validateLotDetails({ block: "A", number: "01", area: 10, price: -1 })?.code,
    "INVALID_LOT_PRICE",
  );
});

test("el estado del solar respeta la venta activa y no fija 'vendido'", () => {
  assert.equal(
    validateManualLotStatus({ status: "bloqueado", hasActiveSale: false }),
    null,
  );
  assert.equal(
    validateManualLotStatus({ status: "vendido", hasActiveSale: true })?.code,
    "LOT_SOLD_STATUS_MANUAL",
  );
  assert.equal(
    validateManualLotStatus({ status: "inactivo", hasActiveSale: false })?.code,
    "LOT_STATUS_UNSUPPORTED",
  );
  assert.equal(
    validateManualLotStatus({ status: "disponible", hasActiveSale: true })?.code,
    "LOT_HAS_ACTIVE_SALE",
  );
  assert.equal(
    validateManualLotStatus({ status: "disponible", hasActiveSale: false }),
    null,
  );
});
