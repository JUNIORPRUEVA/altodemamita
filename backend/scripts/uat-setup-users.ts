/**
 * FASE 06 — Prepara los usuarios de UAT en la base de ACEPTACION.
 *
 * Crea (o repara) dos usuarios con credenciales conocidas para poder ejercitar
 * la interfaz Windows:
 *   - uat-owner@acceptance.local  (OWNER / admin)  -> acciones administrativas
 *   - uat-tech@acceptance.local   (TECH / vendedor) -> debe quedar bloqueado
 *
 * Se niega a ejecutarse contra cualquier URL que no sea local.
 * No toca produccion.
 */
import { PrismaClient } from "@prisma/client";
import { hashPassword } from "../src/password";

const dbUrl = process.env.ACCEPTANCE_DATABASE_URL ?? "";
if (!dbUrl) {
  console.error("Falta ACCEPTANCE_DATABASE_URL.");
  process.exit(2);
}
if (!/(127\.0\.0\.1|localhost)/.test(dbUrl)) {
  console.error("Rechazado: solo Acceptance local.");
  process.exit(2);
}

const OWNER_EMAIL = process.env.UAT_OWNER_EMAIL ?? "uat-owner@acceptance.local";
const OWNER_PASSWORD = process.env.UAT_OWNER_PASSWORD ?? "";
const TECH_EMAIL = process.env.UAT_TECH_EMAIL ?? "uat-tech@acceptance.local";
const TECH_PASSWORD = process.env.UAT_TECH_PASSWORD ?? "";
if (!OWNER_PASSWORD || !TECH_PASSWORD) {
  console.error("Faltan UAT_OWNER_PASSWORD / UAT_TECH_PASSWORD.");
  process.exit(2);
}

const prisma = new PrismaClient({ datasources: { db: { url: dbUrl } } });

async function upsertUser(input: {
  email: string;
  name: string;
  password: string;
  role: "OWNER" | "TECH";
  localRole: string;
}) {
  const company = await prisma.company.findFirst({
    where: { tenantKey: "alto-dona-mamita-sistema-solares" },
    select: { id: true },
  });
  if (!company) {
    throw new Error("No existe la empresa de aceptacion.");
  }

  const hash = await hashPassword(input.password);
  const existing = await prisma.user.findFirst({
    where: { email: input.email, companyId: company.id },
    select: { id: true },
  });

  if (existing) {
    await prisma.user.update({
      where: { id: existing.id },
      data: {
        passwordHash: hash,
        role: input.role,
        localRole: input.localRole,
        active: true,
        deletedAt: null,
      },
    });
    console.log(`actualizado: ${input.email} (${input.role})`);
    return;
  }

  await prisma.user.create({
    data: {
      companyId: company.id,
      syncId: `uat-${input.role.toLowerCase()}-${Date.now()}`,
      email: input.email,
      name: input.name,
      passwordHash: hash,
      role: input.role,
      localRole: input.localRole,
      active: true,
    },
  });
  console.log(`creado: ${input.email} (${input.role})`);
}

async function main() {
  await upsertUser({
    email: OWNER_EMAIL,
    name: "UAT Owner",
    password: OWNER_PASSWORD,
    role: "OWNER",
    localRole: "admin",
  });
  await upsertUser({
    email: TECH_EMAIL,
    name: "UAT Tecnico",
    password: TECH_PASSWORD,
    role: "TECH",
    localRole: "vendedor",
  });
  await prisma.$disconnect();
}

main().catch(async (error) => {
  console.error(error);
  await prisma.$disconnect();
  process.exit(1);
});
