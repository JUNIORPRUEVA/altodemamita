import { Test, TestingModule } from '@nestjs/testing';
import { PrismaService } from 'src/shared/services/prisma.service';
import { ClientsService } from 'src/modules/clients/application/services/clients.service';
import { SalesService } from 'src/modules/sales/application/services/sales.service';
import { ProductsService } from 'src/modules/products/application/services/products.service';
import { SellersService } from 'src/modules/sellers/application/services/sellers.service';
import { ForeignKeyConstraintViolationException } from '@nestjs/common';

describe('Orphan Record FK Constraints (FASE 3 - PASO 3)', () => {
  let module: TestingModule;
  let prisma: PrismaService;
  let clientsService: ClientsService;
  let salesService: SalesService;
  let productsService: ProductsService;
  let sellersService: SellersService;

  beforeAll(async () => {
    module = await Test.createTestingModule({
      providers: [
        PrismaService,
        ClientsService,
        SalesService,
        ProductsService,
        SellersService,
      ],
    }).compile();

    prisma = module.get<PrismaService>(PrismaService);
    clientsService = module.get<ClientsService>(ClientsService);
    salesService = module.get<SalesService>(SalesService);
    productsService = module.get<ProductsService>(ProductsService);
    sellersService = module.get<SellersService>(SellersService);
  });

  afterAll(async () => {
    await module.close();
  });

  it('should REJECT delete of CLIENT if it has active SALES (onDelete: Restrict)', async () => {
    // Setup: Create a client
    const client = await prisma.client.create({
      data: {
        syncId: `test-client-${Date.now()}`,
        firstName: 'Test',
        lastName: 'Client',
        documentId: `DOC-${Date.now()}`,
        syncStatus: 'synced',
      },
    });

    // Create a user, product for the sale
    const user = await prisma.user.create({
      data: {
        syncId: `test-user-${Date.now()}`,
        email: `user-${Date.now()}@test.com`,
        username: `user-${Date.now()}`,
        fullName: 'Test User',
        passwordHash: 'hash123',
        syncStatus: 'synced',
      },
    });

    const product = await prisma.product.create({
      data: {
        syncId: `test-product-${Date.now()}`,
        code: `PROD-${Date.now()}`,
        name: 'Test Product',
        price: 1000.0,
        syncStatus: 'synced',
      },
    });

    // Create a sale for the client
    const sale = await prisma.sale.create({
      data: {
        syncId: `test-sale-${Date.now()}`,
        clientId: client.id,
        userId: user.id,
        productId: product.id,
        saleDate: new Date(),
        principalAmount: 1000.0,
        financedAmount: 1000.0,
        downPayment: 0,
        interestRate: 5.5,
        totalAmount: 1100.0,
        termMonths: 12,
        outstandingBalance: 1100.0,
        syncStatus: 'synced',
      },
    });

    // Attempt to delete the client - should FAIL with FK constraint violation
    let deleteError: Error | null = null;
    try {
      await prisma.client.delete({
        where: { id: client.id },
      });
    } catch (error) {
      deleteError = error as Error;
    }

    // Assert that delete was rejected
    expect(deleteError).toBeDefined();
    expect(deleteError?.message).toContain(
      'delete or update on table' || 'Foreign key constraint failed' || 'violates foreign key constraint',
    );

    console.log(`✅ PASS: Client with active sales CANNOT be deleted (FK protected)`);

    // Cleanup
    await prisma.sale.delete({ where: { id: sale.id } });
    await prisma.client.delete({ where: { id: client.id } });
    await prisma.user.delete({ where: { id: user.id } });
    await prisma.product.delete({ where: { id: product.id } });
  });

  it('should REJECT delete of SELLER if it has active SALES (onDelete: Restrict)', async () => {
    // Setup
    const seller = await prisma.seller.create({
      data: {
        syncId: `test-seller-${Date.now()}`,
        name: 'Test Seller',
        documentId: `SEL-${Date.now()}`,
        syncStatus: 'synced',
      },
    });

    const client = await prisma.client.create({
      data: {
        syncId: `test-client-${Date.now()}`,
        firstName: 'Test',
        lastName: 'Client',
        syncStatus: 'synced',
      },
    });

    const user = await prisma.user.create({
      data: {
        syncId: `test-user-${Date.now()}`,
        email: `user-${Date.now()}@test.com`,
        username: `user-${Date.now()}`,
        fullName: 'Test User',
        passwordHash: 'hash123',
        syncStatus: 'synced',
      },
    });

    const product = await prisma.product.create({
      data: {
        syncId: `test-product-${Date.now()}`,
        code: `PROD-${Date.now()}`,
        name: 'Test Product',
        price: 1000.0,
        syncStatus: 'synced',
      },
    });

    // Create sale with seller
    const sale = await prisma.sale.create({
      data: {
        syncId: `test-sale-${Date.now()}`,
        clientId: client.id,
        userId: user.id,
        productId: product.id,
        sellerId: seller.id,
        saleDate: new Date(),
        principalAmount: 1000.0,
        financedAmount: 1000.0,
        downPayment: 0,
        interestRate: 5.5,
        totalAmount: 1100.0,
        termMonths: 12,
        outstandingBalance: 1100.0,
        syncStatus: 'synced',
      },
    });

    // Attempt to delete seller - should FAIL
    let deleteError: Error | null = null;
    try {
      await prisma.seller.delete({
        where: { id: seller.id },
      });
    } catch (error) {
      deleteError = error as Error;
    }

    expect(deleteError).toBeDefined();
    expect(deleteError?.message).toContain(
      'delete or update on table' || 'Foreign key constraint failed' || 'violates foreign key constraint',
    );

    console.log(`✅ PASS: Seller with active sales CANNOT be deleted (FK protected)`);

    // Cleanup
    await prisma.sale.delete({ where: { id: sale.id } });
    await prisma.seller.delete({ where: { id: seller.id } });
    await prisma.client.delete({ where: { id: client.id } });
    await prisma.user.delete({ where: { id: user.id } });
    await prisma.product.delete({ where: { id: product.id } });
  });

  it('should REJECT delete of PRODUCT if it has active SALES (onDelete: Restrict)', async () => {
    // Setup
    const product = await prisma.product.create({
      data: {
        syncId: `test-product-${Date.now()}`,
        code: `PROD-${Date.now()}`,
        name: 'Test Product',
        price: 5000.0,
        syncStatus: 'synced',
      },
    });

    const client = await prisma.client.create({
      data: {
        syncId: `test-client-${Date.now()}`,
        firstName: 'Test',
        lastName: 'Client',
        syncStatus: 'synced',
      },
    });

    const user = await prisma.user.create({
      data: {
        syncId: `test-user-${Date.now()}`,
        email: `user-${Date.now()}@test.com`,
        username: `user-${Date.now()}`,
        fullName: 'Test User',
        passwordHash: 'hash123',
        syncStatus: 'synced',
      },
    });

    // Create sale with product
    const sale = await prisma.sale.create({
      data: {
        syncId: `test-sale-${Date.now()}`,
        clientId: client.id,
        userId: user.id,
        productId: product.id,
        saleDate: new Date(),
        principalAmount: 5000.0,
        financedAmount: 5000.0,
        downPayment: 0,
        interestRate: 5.5,
        totalAmount: 5500.0,
        termMonths: 24,
        outstandingBalance: 5500.0,
        syncStatus: 'synced',
      },
    });

    // Attempt to delete product - should FAIL
    let deleteError: Error | null = null;
    try {
      await prisma.product.delete({
        where: { id: product.id },
      });
    } catch (error) {
      deleteError = error as Error;
    }

    expect(deleteError).toBeDefined();
    expect(deleteError?.message).toContain(
      'delete or update on table' || 'Foreign key constraint failed' || 'violates foreign key constraint',
    );

    console.log(`✅ PASS: Product with active sales CANNOT be deleted (FK protected)`);

    // Cleanup
    await prisma.sale.delete({ where: { id: sale.id } });
    await prisma.product.delete({ where: { id: product.id } });
    await prisma.client.delete({ where: { id: client.id } });
    await prisma.user.delete({ where: { id: user.id } });
  });

  it('should REJECT delete of SALE if it has INSTALLMENTS or PAYMENTS (onDelete: Restrict)', async () => {
    // Setup all prerequisites
    const client = await prisma.client.create({
      data: {
        syncId: `test-client-${Date.now()}`,
        firstName: 'Test',
        lastName: 'Client',
        syncStatus: 'synced',
      },
    });

    const user = await prisma.user.create({
      data: {
        syncId: `test-user-${Date.now()}`,
        email: `user-${Date.now()}@test.com`,
        username: `user-${Date.now()}`,
        fullName: 'Test User',
        passwordHash: 'hash123',
        syncStatus: 'synced',
      },
    });

    const product = await prisma.product.create({
      data: {
        syncId: `test-product-${Date.now()}`,
        code: `PROD-${Date.now()}`,
        name: 'Test Product',
        price: 2000.0,
        syncStatus: 'synced',
      },
    });

    const sale = await prisma.sale.create({
      data: {
        syncId: `test-sale-${Date.now()}`,
        clientId: client.id,
        userId: user.id,
        productId: product.id,
        saleDate: new Date(),
        principalAmount: 2000.0,
        financedAmount: 2000.0,
        downPayment: 0,
        interestRate: 5.5,
        totalAmount: 2200.0,
        termMonths: 12,
        outstandingBalance: 2200.0,
        syncStatus: 'synced',
      },
    });

    // Create installments for the sale
    const installment = await prisma.installment.create({
      data: {
        syncId: `test-inst-${Date.now()}`,
        saleId: sale.id,
        installmentNumber: 1,
        dueDate: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
        amount: 183.33,
        principalAmount: 166.67,
        interestAmount: 16.66,
        syncStatus: 'synced',
      },
    });

    // Attempt to delete sale - should FAIL because installment exists
    let deleteError: Error | null = null;
    try {
      await prisma.sale.delete({
        where: { id: sale.id },
      });
    } catch (error) {
      deleteError = error as Error;
    }

    expect(deleteError).toBeDefined();
    expect(deleteError?.message).toContain(
      'delete or update on table' || 'Foreign key constraint failed' || 'violates foreign key constraint',
    );

    console.log(`✅ PASS: Sale with installments CANNOT be deleted (FK protected)`);

    // Cleanup
    await prisma.installment.delete({ where: { id: installment.id } });
    await prisma.sale.delete({ where: { id: sale.id } });
    await prisma.client.delete({ where: { id: client.id } });
    await prisma.user.delete({ where: { id: user.id } });
    await prisma.product.delete({ where: { id: product.id } });
  });

  it('should allow SOFT DELETE of entities with Restrict FK constraints', async () => {
    // Setup
    const client = await prisma.client.create({
      data: {
        syncId: `test-client-${Date.now()}`,
        firstName: 'Test',
        lastName: 'Client',
        syncStatus: 'synced',
      },
    });

    const user = await prisma.user.create({
      data: {
        syncId: `test-user-${Date.now()}`,
        email: `user-${Date.now()}@test.com`,
        username: `user-${Date.now()}`,
        fullName: 'Test User',
        passwordHash: 'hash123',
        syncStatus: 'synced',
      },
    });

    const product = await prisma.product.create({
      data: {
        syncId: `test-product-${Date.now()}`,
        code: `PROD-${Date.now()}`,
        name: 'Test Product',
        price: 1500.0,
        syncStatus: 'synced',
      },
    });

    const sale = await prisma.sale.create({
      data: {
        syncId: `test-sale-${Date.now()}`,
        clientId: client.id,
        userId: user.id,
        productId: product.id,
        saleDate: new Date(),
        principalAmount: 1500.0,
        financedAmount: 1500.0,
        downPayment: 0,
        interestRate: 5.5,
        totalAmount: 1650.0,
        termMonths: 12,
        outstandingBalance: 1650.0,
        syncStatus: 'synced',
      },
    });

    // Soft-delete client (UPDATE deleted_at, not hard-delete)
    const now = new Date();
    await prisma.client.update({
      where: { id: client.id },
      data: {
        deletedAt: now,
        syncStatus: 'synced',
      },
    });

    // Verify client is soft-deleted but sale still exists
    const deletedClient = await prisma.client.findUnique({
      where: { id: client.id },
    });

    const saleStillExists = await prisma.sale.findUnique({
      where: { id: sale.id },
    });

    expect(deletedClient?.deletedAt).toBeDefined();
    expect(saleStillExists).toBeDefined();
    expect(saleStillExists?.clientId).toBe(client.id);

    console.log(`✅ PASS: Soft-delete works correctly with Restrict FK constraints`);

    // Cleanup
    await prisma.sale.delete({ where: { id: sale.id } });
    await prisma.client.delete({ where: { id: client.id } });
    await prisma.user.delete({ where: { id: user.id } });
    await prisma.product.delete({ where: { id: product.id } });
  });
});
