// Verificación SOLO-LECTURA de una venta contra ACCEPTANCE (nunca producción).
// Uso (en un terminal donde ya esté configurada la contraseña de aceptación):
//   node backend/scripts/acceptance-sale-detail-inspect.mjs
// Variables opcionales: ACCEPTANCE_BASE_URL, SALE_SYNC_ID, SALE_REMOTE_ID,
//   ACCEPTANCE_ADMIN_EMAIL, ACCEPTANCE_ADMIN_PASSWORD.
const BASE_URL = process.env.ACCEPTANCE_BASE_URL ?? 'http://127.0.0.1:3302';
const SALE_SYNC_ID =
  process.env.SALE_SYNC_ID ?? 'sale-26287bd6-9c2e-4d2c-bd79-aec71e4554c2';
const SALE_REMOTE_ID =
  process.env.SALE_REMOTE_ID ?? 'cf5dc12a-79b1-4cb3-8dd9-52bcd22332ad';
const ADMIN_EMAIL = process.env.ACCEPTANCE_ADMIN_EMAIL ?? 'admin@sistema.local';
const ADMIN_PASSWORD = process.env.ACCEPTANCE_ADMIN_PASSWORD ?? '';

if (!ADMIN_PASSWORD) {
  throw new Error('ACCEPTANCE_ADMIN_PASSWORD es requerida (solo lectura, acceptance).');
}

async function request(path, { method = 'GET', token, body } = {}) {
  const headers = { Accept: 'application/json' };
  if (token) headers.Authorization = `Bearer ${token}`;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const response = await fetch(`${BASE_URL}${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  let json = null;
  if (text) {
    try {
      json = JSON.parse(text);
    } catch {
      json = { rawText: text.slice(0, 300) };
    }
  }
  return { status: response.status, ok: response.ok, json };
}

function dataOf(payload) {
  return payload?.data ?? payload ?? {};
}

async function main() {
  // 1) Confirmar que el backend de aceptación es el correcto.
  const status = await request('/api/system/status');
  console.log('SYSTEM STATUS:', status.status, JSON.stringify(status.json ?? {}));
  if (status.json?.databaseName && status.json.databaseName !== 'altomamita_manual_acceptance') {
    throw new Error(`NO es acceptance: databaseName=${status.json.databaseName}`);
  }

  // 2) Login (solo lectura posterior).
  const login = await request('/api/auth/login', {
    method: 'POST',
    body: { email: ADMIN_EMAIL, password: ADMIN_PASSWORD },
  });
  if (!login.ok || !login.json?.data?.token) {
    console.log('LOGIN ERROR', login.status, JSON.stringify(login.json ?? {}));
    process.exitCode = 2;
    return;
  }
  const token = login.json.data.token;

  // 3) Localizar la venta en el listado (autoridad PG vía API).
  let found = null;
  for (let page = 1; page <= 20 && !found; page++) {
    const list = await request(`/api/owner/sales?page=${page}&pageSize=200`, { token });
    const items = (list.json?.data?.items ?? []) || [];
    for (const item of items) {
      if (
        String(item?.id) === SALE_REMOTE_ID ||
        String(item?.syncId) === SALE_SYNC_ID ||
        String(item?.saleId) === SALE_REMOTE_ID
      ) {
        found = item;
        break;
      }
    }
  }
  if (!found) {
    console.log('SALE EN LISTADO PG: NO ENCONTRADA por syncId/id en /api/owner/sales');
  } else {
    console.log('SALE EN LISTADO PG (row):');
    console.log(
      JSON.stringify(
        {
          id: found.id,
          saleId: found.saleId,
          syncId: found.syncId,
          status: found.status,
          total: found.total,
          initialPaid: found.initialPaid,
          initialRequiredAmount: found.initialRequiredAmount,
          financedBalance: found.financedBalance,
          balance: found.balance,
          monthlyInterestRate: found.monthlyInterestRate,
          installmentCount: found.installmentCount,
          lot: found.lot,
          client: found.client,
        },
        null,
        2,
      ),
    );
  }

  // 4) Detalle dedicado (incluye installments desde PG). Post-despliegue.
  const detail = await request(`/api/owner/sales/${SALE_REMOTE_ID}`, { token });
  console.log(`DETAIL /api/owner/sales/${SALE_REMOTE_ID}: HTTP ${detail.status}`);
  const sale = detail.json?.data?.sale;
  if (detail.status === 404 || !sale) {
    console.log('DETAIL: endpoint de detalle aún no desplegado en acceptance (esperado 404 pre-despliegue).');
  } else {
    const installments = Array.isArray(sale.installments) ? sale.installments : [];
    const payments = Array.isArray(sale.payments) ? sale.payments : [];
    const sum = (key) =>
      installments.reduce((acc, item) => acc + Number(item[key] ?? 0), 0);
    console.log(
      JSON.stringify(
        {
          id: sale.id,
          syncId: sale.syncId,
          status: sale.status,
          total: sale.total,
          initialPaid: sale.initialPaid,
          balance: sale.balance,
          installmentCount: sale.installmentCount,
          installmentsCount: installments.length,
          capitalTotal: sum('principalAmount'),
          interestTotal: sum('interestAmount'),
          planTotal: sum('amount'),
          paidToDate: sum('paidAmount'),
          firstInstallment: installments[0] ?? null,
          lastInstallment: installments[installments.length - 1] ?? null,
          initialPayments: payments.map((p) => ({ method: p.method, amount: p.amount })),
        },
        null,
        2,
      ),
    );
  }
}

main().catch((error) => {
  console.error(error?.message ?? error);
  process.exitCode = 1;
});
