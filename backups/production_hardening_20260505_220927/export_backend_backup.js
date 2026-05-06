const fs = require('fs');
const path = require('path');
const backendRoot = 'c:/Users/pc/DEV/PROYECTOS/CLIENTES/SISTEMA_SOLARES/backend';
const { PrismaClient } = require(path.join(backendRoot, 'node_modules', '@prisma', 'client'));
const prisma = new PrismaClient();
const replacer = (_key, value) => {
  if (value instanceof Date) return value.toISOString();
  if (typeof value === 'bigint') return value.toString();
  return value;
};
async function tableExists(name) {
  const rows = await prisma.$queryRawUnsafe(`SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='${name}') AS exists`);
  return !!(rows[0] && (rows[0].exists === true || rows[0].exists === 't'));
}
async function dumpRaw(name) {
  if (!(await tableExists(name))) return { exists: false, rowCount: 0, rows: [] };
  const rows = await prisma.$queryRawUnsafe(`SELECT * FROM public.${name}`);
  return { exists: true, rowCount: rows.length, rows };
}
(async () => {
  const data = { exportedAt: new Date().toISOString(), tables: {} };
  const users = await prisma.user.findMany();
  const roles = await prisma.role.findMany();
  const userRoles = await prisma.userRole.findMany();
  const rolePermissions = await prisma.rolePermission.findMany();
  const permissions = await prisma.permission.findMany();
  const clients = await prisma.client.findMany();
  const products = await prisma.product.findMany();
  const sales = await prisma.sale.findMany();
  const installments = await prisma.installment.findMany();
  const payments = await prisma.payment.findMany();
  const sellers = prisma.seller ? await prisma.seller.findMany() : [];
  const authorizedDevices = await prisma.authorizedDevice.findMany();
  data.tables.users = { exists: true, rowCount: users.length, rows: users };
  data.tables.roles = { exists: true, rowCount: roles.length, rows: roles };
  data.tables.user_roles = { exists: true, rowCount: userRoles.length, rows: userRoles };
  data.tables.role_permissions = { exists: true, rowCount: rolePermissions.length, rows: rolePermissions };
  data.tables.permissions = { exists: true, rowCount: permissions.length, rows: permissions };
  data.tables.clients = { exists: true, rowCount: clients.length, rows: clients };
  data.tables.products = { exists: true, rowCount: products.length, rows: products };
  data.tables.sales = { exists: true, rowCount: sales.length, rows: sales };
  data.tables.installments = { exists: true, rowCount: installments.length, rows: installments };
  data.tables.payments = { exists: true, rowCount: payments.length, rows: payments };
  data.tables.sellers = { exists: !!prisma.seller, rowCount: sellers.length, rows: sellers };
  data.tables.authorized_devices = { exists: true, rowCount: authorizedDevices.length, rows: authorizedDevices };
  data.tables.sync_queue = await dumpRaw('sync_queue');
  data.tables.conflict_logs = await dumpRaw('conflict_logs');
  fs.writeFileSync(process.argv[2], JSON.stringify(data, replacer, 2));
  console.log(`BACKEND_BACKUP=${process.argv[2]}`);
  console.log(`AUTHORIZED_DEVICES_ROWS=${authorizedDevices.length}`);
  console.log(`SYNC_QUEUE_EXISTS=${data.tables.sync_queue.exists}`);
  console.log(`CONFLICT_LOGS_EXISTS=${data.tables.conflict_logs.exists}`);
  await prisma.$disconnect();
})().catch(async (error) => {
  console.error(error);
  try { await prisma.$disconnect(); } catch {}
  process.exit(1);
});
