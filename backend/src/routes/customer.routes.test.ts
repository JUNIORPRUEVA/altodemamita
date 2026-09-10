import assert from "node:assert/strict";
import test from "node:test";
import { extractCustomerClientSyncId } from "./customer.routes";

test("extractCustomerClientSyncId requires server-side customer linkage metadata", () => {
  assert.equal(
    extractCustomerClientSyncId({
      raw: { customerClientSyncId: "client-a" },
      authSource: null,
      remoteAuthId: null,
    }),
    "client-a",
  );
  assert.equal(
    extractCustomerClientSyncId({
      raw: { customer: { syncId: "client-b" } },
      authSource: null,
      remoteAuthId: null,
    }),
    "client-b",
  );
});

test("extractCustomerClientSyncId does not trust ordinary remote auth ids", () => {
  assert.equal(
    extractCustomerClientSyncId({
      raw: {},
      authSource: "desktop",
      remoteAuthId: "client-b",
    }),
    null,
  );
  assert.equal(
    extractCustomerClientSyncId({
      raw: {},
      authSource: "customer",
      remoteAuthId: "client-c",
    }),
    "client-c",
  );
});
