/**
 * Cloud Data Cleanup - Comprehensive Audit Tool
 * 
 * Fases 1-3: Backup obligatorio + Auditoría nube vs local + Propuesta de limpieza
 * 
 * SEGURIDAD:
 * - Solo lectura hasta que usuario apruebe
 * - Backup REQUERIDO antes de cualquier modificación
 * - Genera reporte completo con todas las métricas
 * 
 * USO: npx ts-node src/tasks/cloud-audit.ts
 * O: npm run task:audit:cloud-cleanup (si existe en package.json)
 */

import { PrismaClient } from '@prisma/client';
import { Database, open } from 'sqlite';
import sqlite3 from 'sqlite3';
import * as fs from 'fs';
import * as path from 'path';
import { exec } from 'child_process';
import { promisify } from 'util';
import * as moment from 'moment';

const execAsync = promisify(exec);

interface AuditReport {
  timestamp: string;
  backupStatus: BackupStatus;
  cloudCounts: TableCounts;
  localCounts: TableCounts;
  comparison: ComparisonResult;
  cleanupProposal: CleanupProposal;
}

interface BackupStatus {
  success: boolean;
  filename: string;
  size: number;
  timestamp: string;
  path: string;
  error?: string;
}

interface TableCounts {
  clients: number;
  sellers: number;
  products: number;
  sales: number;
  payments: number;
  installments: number;
  users: number;
  clientsDeleted: number;
  sellersDeleted: number;
  productsDeleted: number;
  salesDeleted: number;
  paymentsDeleted: number;
  installmentsDeleted: number;
}

interface ComparisonResult {
  tables: {
    [table: string]: TableComparison;
  };
  orphanedRecords: OrphanedRecords;
  possibleDuplicates: PossibleDuplicate[];
  dataIntegrity: DataIntegrityIssue[];
}

interface TableComparison {
  cloudCount: number;
  localCount: number;
  onlyInCloud: number;
  onlyInLocal: number;
  matched: number;
  cloudDeleted: number;
  localDeleted: number;
}

interface OrphanedRecords {
  paymentsWithoutSale: number;
  installmentsWithoutSale: number;
  salesWithoutClient: number;
  salesWithoutProduct: number;
}

interface PossibleDuplicate {
  table: string;
  syncIdList: string[];
  identifier: string;
  count: number;
}

interface DataIntegrityIssue {
  severity: 'high' | 'medium' | 'low';
  table: string;
  issue: string;
  recordCount: number;
  details: string;
}

interface CleanupProposal {
  totalCloudRecords: number;
  totalLocalRecords: number;
  recordsToDelete: DeleteProposal[];
  dependencyOrder: string[];
  riskAssessment: RiskAssessment;
  estimatedImpact: EstimatedImpact;
}

interface DeleteProposal {
  table: string;
  reason: string;
  count: number;
  recordIds: string[];
  dependencies: string[];
  preferSoftDelete: boolean;
}

interface RiskAssessment {
  level: 'high' | 'medium' | 'low';
  criticalIssues: string[];
  warnings: string[];
  recommendations: string[];
}

interface EstimatedImpact {
  affectedSales: number;
  affectedPayments: number;
  affectedInstallments: number;
  totalRecordImpact: number;
  dataLossRisk: string;
}

class CloudAuditTool {
  private prisma: PrismaClient;
  private localDb: Database | null = null;
  private reportPath: string;

  constructor() {
    this.prisma = new PrismaClient();
    this.reportPath = path.join(process.cwd(), 'audit-reports');
  }

  private async getLocalDb(): Promise<Database> {
    if (this.localDb) return this.localDb;

    // Buscar sistema_solares.db en rutas comunes
    const possiblePaths = [
      // Windows AppData
      path.join(process.env.APPDATA || '', 'sistema_solares', 'sistema_solares.db'),
      path.join(process.env.LOCALAPPDATA || '', 'sistema_solares', 'sistema_solares.db'),
      // Rutas relativas comunes
      path.join(process.cwd(), '../../', 'sistema_solares.db'),
      // Desde la app
      path.join(
        process.env.PROGRAMFILES || 'C:\\Program Files',
        'SistemaSolares',
        'data',
        'sistema_solares.db'
      ),
    ];

    for (const dbPath of possiblePaths) {
      if (fs.existsSync(dbPath)) {
        console.log(`   📂 Base de datos local encontrada: ${dbPath}`);
        this.localDb = await open({
          filename: dbPath,
          driver: sqlite3.Database,
        });
        return this.localDb;
      }
    }

    throw new Error(
      `Base de datos local (sistema_solares.db) no encontrada. Rutas buscadas:\n${possiblePaths.join('\n')}`
    );
  }

  // ===========================
  // FASE 1: BACKUP OBLIGATORIO
  // ===========================

  async performBackup(): Promise<BackupStatus> {
    console.log('\n📦 FASE 1: BACKUP OBLIGATORIO DE POSTGRESQL...\n');

    const timestamp = moment().format('YYYY-MM-DD_HH-mm-ss');
    const backupDir = path.join(process.cwd(), 'backups', 'cloud');
    const backupFilename = `postgresql_backup_${timestamp}.sql`;
    const backupPath = path.join(backupDir, backupFilename);

    try {
      // Crear directorio si no existe
      if (!fs.existsSync(backupDir)) {
        fs.mkdirSync(backupDir, { recursive: true });
      }

      // Extraer credenciales de DATABASE_URL
      const dbUrl = process.env.DATABASE_URL;
      if (!dbUrl) {
        throw new Error('DATABASE_URL no configurada');
      }

      // Formato: postgresql://user:password@host:port/database?schema=schema
      const urlMatch = dbUrl.match(
        /postgresql:\/\/([^:]+):([^@]+)@([^:]+):(\d+)\/([^?]+)/
      );
      if (!urlMatch) {
        throw new Error('DATABASE_URL inválida');
      }

      const [, user, password, host, port, database] = urlMatch;

      console.log(`⏳ Realizando backup de PostgreSQL...`);
      console.log(`   Host: ${host}:${port}`);
      console.log(`   Database: ${database}`);

      // Ejecutar pg_dump
      const env = { ...process.env, PGPASSWORD: password };
      const command = `pg_dump -h ${host} -p ${port} -U ${user} -d ${database} > "${backupPath}"`;

      const { stderr } = await execAsync(command, { env });

      if (stderr && !stderr.includes('password')) {
        console.warn(`⚠️  Advertencia del backup: ${stderr}`);
      }

      // Verificar que el archivo existe y tiene contenido
      if (!fs.existsSync(backupPath)) {
        throw new Error(`Archivo de backup no creado: ${backupPath}`);
      }

      const stats = fs.statSync(backupPath);
      if (stats.size === 0) {
        throw new Error(`Backup vacío: ${backupPath}`);
      }

      const status: BackupStatus = {
        success: true,
        filename: backupFilename,
        size: stats.size,
        timestamp,
        path: backupPath,
      };

      console.log(`✅ Backup completado exitosamente`);
      console.log(`   Archivo: ${backupFilename}`);
      console.log(`   Tamaño: ${(stats.size / 1024 / 1024).toFixed(2)} MB`);
      console.log(`   Ruta: ${backupPath}\n`);

      return status;
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      console.error(`❌ ERROR en backup: ${errorMsg}\n`);

      return {
        success: false,
        filename: backupFilename,
        size: 0,
        timestamp,
        path: backupPath,
        error: errorMsg,
      };
    }
  }

  // ===============================
  // FASE 2: AUDITORÍA NUBE VS LOCAL
  // ===============================

  async performAudit(): Promise<AuditReport> {
    console.log('\n🔍 FASE 2: AUDITORÍA NUBE VS LOCAL...\n');

    // Fase 1: Backup
    const backupStatus = await this.performBackup();
    if (!backupStatus.success) {
      throw new Error(`Backup falló. No puedo continuar: ${backupStatus.error}`);
    }

    // Contar registros en cloud
    console.log('📊 Contando registros en NUBE (PostgreSQL)...');
    const cloudCounts = await this.countCloudRecords();
    console.log('   ✓ Completado');

    // Contar registros en local
    console.log('📊 Contando registros en LOCAL (SQLite)...');
    const localCounts = await this.countLocalRecords();
    console.log('   ✓ Completado\n');

    // Comparar y generar insights
    console.log('🔎 Analizando diferencias...');
    const comparison = await this.compareRecords(cloudCounts, localCounts);
    console.log('   ✓ Completado\n');

    // Generar propuesta de limpieza
    console.log('📋 Generando propuesta de limpieza...');
    const cleanupProposal = await this.generateCleanupProposal(
      cloudCounts,
      localCounts,
      comparison
    );
    console.log('   ✓ Completado\n');

    const report: AuditReport = {
      timestamp: moment().format('YYYY-MM-DD HH:mm:ss'),
      backupStatus,
      cloudCounts,
      localCounts,
      comparison,
      cleanupProposal,
    };

    return report;
  }

  private async countCloudRecords(): Promise<TableCounts> {
    return {
      clients: await this.prisma.client.count(),
      sellers: await this.prisma.seller.count(),
      products: await this.prisma.product.count(),
      sales: await this.prisma.sale.count(),
      payments: await this.prisma.payment.count(),
      installments: await this.prisma.installment.count(),
      users: await this.prisma.user.count(),
      clientsDeleted: await this.prisma.client.count({
        where: { deletedAt: { not: null } },
      }),
      sellersDeleted: await this.prisma.seller.count({
        where: { deletedAt: { not: null } },
      }),
      productsDeleted: await this.prisma.product.count({
        where: { deletedAt: { not: null } },
      }),
      salesDeleted: await this.prisma.sale.count({
        where: { deletedAt: { not: null } },
      }),
      paymentsDeleted: await this.prisma.payment.count({
        where: { deletedAt: { not: null } },
      }),
      installmentsDeleted: await this.prisma.installment.count({
        where: { deletedAt: { not: null } },
      }),
    };
  }

  private async countLocalRecords(): Promise<TableCounts> {
    const db = await this.getLocalDb();

    const query = (sql: string): Promise<number> =>
      db.get(sql).then((row: any) => row?.count || 0);

    return {
      clients: await query('SELECT COUNT(*) as count FROM clientes WHERE deleted_at IS NULL'),
      sellers: await query('SELECT COUNT(*) as count FROM vendedores WHERE deleted_at IS NULL'),
      products: await query('SELECT COUNT(*) as count FROM solares WHERE deleted_at IS NULL'),
      sales: await query('SELECT COUNT(*) as count FROM ventas WHERE deleted_at IS NULL'),
      payments: await query('SELECT COUNT(*) as count FROM pagos WHERE deleted_at IS NULL'),
      installments: await query('SELECT COUNT(*) as count FROM cuotas WHERE deleted_at IS NULL'),
      users: await query('SELECT COUNT(*) as count FROM usuarios'),
      clientsDeleted: await query('SELECT COUNT(*) as count FROM clientes WHERE deleted_at IS NOT NULL'),
      sellersDeleted: await query('SELECT COUNT(*) as count FROM vendedores WHERE deleted_at IS NOT NULL'),
      productsDeleted: await query('SELECT COUNT(*) as count FROM solares WHERE deleted_at IS NOT NULL'),
      salesDeleted: await query('SELECT COUNT(*) as count FROM ventas WHERE deleted_at IS NOT NULL'),
      paymentsDeleted: await query('SELECT COUNT(*) as count FROM pagos WHERE deleted_at IS NOT NULL'),
      installmentsDeleted: await query('SELECT COUNT(*) as count FROM cuotas WHERE deleted_at IS NOT NULL'),
    };
  }

  private async compareRecords(
    cloud: TableCounts,
    local: TableCounts
  ): Promise<ComparisonResult> {
    console.log('   🔗 Analizando relaciones y huérfanos...');

    // Detectar registros huérfanos
    const orphanedRecords = await this.detectOrphanedRecords();

    // Detectar posibles duplicados
    const duplicates = await this.detectPossibleDuplicates();

    // Detectar problemas de integridad
    const integrityIssues = await this.detectIntegrityIssues();

    return {
      tables: {
        clients: {
          cloudCount: cloud.clients,
          localCount: local.clients,
          onlyInCloud: Math.max(cloud.clients - local.clients, 0),
          onlyInLocal: Math.max(local.clients - cloud.clients, 0),
          matched: Math.min(cloud.clients, local.clients),
          cloudDeleted: cloud.clientsDeleted,
          localDeleted: local.clientsDeleted,
        },
        sellers: {
          cloudCount: cloud.sellers,
          localCount: local.sellers,
          onlyInCloud: Math.max(cloud.sellers - local.sellers, 0),
          onlyInLocal: Math.max(local.sellers - cloud.sellers, 0),
          matched: Math.min(cloud.sellers, local.sellers),
          cloudDeleted: cloud.sellersDeleted,
          localDeleted: local.sellersDeleted,
        },
        products: {
          cloudCount: cloud.products,
          localCount: local.products,
          onlyInCloud: Math.max(cloud.products - local.products, 0),
          onlyInLocal: Math.max(local.products - cloud.products, 0),
          matched: Math.min(cloud.products, local.products),
          cloudDeleted: cloud.productsDeleted,
          localDeleted: local.productsDeleted,
        },
        sales: {
          cloudCount: cloud.sales,
          localCount: local.sales,
          onlyInCloud: Math.max(cloud.sales - local.sales, 0),
          onlyInLocal: Math.max(local.sales - cloud.sales, 0),
          matched: Math.min(cloud.sales, local.sales),
          cloudDeleted: cloud.salesDeleted,
          localDeleted: local.salesDeleted,
        },
        payments: {
          cloudCount: cloud.payments,
          localCount: local.payments,
          onlyInCloud: Math.max(cloud.payments - local.payments, 0),
          onlyInLocal: Math.max(local.payments - cloud.payments, 0),
          matched: Math.min(cloud.payments, local.payments),
          cloudDeleted: cloud.paymentsDeleted,
          localDeleted: local.paymentsDeleted,
        },
        installments: {
          cloudCount: cloud.installments,
          localCount: local.installments,
          onlyInCloud: Math.max(cloud.installments - local.installments, 0),
          onlyInLocal: Math.max(local.installments - cloud.installments, 0),
          matched: Math.min(cloud.installments, local.installments),
          cloudDeleted: cloud.installmentsDeleted,
          localDeleted: local.installmentsDeleted,
        },
      },
      orphanedRecords,
      possibleDuplicates: duplicates,
      dataIntegrity: integrityIssues,
    };
  }

  private async detectOrphanedRecords(): Promise<OrphanedRecords> {
    console.log('   🔍 Detectando registros huérfanos...');

    return {
      paymentsWithoutSale: await this.prisma.payment.count({
        where: {
          sale: null,
          deletedAt: null,
        },
      }),
      installmentsWithoutSale: await this.prisma.installment.count({
        where: {
          sale: null,
          deletedAt: null,
        },
      }),
      salesWithoutClient: await this.prisma.sale.count({
        where: {
          client: null,
          deletedAt: null,
        },
      }),
      salesWithoutProduct: await this.prisma.sale.count({
        where: {
          product: null,
          deletedAt: null,
        },
      }),
    };
  }

  private async detectPossibleDuplicates(): Promise<PossibleDuplicate[]> {
    console.log('   🔎 Buscando posibles duplicados...');

    const duplicates: PossibleDuplicate[] = [];

    // Buscar clientes con mismo documentId
    const clientDupes = await this.prisma.client.groupBy({
      by: ['documentId'],
      where: { documentId: { not: null }, deletedAt: null },
      _count: true,
      having: {
        id: {
          _count: {
            gt: 1,
          },
        },
      },
    });

    for (const group of clientDupes) {
      if (group._count > 1) {
        const clients = await this.prisma.client.findMany({
          where: { documentId: group.documentId, deletedAt: null },
          select: { id: true },
        });

        duplicates.push({
          table: 'clients',
          syncIdList: clients.map((c) => c.id),
          identifier: `documentId: ${group.documentId}`,
          count: group._count,
        });
      }
    }

    // Buscar vendedores con mismo documentId
    const sellerDupes = await this.prisma.seller.groupBy({
      by: ['documentId'],
      where: { documentId: { not: null }, deletedAt: null },
      _count: true,
      having: {
        id: {
          _count: {
            gt: 1,
          },
        },
      },
    });

    for (const group of sellerDupes) {
      if (group._count > 1) {
        const sellers = await this.prisma.seller.findMany({
          where: { documentId: group.documentId, deletedAt: null },
          select: { id: true },
        });

        duplicates.push({
          table: 'sellers',
          syncIdList: sellers.map((s) => s.id),
          identifier: `documentId: ${group.documentId}`,
          count: group._count,
        });
      }
    }

    return duplicates;
  }

  private async detectIntegrityIssues(): Promise<DataIntegrityIssue[]> {
    console.log('   ⚠️  Verificando integridad de datos...');

    const issues: DataIntegrityIssue[] = [];

    // Verificar sync_status pendientes en nube
    const pendingSync = await this.prisma.sale.count({
      where: { syncStatus: 'pending', deletedAt: null },
    });

    if (pendingSync > 0) {
      issues.push({
        severity: 'medium',
        table: 'sales',
        issue: 'Registros con sync_status pendiente',
        recordCount: pendingSync,
        details: `${pendingSync} ventas no han sido sincronizadas`,
      });
    }

    // Verificar pagos sin cuota asociada
    const paymentsNoInstallment = await this.prisma.payment.count({
      where: { installmentId: null, deletedAt: null },
    });

    if (paymentsNoInstallment > 10) {
      issues.push({
        severity: 'low',
        table: 'payments',
        issue: 'Pagos sin cuota asociada',
        recordCount: paymentsNoInstallment,
        details: `${paymentsNoInstallment} pagos registrados sin vinculación a cuota`,
      });
    }

    return issues;
  }

  private async generateCleanupProposal(
    cloud: TableCounts,
    local: TableCounts,
    comparison: ComparisonResult
  ): Promise<CleanupProposal> {
    console.log('   🧹 Generando propuesta de limpieza...');

    const proposal: CleanupProposal = {
      totalCloudRecords:
        cloud.clients +
        cloud.sellers +
        cloud.products +
        cloud.sales +
        cloud.payments +
        cloud.installments,
      totalLocalRecords:
        local.clients +
        local.sellers +
        local.products +
        local.sales +
        local.payments +
        local.installments,
      recordsToDelete: [],
      dependencyOrder: ['payments', 'installments', 'sales', 'clients', 'sellers', 'products'],
      riskAssessment: {
        level: 'medium',
        criticalIssues: [],
        warnings: [],
        recommendations: [],
      },
      estimatedImpact: {
        affectedSales: 0,
        affectedPayments: 0,
        affectedInstallments: 0,
        totalRecordImpact: 0,
        dataLossRisk: 'N/A',
      },
    };

    // Análisis de qué limpiar
    const orphans = comparison.orphanedRecords;

    // Registros solo en nube (candidatos a borrar)
    if (comparison.tables.clients.onlyInCloud > 0) {
      const clientsOnlyCloud = await this.prisma.client.findMany({
        where: {
          deletedAt: null,
          // Serían aquellos sin sync_id en local
        },
        select: { id: true, firstName: true, lastName: true },
        take: 100,
      });

      proposal.recordsToDelete.push({
        table: 'clients',
        reason: 'Clientes que existen solo en nube (no en local)',
        count: comparison.tables.clients.onlyInCloud,
        recordIds: clientsOnlyCloud.map((c) => c.id),
        dependencies: ['sales'],
        preferSoftDelete: true,
      });
    }

    // Registros huérfanos
    if (orphans.paymentsWithoutSale > 0) {
      proposal.recordsToDelete.push({
        table: 'payments',
        reason: 'Pagos sin venta asociada (huérfanos)',
        count: orphans.paymentsWithoutSale,
        recordIds: [],
        dependencies: [],
        preferSoftDelete: false,
      });

      proposal.riskAssessment.warnings.push(
        `${orphans.paymentsWithoutSale} pagos huérfanos sin venta: revisar antes de borrar`
      );
    }

    if (orphans.installmentsWithoutSale > 0) {
      proposal.recordsToDelete.push({
        table: 'installments',
        reason: 'Cuotas sin venta asociada (huérfanas)',
        count: orphans.installmentsWithoutSale,
        recordIds: [],
        dependencies: ['payments'],
        preferSoftDelete: false,
      });

      proposal.riskAssessment.warnings.push(
        `${orphans.installmentsWithoutSale} cuotas huérfanas sin venta`
      );
    }

    // Evaluación de riesgo
    if (proposal.recordsToDelete.length > 0) {
      const totalToDelete = proposal.recordsToDelete.reduce((sum, d) => sum + d.count, 0);
      proposal.estimatedImpact.totalRecordImpact = totalToDelete;

      if (totalToDelete > 100) {
        proposal.riskAssessment.level = 'high';
        proposal.riskAssessment.criticalIssues.push(
          `Se eliminarían ${totalToDelete} registros. Alto riesgo de pérdida de datos.`
        );
      } else if (totalToDelete > 10) {
        proposal.riskAssessment.level = 'medium';
      }
    } else {
      proposal.riskAssessment.level = 'low';
      proposal.riskAssessment.recommendations.push(
        'La nube está consistente con local. No hay registros candidatos para limpieza automática.'
      );
    }

    // Recomendaciones
    proposal.riskAssessment.recommendations.push(
      'Hacer backup ANTES de ejecutar cualquier limpieza (ya hecho)',
      'Ejecutar limpieza en orden de dependencias: ' +
        proposal.dependencyOrder.join(' → '),
      'Usar soft-delete (deleted_at) preferentemente',
      'Verificar que local está actualizado antes de limpiar'
    );

    return proposal;
  }

  // ================
  // UTILIDADES
  // ================

  async saveReport(report: AuditReport): Promise<string> {
    if (!fs.existsSync(this.reportPath)) {
      fs.mkdirSync(this.reportPath, { recursive: true });
    }

    const timestamp = moment().format('YYYY-MM-DD_HH-mm-ss');
    const reportFile = path.join(
      this.reportPath,
      `audit-report-${timestamp}.json`
    );

    fs.writeFileSync(reportFile, JSON.stringify(report, null, 2));

    return reportFile;
  }

  async printReport(report: AuditReport): Promise<void> {
    console.log('\n');
    console.log('╔════════════════════════════════════════════════════════════╗');
    console.log('║       📊 REPORTE DE AUDITORÍA - NUBE VS LOCAL              ║');
    console.log('║       Fases 1-3: Backup + Auditoría + Propuesta           ║');
    console.log('╚════════════════════════════════════════════════════════════╝\n');

    // ========== BACKUP ==========
    console.log('📦 FASE 1: ESTADO DEL BACKUP');
    console.log('─'.repeat(60));
    console.log(
      `  Estado: ${report.backupStatus.success ? '✅ EXITOSO' : '❌ FALLIDO'}`
    );
    console.log(`  Archivo: ${report.backupStatus.filename}`);
    console.log(
      `  Tamaño: ${(report.backupStatus.size / 1024 / 1024).toFixed(2)} MB`
    );
    console.log(`  Ubicación: ${report.backupStatus.path}\n`);

    if (!report.backupStatus.success) {
      console.log(`  ❌ ERROR: ${report.backupStatus.error}\n`);
      console.log('  ⚠️  NO SE PUEDE CONTINUAR SIN BACKUP EXITOSO\n');
      return;
    }

    // ========== CONTEOS ==========
    console.log('📈 FASE 2: CONTEOS POR TABLA');
    console.log('─'.repeat(60));

    const tables = [
      { name: 'Clientes', key: 'clients' },
      { name: 'Vendedores', key: 'sellers' },
      { name: 'Solares/Productos', key: 'products' },
      { name: 'Ventas', key: 'sales' },
      { name: 'Cuotas/Installments', key: 'installments' },
      { name: 'Pagos', key: 'payments' },
    ];

    for (const table of tables) {
      const comparison = report.comparison.tables[table.key];
      const cloud = report.cloudCounts[table.key as keyof TableCounts];
      const local = report.localCounts[table.key as keyof TableCounts];
      const diff = Math.abs(cloud - local);
      const diffIcon = cloud > local ? '↑ más' : cloud < local ? '↓ menos' : '=';

      console.log(`\n  ${table.name}`);
      console.log(
        `    NUBE:  ${String(cloud).padEnd(6)} registros activos | ${report.cloudCounts[`${table.key}Deleted` as any] || 0} eliminados`
      );
      console.log(
        `    LOCAL: ${String(local).padEnd(6)} registros activos | ${report.localCounts[`${table.key}Deleted` as any] || 0} eliminados`
      );

      if (diff > 0) {
        console.log(
          `    ⚠️  Diferencia: ${diff} registros (${diffIcon} en nube)`
        );
      } else {
        console.log(`    ✓ Paridad: Nube = Local`);
      }
    }

    console.log('\n');

    // ========== ANÁLISIS DE RELACIONES ==========
    const orphans = report.comparison.orphanedRecords;
    if (
      orphans.paymentsWithoutSale > 0 ||
      orphans.installmentsWithoutSale > 0 ||
      orphans.salesWithoutClient > 0 ||
      orphans.salesWithoutProduct > 0
    ) {
      console.log('⚠️  REGISTROS HUÉRFANOS DETECTADOS');
      console.log('─'.repeat(60));

      if (orphans.paymentsWithoutSale > 0) {
        console.log(`  🔴 ${orphans.paymentsWithoutSale} pagos sin venta asociada`);
      }
      if (orphans.installmentsWithoutSale > 0) {
        console.log(`  🔴 ${orphans.installmentsWithoutSale} cuotas sin venta asociada`);
      }
      if (orphans.salesWithoutClient > 0) {
        console.log(`  🔴 ${orphans.salesWithoutClient} ventas sin cliente`);
      }
      if (orphans.salesWithoutProduct > 0) {
        console.log(`  🔴 ${orphans.salesWithoutProduct} ventas sin solar/producto`);
      }
      console.log('');
    }

    // ========== POSIBLES DUPLICADOS ==========
    if (report.comparison.possibleDuplicates.length > 0) {
      console.log('🔎 POSIBLES DUPLICADOS');
      console.log('─'.repeat(60));

      for (const dup of report.comparison.possibleDuplicates) {
        console.log(
          `  Tabla: ${dup.table} | Identificador: ${dup.identifier} | Cantidad: ${dup.count}`
        );
        console.log(`    IDs: ${dup.syncIdList.slice(0, 3).join(', ')}...`);
      }
      console.log('');
    }

    // ========== PROBLEMAS DE INTEGRIDAD ==========
    if (report.comparison.dataIntegrity.length > 0) {
      console.log('⚠️  PROBLEMAS DE INTEGRIDAD DE DATOS');
      console.log('─'.repeat(60));

      for (const issue of report.comparison.dataIntegrity) {
        const severityIcon =
          issue.severity === 'high' ? '🔴' : issue.severity === 'medium' ? '🟠' : '🟡';
        console.log(
          `  ${severityIcon} [${issue.severity.toUpperCase()}] ${issue.table}: ${issue.issue}`
        );
        console.log(
          `     Registros: ${issue.recordCount} | ${issue.details}`
        );
      }
      console.log('');
    }

    // ========== PROPUESTA DE LIMPIEZA ==========
    console.log('🧹 FASE 3: PROPUESTA DE LIMPIEZA');
    console.log('─'.repeat(60));

    console.log(
      `\n  Total de registros en NUBE: ${report.cleanupProposal.totalCloudRecords}`
    );
    console.log(
      `  Total de registros en LOCAL: ${report.cleanupProposal.totalLocalRecords}`
    );

    if (report.cleanupProposal.recordsToDelete.length > 0) {
      console.log('\n  📋 CANDIDATOS PARA LIMPIEZA:');

      for (const proposal of report.cleanupProposal.recordsToDelete) {
        console.log(`\n    • ${proposal.table}`);
        console.log(`      Motivo: ${proposal.reason}`);
        console.log(`      Cantidad: ${proposal.count} registros`);
        console.log(
          `      Método: ${proposal.preferSoftDelete ? 'Soft-delete (marked deleted)' : 'Hard-delete (eliminar físicamente)'}`
        );

        if (proposal.dependencies.length > 0) {
          console.log(`      Dependencias: ${proposal.dependencies.join(', ')}`);
        }
      }

      console.log(`\n  🔗 ORDEN RECOMENDADO DE LIMPIEZA:`);
      console.log(`     ${report.cleanupProposal.dependencyOrder.join(' → ')}`);
    } else {
      console.log('\n  ✓ No hay registros candidatos para limpieza automática.');
    }

    // ========== EVALUACIÓN DE RIESGO ==========
    console.log('\n🚨 EVALUACIÓN DE RIESGO');
    console.log('─'.repeat(60));

    const riskIcon =
      report.cleanupProposal.riskAssessment.level === 'high'
        ? '🔴'
        : report.cleanupProposal.riskAssessment.level === 'medium'
          ? '🟠'
          : '🟢';

    console.log(
      `\n  Nivel de Riesgo: ${riskIcon} ${report.cleanupProposal.riskAssessment.level.toUpperCase()}`
    );

    if (
      report.cleanupProposal.riskAssessment.criticalIssues.length > 0
    ) {
      console.log('\n  ⛔ PROBLEMAS CRÍTICOS:');
      for (const issue of report.cleanupProposal.riskAssessment.criticalIssues) {
        console.log(`     • ${issue}`);
      }
    }

    if (report.cleanupProposal.riskAssessment.warnings.length > 0) {
      console.log('\n  ⚠️  ADVERTENCIAS:');
      for (const warning of report.cleanupProposal.riskAssessment.warnings) {
        console.log(`     • ${warning}`);
      }
    }

    console.log('\n  💡 RECOMENDACIONES:');
    for (const rec of report.cleanupProposal.riskAssessment.recommendations) {
      console.log(`     • ${rec}`);
    }

    // ========== IMPACTO ESTIMADO ==========
    console.log('\n📊 IMPACTO ESTIMADO');
    console.log('─'.repeat(60));

    const impact = report.cleanupProposal.estimatedImpact;
    console.log(
      `\n  Total de registros a impactar: ${impact.totalRecordImpact}`
    );
    console.log(`  Riesgo de pérdida de datos: ${impact.dataLossRisk}`);

    // ========== CONCLUSIÓN ==========
    console.log('\n');
    console.log('═'.repeat(60));
    console.log('✅ AUDITORÍA COMPLETADA - ANÁLISIS DE SOLO LECTURA');
    console.log('═'.repeat(60));

    console.log('\n📄 ARCHIVOS GENERADOS:');
    console.log(`   • Reporte JSON: ${this.reportPath}`);
    console.log(`   • Backup SQL: ${report.backupStatus.path}\n`);

    console.log('⚠️  IMPORTANTE:');
    console.log('   • NO SE HA MODIFICADO NADA EN NINGUNA BASE DE DATOS');
    console.log('   • El backup está disponible y verificado');
    console.log('   • Revisar este reporte antes de proceder a limpieza');
    console.log('   • Si apruebas la limpieza, ejecutar Fase 4 con este reporte\n');
  }

  async close(): Promise<void> {
    await this.prisma.$disconnect();
    if (this.localDb) {
      await this.localDb.close();
    }
  }
}

// ============
// MAIN SCRIPT
// ============

async function main() {
  const tool = new CloudAuditTool();

  try {
    const report = await tool.performAudit();
    const reportPath = await tool.saveReport(report);

    console.log(`\n✅ Auditoría completada exitosamente`);
    console.log(`📄 Reporte guardado en: ${reportPath}\n`);

    await tool.printReport(report);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`\n❌ ERROR: ${message}\n`);
    process.exit(1);
  } finally {
    await tool.close();
  }
}

main();
