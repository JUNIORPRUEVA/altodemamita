import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares/features/auth/domain/permission_model.dart';
import 'package:sistema_solares/features/auth/domain/user_model.dart';
import 'package:sistema_solares/features/payments/domain/payment_history_item.dart';
import 'package:sistema_solares/features/sales/domain/sale_summary.dart';

PermissionModel _permission(
  String module, {
  bool read = false,
  bool create = false,
  bool update = false,
  bool delete = false,
  bool cancel = false,
}) {
  return PermissionModel(
    module: module,
    read: read,
    create: create,
    update: update,
    delete: delete,
    cancel: cancel,
  );
}

UserModel _user(UserRole role, List<PermissionModel> permissions) {
  return UserModel(
    id: 1,
    nombre: 'Operador',
    email: 'operador@test.local',
    passwordHash: '',
    passwordResetRequired: false,
    role: role,
    permissions: permissions,
    activo: true,
    fechaCreacion: DateTime(2026, 1, 1),
    fechaActualizacion: DateTime(2026, 1, 1),
  );
}

void main() {
  group('permiso granular de anulacion de pagos', () {
    test('interpreta la accion "anular" del catalogo y la expone en el modelo', () {
      final permission = PermissionModel.fromLegacy(
        module: PermissionCatalog.payments,
        actions: ['ver', 'anular'],
      );

      expect(permission.cancel, isTrue);
      expect(permission.allows(PermissionAction.cancel), isTrue);
      expect(permission.toLegacyActions(), contains('anular'));
    });

    test('no confunde anular con crear, ver o editar pagos', () {
      final permission = PermissionModel.fromLegacy(
        module: PermissionCatalog.payments,
        actions: ['ver', 'crear', 'editar'],
      );

      expect(permission.cancel, isFalse);
      expect(permission.allows(PermissionAction.cancel), isFalse);
    });

    test('administrador puede anular sin permisos explicitos', () {
      final admin = _user(UserRole.admin, const <PermissionModel>[]);

      expect(admin.canCancelPayments, isTrue);
    });

    test('usuario con permiso de anulacion puede anular', () {
      final operator = _user(UserRole.user, [
        _permission(PermissionCatalog.payments, read: true, cancel: true),
      ]);

      expect(operator.canCancelPayments, isTrue);
    });

    test('usuario con permiso legado de eliminacion NO puede anular por si mismo (requiere autorizacion)', () {
      final operator = _user(UserRole.user, [
        _permission(PermissionCatalog.payments, read: true, delete: true),
      ]);

      expect(operator.canCancelPayments, isFalse);
    });

    test('usuario sin permiso de anulacion requiere autorizacion', () {
      final operator = _user(UserRole.user, [
        _permission(
          PermissionCatalog.payments,
          read: true,
          create: true,
          update: true,
        ),
      ]);

      expect(operator.canCancelPayments, isFalse);
    });

    test('un permiso de anulacion en otro modulo no habilita pagos', () {
      final operator = _user(UserRole.user, [
        _permission(PermissionCatalog.sales, cancel: true),
      ]);

      expect(operator.canCancelPayments, isFalse);
    });
  });

  group('historial de pagos anulados', () {
    test('un pago activo no se considera anulado', () {
      final payment = PaymentHistoryItem(
        id: 1,
        saleId: 1,
        clientId: 1,
        paymentDate: DateTime(2026, 9, 1),
        amountPaid: 25000,
        paymentMethod: 'efectivo',
        paymentType: 'abono_inicial',
      );

      expect(payment.isAnnulled, isFalse);
      expect(payment.annulledByName, isNull);
    });

    test('un pago anulado conserva monto, motivo y auditoria', () {
      final payment = PaymentHistoryItem(
        id: 1,
        saleId: 1,
        clientId: 1,
        paymentDate: DateTime(2026, 9, 1),
        amountPaid: 25000,
        paymentMethod: 'efectivo',
        paymentType: 'abono_inicial',
        annulledAt: DateTime(2026, 9, 2),
        annulledByName: 'Administradora',
        annulmentReason: 'Monto incorrecto',
        authorizedByAdmin: true,
      );

      expect(payment.isAnnulled, isTrue);
      expect(payment.amountPaid, 25000);
      expect(payment.annulmentReason, 'Monto incorrecto');
      expect(payment.authorizedByAdmin, isTrue);
    });
  });

  group('clasificacion de venta definitiva en el resumen de venta', () {
    SaleSummary summary({bool isFullyPaid = false}) {
      return SaleSummary(
        id: 1,
        syncStatus: 'synced',
        clientName: 'Cliente',
        clientDocumentId: '001-0000000-1',
        lotDisplayCode: 'M1-S1',
        saleDate: DateTime(2026, 1, 1),
        salePrice: 250000,
        downPaymentAmount: 25000,
        requiredInitialPayment: 25000,
        paidInitialPayment: 25000,
        pendingInitialPayment: 0,
        paidApartadoPayment: 0,
        financedBalance: 225000,
        pendingBalance: 0,
        monthlyInterest: 0,
        installmentCount: 12,
        status: 'pagada',
        generatedInstallments: 12,
        isFullyPaid: isFullyPaid,
      );
    }

    test('expone la etiqueta compacta exigida por operacion', () {
      expect(summary(isFullyPaid: true).settlementLabel,
          'Saldada · Venta definitiva');
    });

    test('solo marca como definitiva la venta clasificada por el backend', () {
      expect(summary(isFullyPaid: true).isFullyPaid, isTrue);
      expect(summary().isFullyPaid, isFalse);
    });
  });
}
