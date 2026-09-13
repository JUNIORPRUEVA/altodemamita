const ACCEPTANCE_BASE_URL = process.env.ACCEPTANCE_BASE_URL ?? 'http://127.0.0.1:3302';
const PRODUCTION_BASE_URL = process.env.PRODUCTION_BASE_URL ?? '';
const ADMIN_EMAIL = process.env.ACCEPTANCE_ADMIN_EMAIL ?? 'admin@sistema.local';
const ADMIN_PASSWORD = process.env.ACCEPTANCE_ADMIN_PASSWORD ?? '';

const productionExpectedHistorical = {
  clients: 90,
  sellers: 26,
  lots: 135,
  sales: 135,
  installments: 15864,
  payments: 889,
};

const productionExpectedActive = {
  clients: 81,
  sellers: 22,
  lots: 103,
  sales: 103,
  installments: 12252,
  payments: 786,
};

const scopeToPath = {
  clients: '/api/owner/clients',
  sellers: '/api/owner/sellers',
  lots: '/api/owner/lots',
  sales: '/api/owner/sales',
  installments: '/api/owner/installments',
  payments: '/api/owner/payments',
};

const result = {
  checks: {},
  metrics: {},
  failures: [],
  endpoints: new Map(),
  productionMethods: [],
};

function fail(name, detail) {
  result.failures.push({ name, detail });
  result.checks[name] = false;
}

function pass(name, detail = true) {
  result.checks[name] = detail;
}

function assertCheck(name, condition, detail) {
  if (condition) pass(name, detail ?? true);
  else fail(name, detail ?? 'failed');
}

function id(prefix) {
  return `${prefix}-${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

async function request(baseUrl, method, path, { token, body, idempotencyKey, production = false } = {}) {
  if (production) {
    result.productionMethods.push(method);
    if (method !== 'GET') {
      throw new Error(`Production write blocked by probe: ${method} ${path}`);
    }
  }
  const headers = { Accept: 'application/json' };
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  if (token) headers.Authorization = `Bearer ${token}`;
  if (idempotencyKey) headers['Idempotency-Key'] = idempotencyKey;
  const response = await fetch(`${baseUrl}${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  result.endpoints.set(`${method} ${path.split('?')[0]}`, response.status);
  let json = null;
  const text = await response.text();
  if (text) {
    try {
      json = JSON.parse(text);
    } catch {
      json = { rawText: text.slice(0, 500) };
    }
  }
  return { status: response.status, ok: response.ok, json };
}

function dataArray(payload) {
  if (Array.isArray(payload)) return payload;
  if (Array.isArray(payload?.data)) return payload.data;
  if (Array.isArray(payload?.data?.items)) return payload.data.items;
  if (Array.isArray(payload?.users)) return payload.users;
  if (Array.isArray(payload?.data?.users)) return payload.data.users;
  return [];
}

function userRole(user) {
  return String(user?.role ?? user?.rol ?? '').toUpperCase();
}

function userActive(user) {
  if (typeof user?.active === 'boolean') return user.active;
  if (typeof user?.activo === 'boolean') return user.activo;
  if (typeof user?.isActive === 'boolean') return user.isActive;
  return false;
}

async function countOwner(baseUrl, scope, includeDeleted, token, production = false) {
  const path = `${scopeToPath[scope]}?pageSize=1&includeDeleted=${includeDeleted ? 'true' : 'false'}`;
  const response = await request(baseUrl, 'GET', path, { token, production });
  if (!response.ok) return { status: response.status, total: null };
  return { status: response.status, total: Number(response.json?.data?.total ?? NaN) };
}

async function ownerCounts(baseUrl, token, includeDeleted, production = false) {
  const entries = await Promise.all(
    Object.keys(scopeToPath).map(async (scope) => [scope, await countOwner(baseUrl, scope, includeDeleted, token, production)]),
  );
  return Object.fromEntries(entries.map(([scope, item]) => [scope, item.total]));
}

function compareCounts(actual, expected) {
  return Object.entries(expected).every(([scope, value]) => actual[scope] === value);
}

async function syncUpload(token, records) {
  return request(ACCEPTANCE_BASE_URL, 'POST', '/api/sync/upload', {
    token,
    body: { device_id: 'acceptance-final-probe', records },
  });
}

async function syncDownload(token) {
  return request(ACCEPTANCE_BASE_URL, 'GET', '/api/sync/download', { token });
}

function findSync(records, scope, syncId) {
  return (records?.[scope] ?? []).find((row) => row.sync_id === syncId || row.syncId === syncId);
}

async function main() {
  if (!ADMIN_PASSWORD) {
    throw new Error('ACCEPTANCE_ADMIN_PASSWORD is required');
  }

  const status = await request(ACCEPTANCE_BASE_URL, 'GET', '/api/system/status');
  assertCheck(
    'acceptance_database',
    status.json?.databaseName === 'altomamita_manual_acceptance',
    status.json?.databaseName,
  );

  const login = await request(ACCEPTANCE_BASE_URL, 'POST', '/api/auth/login', {
    body: { email: ADMIN_EMAIL, password: ADMIN_PASSWORD },
  });
  assertCheck('auth_login_http', login.status === 200, login.status);
  const token = login.json?.accessToken ?? login.json?.data?.accessToken ?? login.json?.token ?? login.json?.data?.token;
  const currentUser = login.json?.user ?? login.json?.data?.user;
  assertCheck('auth_owner_role', userRole(currentUser) === 'OWNER', userRole(currentUser));
  assertCheck('auth_token_present_redacted', typeof token === 'string' && token.length > 10, 'present');
  if (!token) throw new Error('Login succeeded but did not return an access token');

  const me = await request(ACCEPTANCE_BASE_URL, 'GET', '/api/auth/me', { token });
  assertCheck('auth_me_http', me.status === 200, me.status);
  assertCheck('auth_me_owner_role', userRole(me.json?.user ?? me.json?.data?.user) === 'OWNER', userRole(me.json?.user ?? me.json?.data?.user));

  const usersBefore = await request(ACCEPTANCE_BASE_URL, 'GET', '/api/business/users', { token });
  assertCheck('users_get_http', usersBefore.status === 200, usersBefore.status);
  const beforeUsers = dataArray(usersBefore.json);
  result.metrics.usersBefore = beforeUsers.length;
  assertCheck('users_owner_can_read', beforeUsers.length > 0, beforeUsers.length);

  const userSuffix = id('user');
  const testEmail = `${userSuffix}@sistema.local`;
  const testPassword = id('pw');
  const createUser = await request(ACCEPTANCE_BASE_URL, 'POST', '/api/business/users', {
    token,
    body: { name: `ACCEPTANCE AUTO ${userSuffix}`, email: testEmail, role: 'TECH', password: testPassword, active: true },
  });
  assertCheck('users_post_http', [200, 201].includes(createUser.status), createUser.status);
  const createdUser = createUser.json?.user ?? createUser.json?.data?.user ?? createUser.json?.data ?? createUser.json;
  const createdUserId = createdUser?.id ?? createdUser?.userId;
  assertCheck('users_created_has_id', Boolean(createdUserId), createdUserId ? 'present' : 'missing');

  const patchName = await request(ACCEPTANCE_BASE_URL, 'PATCH', `/api/business/users/${createdUserId}`, {
    token,
    body: { name: `ACCEPTANCE AUTO EDIT ${userSuffix}` },
  });
  assertCheck('users_patch_edit_http', patchName.status === 200, patchName.status);

  const patchOwner = await request(ACCEPTANCE_BASE_URL, 'PATCH', `/api/business/users/${createdUserId}`, {
    token,
    body: { role: 'OWNER' },
  });
  assertCheck('users_patch_role_owner_http', patchOwner.status === 200, patchOwner.status);
  const patchTech = await request(ACCEPTANCE_BASE_URL, 'PATCH', `/api/business/users/${createdUserId}`, {
    token,
    body: { role: 'TECH' },
  });
  assertCheck('users_patch_role_tech_http', patchTech.status === 200, patchTech.status);

  const selfDeactivate = await request(ACCEPTANCE_BASE_URL, 'PATCH', `/api/business/users/${currentUser.id}`, {
    token,
    body: { active: false },
  });
  assertCheck('users_self_deactivate_blocked', selfDeactivate.status === 409, selfDeactivate.status);

  const disableUser = await request(ACCEPTANCE_BASE_URL, 'PATCH', `/api/business/users/${createdUserId}`, {
    token,
    body: { active: false },
  });
  assertCheck('users_disable_http', disableUser.status === 200, disableUser.status);

  const disabledLogin = await request(ACCEPTANCE_BASE_URL, 'POST', '/api/auth/login', {
    body: { email: testEmail, password: testPassword },
  });
  assertCheck('users_disabled_login_blocked', [401, 403].includes(disabledLogin.status), disabledLogin.status);

  const reactivateUser = await request(ACCEPTANCE_BASE_URL, 'PATCH', `/api/business/users/${createdUserId}`, {
    token,
    body: { active: true },
  });
  assertCheck('users_reactivate_http', reactivateUser.status === 200, reactivateUser.status);

  const techLogin = await request(ACCEPTANCE_BASE_URL, 'POST', '/api/auth/login', {
    body: { email: testEmail, password: testPassword },
  });
  assertCheck('rbac_tech_login_http', techLogin.status === 200, techLogin.status);
  const techToken = techLogin.json?.accessToken ?? techLogin.json?.data?.accessToken ?? techLogin.json?.token ?? techLogin.json?.data?.token;
  const techGetUsers = await request(ACCEPTANCE_BASE_URL, 'GET', '/api/business/users', { token: techToken });
  assertCheck('rbac_tech_users_denied', techGetUsers.status === 403, techGetUsers.status);

  const deleteUser = await request(ACCEPTANCE_BASE_URL, 'DELETE', `/api/business/users/${createdUserId}`, { token });
  assertCheck('users_delete_hard_http', deleteUser.status === 200, deleteUser.status);
  const afterDeleteUsers = dataArray((await request(ACCEPTANCE_BASE_URL, 'GET', '/api/business/users', { token })).json);
  const deletedUserRow = afterDeleteUsers.find((u) => String(u.email).toLowerCase() === testEmail);
  assertCheck('users_delete_hard_missing_from_get', !deletedUserRow, deletedUserRow ? userActive(deletedUserRow) : 'missing');
  const deletedLogin = await request(ACCEPTANCE_BASE_URL, 'POST', '/api/auth/login', {
    body: { email: testEmail, password: testPassword },
  });
  assertCheck('users_deleted_login_blocked', [401, 403].includes(deletedLogin.status), deletedLogin.status);

  const baselineActive = await ownerCounts(ACCEPTANCE_BASE_URL, token, false);
  const baselineHistorical = await ownerCounts(ACCEPTANCE_BASE_URL, token, true);
  result.metrics.acceptanceBeforeActive = baselineActive;
  result.metrics.acceptanceBeforeHistorical = baselineHistorical;

  const stamp = id('core');
  const clientSync = `${stamp}-client`;
  const sellerSync = `${stamp}-seller`;
  const lotSync = `${stamp}-lot`;
  const freeLotSync = `${stamp}-free-lot`;
  const uploadCreate = await syncUpload(token, {
    clients: [{ sync_id: clientSync, nombre: `ACCEPTANCE CLIENT ${stamp}`, cedula: `AC-${stamp}`, telefono: '000', version: 1 }],
    sellers: [{ sync_id: sellerSync, nombre: `ACCEPTANCE SELLER ${stamp}`, cedula: `AS-${stamp}`, activo: true, version: 1 }],
    products: [
      { sync_id: lotSync, manzana_numero: `A${stamp.slice(-4)}`, solar_numero: '1', metros_cuadrados: 100, precio_por_metro: 1000, estado: 'disponible', version: 1 },
      { sync_id: freeLotSync, manzana_numero: `F${stamp.slice(-4)}`, solar_numero: '1', metros_cuadrados: 90, precio_por_metro: 800, estado: 'disponible', version: 1 },
    ],
  });
  assertCheck('sync_nonfinancial_create_http', uploadCreate.status === 200, uploadCreate.status);
  assertCheck('clients_create_applied', uploadCreate.json?.applied?.clients === 1, uploadCreate.json?.applied?.clients);
  assertCheck('sellers_create_applied', uploadCreate.json?.applied?.sellers === 1, uploadCreate.json?.applied?.sellers);
  assertCheck('lots_create_applied', uploadCreate.json?.applied?.products === 2, uploadCreate.json?.applied?.products);

  const uploadEdit = await syncUpload(token, {
    clients: [{ sync_id: clientSync, nombre: `ACCEPTANCE CLIENT EDIT ${stamp}`, cedula: `AC-${stamp}`, telefono: '111', version: 2 }],
    sellers: [{ sync_id: sellerSync, nombre: `ACCEPTANCE SELLER EDIT ${stamp}`, cedula: `AS-${stamp}`, activo: true, version: 2 }],
    products: [{ sync_id: freeLotSync, manzana_numero: `F${stamp.slice(-4)}`, solar_numero: '1', metros_cuadrados: 91, precio_por_metro: 850, estado: 'disponible', version: 2 }],
  });
  assertCheck('sync_nonfinancial_edit_http', uploadEdit.status === 200, uploadEdit.status);

  const freeLotDelete = await syncUpload(token, {
    products: [{ sync_id: freeLotSync, deleted_at: new Date().toISOString(), version: 3 }],
  });
  assertCheck('lots_free_delete_http', freeLotDelete.status === 200, freeLotDelete.status);
  assertCheck('lots_free_delete_applied', freeLotDelete.json?.applied?.products === 1, freeLotDelete.json?.applied?.products);

  const saleActive = await request(ACCEPTANCE_BASE_URL, 'POST', '/api/authoritative/sales', {
    token,
    idempotencyKey: id('sale-active'),
    body: {
      clientSyncId: clientSync,
      lotSyncId: lotSync,
      sellerSyncId: sellerSync,
      syncId: `${stamp}-sale-active`,
      salePrice: 100000,
      downPaymentPercentage: 20,
      initialPaymentPaid: 20000,
      monthlyInterest: 1,
      installmentCount: 12,
      initialPaymentMethod: 'efectivo',
    },
  });
  assertCheck('sales_create_http', [200, 201].includes(saleActive.status), saleActive.status);
  const activeSaleId = saleActive.json?.data?.saleId ?? saleActive.json?.saleId;
  assertCheck('sales_create_has_id', Boolean(activeSaleId), activeSaleId ? 'present' : 'missing');

  const editClientSync = `${stamp}-edit-client`;
  const editLotSync = `${stamp}-edit-lot`;
  await syncUpload(token, {
    clients: [{ sync_id: editClientSync, nombre: `ACCEPTANCE EDIT CLIENT ${stamp}`, cedula: `ACE-${stamp}`, version: 1 }],
    products: [{ sync_id: editLotSync, manzana_numero: `E${stamp.slice(-4)}`, solar_numero: '1', metros_cuadrados: 100, precio_por_metro: 900, estado: 'disponible', version: 1 }],
  });
  const editableSale = await request(ACCEPTANCE_BASE_URL, 'POST', '/api/authoritative/sales', {
    token,
    idempotencyKey: id('sale-editable'),
    body: {
      clientSyncId: editClientSync,
      lotSyncId: editLotSync,
      syncId: `${stamp}-sale-editable`,
      salePrice: 90000,
      downPaymentPercentage: 20,
      initialPaymentPaid: 0,
      initialPaymentDeadline: new Date(Date.now() + 86400000).toISOString(),
      monthlyInterest: 1,
      installmentCount: 12,
    },
  });
  assertCheck('sales_editable_create_http', [200, 201].includes(editableSale.status), editableSale.status);
  const editableSaleId = editableSale.json?.data?.saleId ?? editableSale.json?.saleId;
  assertCheck('sales_editable_create_has_id', Boolean(editableSaleId), editableSaleId ? 'present' : 'missing');

  const editOperationKey = id('sale-edit');
  const editBody = {
    clientSyncId: editClientSync,
    lotSyncId: editLotSync,
    salePrice: 95000,
    downPaymentPercentage: 20,
    initialPaymentPaid: 0,
    initialPaymentDeadline: new Date(Date.now() + 172800000).toISOString(),
    monthlyInterest: 1,
    installmentCount: 10,
    operationId: editOperationKey,
  };
  const editSale = await request(ACCEPTANCE_BASE_URL, 'PATCH', `/api/business/sales/${editableSaleId}`, {
    token,
    idempotencyKey: editOperationKey,
    body: editBody,
  });
  assertCheck('sales_edit_http', editSale.status === 200, editSale.status);
  assertCheck('sales_edit_balance_recalculated', Number(editSale.json?.data?.balance) === 95000, editSale.json?.data);

  const editSaleReplay = await request(ACCEPTANCE_BASE_URL, 'PATCH', `/api/business/sales/${editableSaleId}`, {
    token,
    idempotencyKey: editOperationKey,
    body: editBody,
  });
  assertCheck('sales_edit_idempotent_replay_http', editSaleReplay.status === 200, editSaleReplay.status);
  assertCheck('sales_edit_idempotent_replay_flag', editSaleReplay.json?.idempotentReplay === true, editSaleReplay.json);

  const editToOccupiedLot = await request(ACCEPTANCE_BASE_URL, 'PATCH', `/api/business/sales/${editableSaleId}`, {
    token,
    idempotencyKey: id('sale-edit-occupied-lot'),
    body: {
      clientSyncId: editClientSync,
      lotSyncId: lotSync,
      salePrice: 95000,
      downPaymentPercentage: 20,
      initialPaymentPaid: 0,
      initialPaymentDeadline: new Date(Date.now() + 172800000).toISOString(),
      monthlyInterest: 1,
      installmentCount: 10,
    },
  });
  assertCheck('sales_edit_occupied_lot_blocked', editToOccupiedLot.status === 409, editToOccupiedLot.status);

  const editPaidSale = await request(ACCEPTANCE_BASE_URL, 'PATCH', `/api/business/sales/${activeSaleId}`, {
    token,
    idempotencyKey: id('sale-edit-paid'),
    body: {
      clientSyncId: clientSync,
      lotSyncId: lotSync,
      salePrice: 101000,
      downPaymentPercentage: 20,
      initialPaymentPaid: 20000,
      monthlyInterest: 1,
      installmentCount: 12,
    },
  });
  assertCheck('sales_edit_with_existing_payments_blocked', editPaidSale.status === 409, editPaidSale.status);

  const deleteActiveLotBypass = await syncUpload(token, {
    products: [{ sync_id: lotSync, deleted_at: new Date().toISOString(), version: 9 }],
  });
  const lotRejected = (deleteActiveLotBypass.json?.rejected?.products ?? []).some((row) => row.reason === 'active_sale_reference');
  assertCheck('lots_active_sale_delete_blocked_api', deleteActiveLotBypass.status === 200 && lotRejected, deleteActiveLotBypass.json?.rejected?.products ?? deleteActiveLotBypass.status);

  const normalPayment = await request(ACCEPTANCE_BASE_URL, 'POST', '/api/authoritative/payments', {
    token,
    idempotencyKey: id('payment-normal'),
    body: { saleId: activeSaleId, amount: 2000, paymentType: 'cuota', paymentMethod: 'efectivo' },
  });
  assertCheck('payments_normal_http', [200, 201].includes(normalPayment.status), normalPayment.status);
  const normalPaymentId = normalPayment.json?.data?.paymentIds?.[0] ?? normalPayment.json?.paymentIds?.[0];
  assertCheck('payments_normal_has_id', Boolean(normalPaymentId), normalPaymentId ? 'present' : 'missing');

  const capitalPayment = await request(ACCEPTANCE_BASE_URL, 'POST', '/api/authoritative/payments', {
    token,
    idempotencyKey: id('payment-capital'),
    body: { saleId: activeSaleId, amount: 500, paymentType: 'abono_capital', paymentMethod: 'efectivo' },
  });
  assertCheck('payments_capital_http', [200, 201, 409].includes(capitalPayment.status), capitalPayment.status);

  const annul = await request(ACCEPTANCE_BASE_URL, 'POST', `/api/authoritative/payments/${normalPaymentId}/annul`, {
    token,
    idempotencyKey: id('payment-annul'),
    body: { reason: 'acceptance final probe' },
  });
  assertCheck('payments_annul_http', [200, 201, 409].includes(annul.status), annul.status);

  const cancelClientSync = `${stamp}-cancel-client`;
  const cancelLotSync = `${stamp}-cancel-lot`;
  await syncUpload(token, {
    clients: [{ sync_id: cancelClientSync, nombre: `ACCEPTANCE CANCEL CLIENT ${stamp}`, cedula: `ACC-${stamp}`, version: 1 }],
    products: [{ sync_id: cancelLotSync, manzana_numero: `C${stamp.slice(-4)}`, solar_numero: '1', metros_cuadrados: 100, precio_por_metro: 1000, estado: 'disponible', version: 1 }],
  });
  const cancellableSale = await request(ACCEPTANCE_BASE_URL, 'POST', '/api/authoritative/sales', {
    token,
    idempotencyKey: id('sale-cancel'),
    body: {
      clientSyncId: cancelClientSync,
      lotSyncId: cancelLotSync,
      syncId: `${stamp}-sale-cancel`,
      salePrice: 100000,
      downPaymentPercentage: 20,
      initialPaymentPaid: 0,
      initialPaymentDeadline: new Date(Date.now() + 86400000).toISOString(),
      monthlyInterest: 1,
      installmentCount: 12,
    },
  });
  const cancellableSaleId = cancellableSale.json?.data?.saleId ?? cancellableSale.json?.saleId;
  const cancelSale = await request(ACCEPTANCE_BASE_URL, 'POST', `/api/authoritative/sales/${cancellableSaleId}/cancel`, {
    token,
    idempotencyKey: id('sale-cancel-op'),
    body: { reason: 'acceptance final probe' },
  });
  assertCheck('sales_cancel_http', [200, 201].includes(cancelSale.status), cancelSale.status);

  const dashboard = await request(ACCEPTANCE_BASE_URL, 'GET', '/api/owner/dashboard', { token });
  assertCheck('dashboard_http', dashboard.status === 200, dashboard.status);

  const download = await syncDownload(token);
  assertCheck('sync_download_http', download.status === 200, download.status);
  const records = download.json?.records ?? {};
  assertCheck('sync_download_contains_client', Boolean(findSync(records, 'clients', clientSync)), clientSync);
  assertCheck('sync_download_contains_lot', Boolean(findSync(records, 'products', lotSync)), lotSync);
  assertCheck('sync_free_lot_tombstone_visible', Boolean(findSync(records, 'products', freeLotSync)?.deleted_at), freeLotSync);

  const activeAfter = await ownerCounts(ACCEPTANCE_BASE_URL, token, false);
  const historicalAfter = await ownerCounts(ACCEPTANCE_BASE_URL, token, true);
  result.metrics.acceptanceAfterActive = activeAfter;
  result.metrics.acceptanceAfterHistorical = historicalAfter;
  assertCheck('postgres_counts_changed_expectedly', historicalAfter.clients >= baselineHistorical.clients + 2 && historicalAfter.lots >= baselineHistorical.lots + 3, { before: baselineHistorical, after: historicalAfter });

  if (PRODUCTION_BASE_URL) {
    const prodActive = await ownerCounts(PRODUCTION_BASE_URL, undefined, false, true);
    const prodHistorical = await ownerCounts(PRODUCTION_BASE_URL, undefined, true, true);
    result.metrics.productionActive = prodActive;
    result.metrics.productionHistorical = prodHistorical;
    assertCheck('production_active_sentinel', compareCounts(prodActive, productionExpectedActive), prodActive);
    assertCheck('production_historical_sentinel', compareCounts(prodHistorical, productionExpectedHistorical), prodHistorical);
    assertCheck('production_read_only_methods', result.productionMethods.every((method) => method === 'GET'), result.productionMethods);
  } else {
    pass('production_sentinel_skipped', 'PRODUCTION_BASE_URL not provided');
  }

  const endpoints = Object.fromEntries(result.endpoints);
  const output = {
    ok: result.failures.length === 0,
    checks: result.checks,
    metrics: result.metrics,
    endpoints,
    failures: result.failures,
  };
  console.log(JSON.stringify(output, null, 2));
  if (result.failures.length > 0) process.exitCode = 1;
}

main().catch((error) => {
  console.error(JSON.stringify({ ok: false, error: error.message }, null, 2));
  process.exitCode = 1;
});
