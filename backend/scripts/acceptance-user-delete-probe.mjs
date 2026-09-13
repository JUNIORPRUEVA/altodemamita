const ACCEPTANCE_BASE_URL = process.env.ACCEPTANCE_BASE_URL ?? 'http://127.0.0.1:3302';
const ADMIN_EMAIL = process.env.ACCEPTANCE_ADMIN_EMAIL ?? 'admin@sistema.local';
const ADMIN_PASSWORD = process.env.ACCEPTANCE_ADMIN_PASSWORD ?? '';

const result = {
  checks: {},
  metrics: {},
  endpoints: {},
  failures: [],
};

function record(name, pass, detail = true) {
  result.checks[name] = pass ? detail : false;
  if (!pass) result.failures.push({ name, detail });
}

function id(prefix) {
  return `${prefix}-${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

function randomPassword() {
  return `Acc#${Math.random().toString(36).slice(2)}${Date.now()}!`;
}

async function request(method, path, { token, body, idempotencyKey } = {}) {
  const headers = { Accept: 'application/json' };
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  if (token) headers.Authorization = `Bearer ${token}`;
  if (idempotencyKey) headers['Idempotency-Key'] = idempotencyKey;
  const response = await fetch(`${ACCEPTANCE_BASE_URL}${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  result.endpoints[`${method} ${path.split('?')[0]}`] = response.status;
  const text = await response.text();
  let json = null;
  if (text) {
    try {
      json = JSON.parse(text);
    } catch {
      json = { rawText: text.slice(0, 200) };
    }
  }
  return { status: response.status, ok: response.ok, json };
}

function usersFrom(payload) {
  if (Array.isArray(payload?.data?.users)) return payload.data.users;
  if (Array.isArray(payload?.users)) return payload.users;
  if (Array.isArray(payload?.data)) return payload.data;
  return [];
}

function userId(user) {
  return user?.id ?? user?.userId ?? user?.remoteId;
}

async function login(email, password) {
  const response = await request('POST', '/api/auth/login', {
    body: { email, password },
  });
  return {
    response,
    token: response.json?.data?.token ?? response.json?.token ?? response.json?.accessToken,
    user: response.json?.data?.user ?? response.json?.user,
  };
}

async function syncUpload(token, records) {
  return request('POST', '/api/sync/upload', {
    token,
    body: { device_id: 'acceptance-user-delete-probe', records },
  });
}

async function createUser(token, { name, email, role, password }) {
  const response = await request('POST', '/api/business/users', {
    token,
    body: { name, email, role, password, active: true },
  });
  return response;
}

async function findUser(token, email) {
  const response = await request('GET', '/api/business/users', { token });
  const users = usersFrom(response.json);
  return {
    response,
    user: users.find((item) => String(item.email ?? '').toLowerCase() === email.toLowerCase()),
    count: users.length,
  };
}

async function main() {
  if (!ADMIN_PASSWORD) {
    throw new Error('ACCEPTANCE_ADMIN_PASSWORD is required.');
  }

  const status = await request('GET', '/api/system/status');
  record('acceptance_database', status.json?.databaseName === 'altomamita_manual_acceptance', status.json?.databaseName);

  const adminLogin = await login(ADMIN_EMAIL, ADMIN_PASSWORD);
  record('owner_login_http', adminLogin.response.status === 200, adminLogin.response.status);
  record('owner_role', String(adminLogin.user?.role ?? '').toUpperCase() === 'OWNER', adminLogin.user?.role);
  const token = adminLogin.token;
  if (!token) throw new Error('Owner token missing.');

  const before = await findUser(token, '__never__@sistema.local');
  result.metrics.usersBefore = before.count;

  const freeEmail = 'acceptance.delete.user.001@sistema.local';
  const freeExisting = await findUser(token, freeEmail);
  if (freeExisting.user) {
    await request('DELETE', `/api/business/users/${userId(freeExisting.user)}`, { token });
  }
  const freePassword = randomPassword();
  const freeCreate = await createUser(token, {
    name: 'ACCEPTANCE-DELETE-USER-001',
    email: freeEmail,
    role: 'TECH',
    password: freePassword,
  });
  const freeUser = freeCreate.json?.data?.user ?? freeCreate.json?.user;
  const freeUserId = userId(freeUser);
  record('free_user_create_http', freeCreate.status === 201, freeCreate.status);
  record('free_user_role_tech', String(freeUser?.role ?? '').toUpperCase() === 'TECH', freeUser?.role);

  const freeDelete = await request('DELETE', `/api/business/users/${freeUserId}`, { token });
  record('free_user_delete_http', freeDelete.status === 200, freeDelete.status);
  record('free_user_delete_contract', freeDelete.json?.data?.deleted === true, freeDelete.json);

  const freeAfter = await findUser(token, freeEmail);
  record('free_user_missing_from_get', !freeAfter.user, Boolean(freeAfter.user));
  const deletedLogin = await login(freeEmail, freePassword);
  record('deleted_user_login_rejected', deletedLogin.response.status === 401, deletedLogin.response.status);

  const blockEmail = `acceptance.block.user.${Date.now()}@sistema.local`;
  const blockPassword = randomPassword();
  const blockCreate = await createUser(token, {
    name: 'ACCEPTANCE-BLOCK-USER-001',
    email: blockEmail,
    role: 'TECH',
    password: blockPassword,
  });
  const blockUser = blockCreate.json?.data?.user ?? blockCreate.json?.user;
  const blockPatch = await request('PATCH', `/api/business/users/${userId(blockUser)}`, {
    token,
    body: { active: false },
  });
  const blockAfter = await findUser(token, blockEmail);
  const blockedLogin = await login(blockEmail, blockPassword);
  record('deactivate_patch_http', blockPatch.status === 200, blockPatch.status);
  record('deactivated_row_remains', Boolean(blockAfter.user), Boolean(blockAfter.user));
  record('deactivated_user_inactive', blockAfter.user?.active === false, blockAfter.user?.active);
  record('deactivated_login_rejected', blockedLogin.response.status === 401, blockedLogin.response.status);

  const historyEmail = `acceptance.history.user.${Date.now()}@sistema.local`;
  const historyPassword = randomPassword();
  const historyCreate = await createUser(token, {
    name: 'ACCEPTANCE-HISTORY-USER-001',
    email: historyEmail,
    role: 'OWNER',
    password: historyPassword,
  });
  const historyUser = historyCreate.json?.data?.user ?? historyCreate.json?.user;
  const historyUserId = userId(historyUser);
  record('history_user_create_http', historyCreate.status === 201, historyCreate.status);

  const historyLogin = await login(historyEmail, historyPassword);
  const historyToken = historyLogin.token;
  record('history_owner_login_http', historyLogin.response.status === 200 && Boolean(historyToken), historyLogin.response.status);

  const stamp = id('history');
  const clientSync = `${stamp}-client`;
  const sellerSync = `${stamp}-seller`;
  const lotSync = `${stamp}-lot`;
  const upload = await syncUpload(historyToken, {
    clients: [{ sync_id: clientSync, nombre: `ACCEPTANCE HISTORY CLIENT ${stamp}`, cedula: `HD-${stamp}`, telefono: '000', version: 1 }],
    sellers: [{ sync_id: sellerSync, nombre: `ACCEPTANCE HISTORY SELLER ${stamp}`, cedula: `HS-${stamp}`, activo: true, version: 1 }],
    products: [{ sync_id: lotSync, manzana_numero: `H${stamp.slice(-4)}`, solar_numero: '1', metros_cuadrados: 100, precio_por_metro: 1000, estado: 'disponible', version: 1 }],
  });
  record('history_seed_sync_http', upload.status === 200, upload.status);

  const sale = await request('POST', '/api/authoritative/sales', {
    token: historyToken,
    idempotencyKey: id('history-sale'),
    body: {
      clientSyncId: clientSync,
      lotSyncId: lotSync,
      sellerSyncId: sellerSync,
      syncId: `${stamp}-sale`,
      salePrice: 100000,
      downPaymentPercentage: 20,
      initialPaymentPaid: 20000,
      monthlyInterest: 1,
      installmentCount: 12,
      initialPaymentMethod: 'efectivo',
    },
  });
  record('history_sale_create_http', [200, 201].includes(sale.status), sale.status);

  const historyDelete = await request('DELETE', `/api/business/users/${historyUserId}`, { token });
  const historyAfter = await findUser(token, historyEmail);
  record('history_delete_rejected_http', historyDelete.status === 409, historyDelete.status);
  record('history_delete_business_error', historyDelete.json?.error?.code === 'USER_HAS_HISTORY', historyDelete.json?.error?.code);
  record('history_row_remains_active', historyAfter.user?.active === true, historyAfter.user?.active);

  const selfDelete = await request('DELETE', `/api/business/users/${adminLogin.user?.id}`, { token });
  record('self_delete_rejected', selfDelete.status === 409 && selfDelete.json?.error?.code === 'CANNOT_DELETE_SELF', {
    status: selfDelete.status,
    code: selfDelete.json?.error?.code,
  });

  const techEmail = `acceptance.tech.rbac.${Date.now()}@sistema.local`;
  const techPassword = randomPassword();
  const techCreate = await createUser(token, {
    name: 'ACCEPTANCE-TECH-RBAC-DELETE',
    email: techEmail,
    role: 'TECH',
    password: techPassword,
  });
  const techLogin = await login(techEmail, techPassword);
  const techDelete = await request('DELETE', `/api/business/users/${historyUserId}`, { token: techLogin.token });
  record('tech_delete_forbidden', techCreate.status === 201 && techLogin.response.status === 200 && techDelete.status === 403, {
    create: techCreate.status,
    login: techLogin.response.status,
    delete: techDelete.status,
  });

  const after = await findUser(token, '__never__@sistema.local');
  result.metrics.usersAfter = after.count;
  result.metrics.freeEmail = freeEmail;
  result.metrics.historyEmail = historyEmail;
  result.metrics.blockEmail = blockEmail;
  result.metrics.failures = result.failures.length;

  console.log(JSON.stringify(result, null, 2));
  if (result.failures.length > 0) {
    process.exitCode = 1;
  }
}

main().catch((error) => {
  console.error(error?.message ?? error);
  process.exitCode = 1;
});
