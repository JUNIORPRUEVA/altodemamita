#!/usr/bin/env node

/**
 * Ejecutor de Auditoría de Datos en Nube
 * 
 * USO:
 *   npm run task:audit:cloud-cleanup
 *   
 * O directamente:
 *   node scripts/audit-cloud-data.js
 * 
 * REQUISITOS:
 *   - PostgreSQL cliente (pg_dump disponible en PATH)
 *   - Node.js con Prisma configurado
 *   - DATABASE_URL configurada con credenciales de la nube
 *   - Acceso a base de datos local (sistema_solares.db)
 */

const { exec } = require('child_process');
const { promisify } = require('util');
const path = require('path');

const execAsync = promisify(exec);

async function runAudit() {
  console.log('\n╔════════════════════════════════════════════════════════════╗');
  console.log('║    🔍 SISTEMA DE AUDITORÍA DE DATOS - NUBE VS LOCAL        ║');
  console.log('║              Fases 1-3: Backup + Auditoría + Propuesta     ║');
  console.log('╚════════════════════════════════════════════════════════════╝\n');

  console.log('Iniciando auditoría...\n');

  try {
    // Ejecutar el script TypeScript
    const scriptPath = path.join(__dirname, '../src/tasks/cloud-audit.ts');
    
    const { stdout, stderr } = await execAsync(
      `npx ts-node "${scriptPath}"`,
      {
        cwd: path.join(__dirname, '..'),
        maxBuffer: 10 * 1024 * 1024, // 10MB buffer
        env: {
          ...process.env,
          NODE_ENV: 'development',
        },
      }
    );

    console.log(stdout);

    if (stderr && !stderr.includes('advisory')) {
      console.warn('ADVERTENCIAS:\n', stderr);
    }

    process.exit(0);
  } catch (error: any) {
    console.error('\n❌ ERROR DURANTE LA AUDITORÍA:\n');
    console.error(error.message);
    
    if (error.stderr) {
      console.error('\nDetalle del error:\n', error.stderr);
    }
    
    process.exit(1);
  }
}

runAudit();
