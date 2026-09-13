import { stdin } from "node:process";
import { PrismaClient } from "@prisma/client";
import bcrypt from "bcryptjs";

const prisma = new PrismaClient();

async function readStdin() {
  const chunks = [];
  for await (const chunk of stdin) chunks.push(chunk);
  return Buffer.concat(chunks).toString("utf8");
}

async function main() {
  const input = JSON.parse(await readStdin());
  const email = String(input.email ?? "")
    .trim()
    .toLowerCase();
  const password = String(input.password ?? "");
  if (!email || password.length < 12) {
    throw new Error("Invalid acceptance password update input.");
  }

  const databaseUrl = new URL(process.env.DATABASE_URL);
  if (databaseUrl.pathname.slice(1) !== "altomamita_manual_acceptance") {
    throw new Error("Refusing to mutate non-acceptance database.");
  }

  const user = await prisma.user.findUnique({ where: { email } });
  if (!user || !user.active || user.deletedAt) {
    throw new Error("Acceptance user not found or inactive.");
  }
  await prisma.user.update({
    where: { id: user.id },
    data: { passwordHash: await bcrypt.hash(password, 10) },
  });
  console.log(JSON.stringify({ ok: true, email }));
}

main()
  .catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
