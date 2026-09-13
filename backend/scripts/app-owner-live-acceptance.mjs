import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { PrismaClient } from "@prisma/client";
import bcrypt from "bcryptjs";

const BASE_URL = process.env.ACCEPTANCE_BASE_URL ?? "http://127.0.0.1:3000";
const prisma = new PrismaClient();
const results = [];

function record(name, passed, detail = "") {
  results.push({ name, passed: Boolean(passed), detail });
  console.log(
    `${passed ? "PASS" : "FAIL"} ${name}${detail ? ` ${detail}` : ""}`,
  );
}

function password() {
  return `Aa1!${randomBytes(18).toString("base64url")}`;
}

async function request(method, path, { token, body, headers = {} } = {}) {
  const response = await fetch(`${BASE_URL}${path}`, {
    method,
    headers: {
      accept: "application/json",
      ...(body ? { "content-type": "application/json" } : {}),
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...headers,
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await response.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    json = { raw: text };
  }
  return { status: response.status, json };
}

async function login(email, pass) {
  const response = await request("POST", "/api/auth/login", {
    body: { email, password: pass },
  });
  assert.equal(response.status, 200, `login failed for ${email}`);
  return response.json.data.accessToken;
}

async function main() {
  const status = await request("GET", "/api/system/status");
  record("acceptance_backend_health", status.status === 200);
  record(
    "acceptance_database",
    status.json?.databaseName === "altomamita_manual_acceptance",
    status.json?.databaseName,
  );
  if (status.json?.databaseName !== "altomamita_manual_acceptance") {
    throw new Error("Refusing to mutate non-acceptance database.");
  }

  const company = await prisma.company.findUnique({
    where: { tenantKey: status.json.tenantKey },
  });
  assert(company, "company not found");

  const run = Date.now().toString();
  const adminEmail = `acceptance.appowner.admin.${run}@sistema.local`;
  const customerAEmail = `acceptance.customer.a.${run}@sistema.local`;
  const customerBEmail = `acceptance.customer.b.${run}@sistema.local`;
  const adminPass = password();
  const passA = password();
  const passB = password();
  const clientASync = `acceptance-customer-a-${run}`;
  const clientBSync = `acceptance-customer-b-${run}`;
  const lotASync = `acceptance-lot-a-${run}`;
  const lotBSync = `acceptance-lot-b-${run}`;
  const sellerSync = `acceptance-seller-${run}`;

  const [clientA, clientB, lotA, lotB, seller] = await Promise.all([
    prisma.client.create({
      data: {
        companyId: company.id,
        syncId: clientASync,
        name: "ACCEPTANCE-CUSTOMER-A",
        document: `ACA-${run}`,
        phone: "8090000001",
        address: "Acceptance A",
        raw: { acceptanceRun: run },
      },
    }),
    prisma.client.create({
      data: {
        companyId: company.id,
        syncId: clientBSync,
        name: "ACCEPTANCE-CUSTOMER-B",
        document: `ACB-${run}`,
        phone: "8090000002",
        address: "Acceptance B",
        raw: { acceptanceRun: run },
      },
    }),
    prisma.lot.create({
      data: {
        companyId: company.id,
        syncId: lotASync,
        block: "A",
        number: `MOB-${run.slice(-5)}A`,
        status: "disponible",
        area: "200",
        price: "1000",
        raw: { acceptanceRun: run },
      },
    }),
    prisma.lot.create({
      data: {
        companyId: company.id,
        syncId: lotBSync,
        block: "B",
        number: `MOB-${run.slice(-5)}B`,
        status: "disponible",
        area: "210",
        price: "1000",
        raw: { acceptanceRun: run },
      },
    }),
    prisma.seller.create({
      data: {
        companyId: company.id,
        syncId: sellerSync,
        name: `ACCEPTANCE SELLER ${run}`,
        document: `ACS-${run}`,
        phone: "8090000003",
        raw: { acceptanceRun: run },
      },
    }),
  ]);

  await Promise.all([
    prisma.user.create({
      data: {
        companyId: company.id,
        email: adminEmail,
        name: `ACCEPTANCE APP OWNER ADMIN ${run}`,
        role: "OWNER",
        active: true,
        passwordHash: await bcrypt.hash(adminPass, 10),
        raw: { acceptanceRun: run },
      },
    }),
    prisma.user.create({
      data: {
        companyId: company.id,
        email: customerAEmail,
        name: "ACCEPTANCE-CUSTOMER-A",
        role: "TECH",
        active: true,
        passwordHash: await bcrypt.hash(passA, 10),
        authSource: "customer",
        remoteAuthId: clientASync,
        raw: { acceptanceRun: run, customerClientSyncId: clientASync },
      },
    }),
    prisma.user.create({
      data: {
        companyId: company.id,
        email: customerBEmail,
        name: "ACCEPTANCE-CUSTOMER-B",
        role: "TECH",
        active: true,
        passwordHash: await bcrypt.hash(passB, 10),
        authSource: "customer",
        remoteAuthId: clientBSync,
        raw: { acceptanceRun: run, customerClientSyncId: clientBSync },
      },
    }),
  ]);
  record("acceptance_customer_users_provisioned", true, `run=${run}`);

  const adminToken = await login(adminEmail, adminPass);
  const saleAResponse = await request("POST", "/api/authoritative/sales", {
    token: adminToken,
    headers: { "idempotency-key": `acceptance-sale-a-${run}` },
    body: {
      clientSyncId: clientASync,
      lotSyncId: lotASync,
      sellerSyncId: sellerSync,
      salePrice: 200000,
      downPaymentPercentage: 10,
      initialPaymentPaid: 20000,
      monthlyInterest: 1,
      installmentCount: 6,
      reference: `ACCEPTANCE-SALE-A-${run}`,
    },
  });
  const saleBResponse = await request("POST", "/api/authoritative/sales", {
    token: adminToken,
    headers: { "idempotency-key": `acceptance-sale-b-${run}` },
    body: {
      clientSyncId: clientBSync,
      lotSyncId: lotBSync,
      sellerSyncId: sellerSync,
      salePrice: 210000,
      downPaymentPercentage: 10,
      initialPaymentPaid: 21000,
      monthlyInterest: 1,
      installmentCount: 6,
      reference: `ACCEPTANCE-SALE-B-${run}`,
    },
  });
  record("sale_a_created_by_backend", saleAResponse.status === 201);
  record("sale_b_created_by_backend", saleBResponse.status === 201);
  const saleAId = saleAResponse.json?.data?.saleId;
  const saleBId = saleBResponse.json?.data?.saleId;
  assert(saleAId && saleBId, "sale ids missing");

  const tokenA = await login(customerAEmail, passA);
  const tokenB = await login(customerBEmail, passB);
  record("customer_a_login", true);
  record("customer_b_login", true);

  const [meA, meB, snapshotA, snapshotB] = await Promise.all([
    request("GET", "/api/customer/me", { token: tokenA }),
    request("GET", "/api/customer/me", { token: tokenB }),
    request("GET", "/api/customer/snapshot", { token: tokenA }),
    request("GET", "/api/customer/snapshot", { token: tokenB }),
  ]);

  record("customer_a_me", meA.json?.data?.client?.syncId === clientASync);
  record("customer_b_me", meB.json?.data?.client?.syncId === clientBSync);
  const aData = snapshotA.json?.data;
  const bData = snapshotB.json?.data;
  record("customer_a_scope", onlyHasClient(aData, clientASync, clientBSync));
  record("customer_b_scope", onlyHasClient(bData, clientBSync, clientASync));
  record(
    "project_lot",
    aData?.lots?.[0]?.id === lotA.id && bData?.lots?.[0]?.id === lotB.id,
  );
  record(
    "sale",
    aData?.sales?.[0]?.id === saleAId && bData?.sales?.[0]?.id === saleBId,
  );
  record(
    "installments",
    aData?.installments?.length === 6 && bData?.installments?.length === 6,
  );
  record("balance", Number(aData?.dashboard?.totals?.balance) > 0);

  const installmentBId = bData.installments[0].id;
  const lotBCross = await request("GET", `/api/customer/lots/${lotB.id}`, {
    token: tokenA,
  });
  const saleBCross = await request("GET", `/api/customer/sales/${saleBId}`, {
    token: tokenA,
  });
  const installmentBCross = await request(
    "GET",
    `/api/customer/installments/${installmentBId}`,
    {
      token: tokenA,
    },
  );
  record("cross_customer_lot_blocked", lotBCross.status === 404);
  record("cross_customer_sale_blocked", saleBCross.status === 404);
  record(
    "cross_customer_installment_blocked",
    installmentBCross.status === 404,
  );

  const editedAddress = `Acceptance A edited ${run}`;
  const projectEdit = await request(
    "PATCH",
    `/api/business/clients/${clientA.id}`,
    {
      token: adminToken,
      body: { address: editedAddress },
    },
  );
  record(
    "project_edit_by_backend",
    projectEdit.status === 200,
    projectEdit.json?.error?.code ?? "",
  );
  record(
    "project_edit_live_update_snapshot",
    (await request("GET", "/api/customer/snapshot", { token: tokenA })).json
      .data.clients[0].address === editedAddress,
  );

  const baselineBalance = Number(aData.dashboard.totals.balance);
  const baselinePayments = aData.payments.length;
  const firstInstallment = aData.installments[0];
  const paymentAmount = Number(firstInstallment.amount);
  const payment = await request("POST", "/api/authoritative/payments", {
    token: adminToken,
    headers: { "idempotency-key": `acceptance-payment-a-${run}` },
    body: {
      saleId: saleAId,
      amountPaid: paymentAmount,
      paymentMethod: "efectivo",
      paymentType: "cuota",
      targetInstallmentId: firstInstallment.id,
      reference: `ACCEPTANCE-PAYMENT-A-${run}`,
    },
  });
  record("payment_created_by_backend", payment.status === 201);
  const paymentId = payment.json?.data?.paymentIds?.[0];
  const afterPayment = (
    await request("GET", "/api/customer/snapshot", { token: tokenA })
  ).json.data;
  record(
    "payment_live_update_snapshot",
    afterPayment.payments.length === baselinePayments + 1,
  );
  record(
    "balance_updated_after_payment",
    Number(afterPayment.dashboard.totals.balance) < baselineBalance,
  );
  record(
    "installment_updated_after_payment",
    afterPayment.installments[0].status === "pagada" ||
      Number(afterPayment.installments[0].paidAmount) >
        Number(firstInstallment.paidAmount),
  );
  const paymentBCross = await request(
    "GET",
    `/api/customer/payments/${paymentId}`,
    { token: tokenB },
  );
  record("cross_customer_payment_blocked", paymentBCross.status === 404);

  const annul = await request(
    "POST",
    `/api/authoritative/payments/${paymentId}/annul`,
    {
      token: adminToken,
      headers: { "idempotency-key": `acceptance-payment-annul-a-${run}` },
      body: { reason: "app_owner acceptance rollback of test payment" },
    },
  );
  record("payment_annulled_by_backend", annul.status === 201);
  const afterAnnul = (
    await request("GET", "/api/customer/snapshot", { token: tokenA })
  ).json.data;
  record(
    "annulment_reflected",
    afterAnnul.payments.length === baselinePayments,
  );

  const invalidMe = await request("GET", "/api/customer/me", {
    token: `${tokenA}x`,
  });
  record("invalid_token_rejected", invalidMe.status === 401);

  const failed = results.filter((result) => !result.passed);
  console.log(
    `SUMMARY ${results.length - failed.length}/${results.length} passed`,
  );
  console.log(
    JSON.stringify({
      run,
      customerAEmail,
      customerBEmail,
      saleAId,
      saleBId,
      lotAId: lotA.id,
      lotBId: lotB.id,
      paymentId,
      failed: failed.map((item) => item.name),
    }),
  );
  if (failed.length > 0) process.exitCode = 1;
}

function onlyHasClient(snapshot, ownSyncId, otherSyncId) {
  const raw = JSON.stringify(snapshot);
  return (
    snapshot?.clients?.length === 1 &&
    raw.includes(ownSyncId) &&
    !raw.includes(otherSyncId)
  );
}

main()
  .catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
