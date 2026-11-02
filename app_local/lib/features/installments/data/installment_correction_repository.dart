import '../../../core/network/backend_api_client.dart';
import '../../../core/network/backend_entity_id_registry.dart';
import '../../../core/system/system_config_service.dart';
import '../domain/installment_correction.dart';

/// FASE 02 — Acceso a los endpoints OWNER de gestion del cronograma.
///
/// Los identificadores se resuelven contra el registro de ids remotos: si una
/// cuota o venta aun no esta sincronizada, la operacion se bloquea (fail-closed)
/// en lugar de adivinar la identidad autoritativa.
class InstallmentCorrectionRepository {
  InstallmentCorrectionRepository({
    BackendApiClient? apiClient,
    BackendEntityIdRegistry? idRegistry,
    SystemConfigService? systemConfigService,
  }) : _apiClient = apiClient ?? BackendApiClient(),
       _idRegistry = idRegistry ?? BackendEntityIdRegistry.instance,
       _systemConfigService = systemConfigService ?? SystemConfigService.instance;

  final BackendApiClient _apiClient;
  final BackendEntityIdRegistry _idRegistry;
  final SystemConfigService _systemConfigService;

  String? _saleRemoteId(int saleId) =>
      _idRegistry.resolveRemoteId('sales', saleId);

  String? _installmentRemoteId(int installmentId) =>
      _idRegistry.resolveRemoteId('installments', installmentId);

  Future<InstallmentCorrectionPreview> preview({
    required int saleId,
    required String action,
    int? installmentId,
    DateTime? dueDate,
    double? principalAmount,
    double? interestAmount,
    int? installmentCount,
    DateTime? firstDueDate,
  }) async {
    final saleRemoteId = _saleRemoteId(saleId);
    if (saleRemoteId == null || saleRemoteId.isEmpty) {
      return InstallmentCorrectionPreview.blocked(
        'Esta venta aun no esta sincronizada con el servidor: no se puede corregir el cronograma.',
      );
    }
    final query = <String, String>{'action': action};
    if (installmentId != null) {
      final remote = _installmentRemoteId(installmentId);
      if (remote == null || remote.isEmpty) {
        return InstallmentCorrectionPreview.blocked(
          'Esta cuota aun no esta sincronizada con el servidor.',
        );
      }
      query['installmentId'] = remote;
    }
    if (dueDate != null) query['dueDate'] = dueDate.toUtc().toIso8601String();
    if (principalAmount != null) {
      query['principalAmount'] = principalAmount.toStringAsFixed(2);
    }
    if (interestAmount != null) {
      query['interestAmount'] = interestAmount.toStringAsFixed(2);
    }
    if (installmentCount != null) {
      query['installmentCount'] = installmentCount.toString();
    }
    if (firstDueDate != null) {
      query['firstDueDate'] = firstDueDate.toUtc().toIso8601String();
    }
    try {
      final response = await _apiClient.get(
        '/authoritative/sales/$saleRemoteId/installment-corrections/preview',
        queryParameters: query,
      );
      final data = response is Map ? response['data'] : null;
      final map = data is Map
          ? data.map((key, value) => MapEntry(key.toString(), value))
          : <String, dynamic>{};
      return InstallmentCorrectionPreview.fromMap(map);
    } catch (error) {
      return InstallmentCorrectionPreview.blocked(
        'No se pudo validar la correccion con el servidor: ${error.toString()}',
      );
    }
  }

  Future<Map<String, dynamic>> apply({
    required int saleId,
    required String action,
    required String reason,
    required int expectedSaleVersion,
    int? installmentId,
    DateTime? dueDate,
    double? principalAmount,
    double? interestAmount,
    int? installmentCount,
    DateTime? firstDueDate,
    String? idempotencyKey,
  }) async {
    _systemConfigService.ensureWritable();
    final saleRemoteId = _saleRemoteId(saleId);
    if (saleRemoteId == null || saleRemoteId.isEmpty) {
      throw const BackendApiException(
        'Esta venta aun no esta sincronizada con el servidor.',
      );
    }
    final remoteInstallment = installmentId == null
        ? null
        : _installmentRemoteId(installmentId);
    if (installmentId != null &&
        (remoteInstallment == null || remoteInstallment.isEmpty)) {
      throw const BackendApiException(
        'Esta cuota aun no esta sincronizada con el servidor.',
      );
    }
    final response = await _apiClient.post(
      '/authoritative/sales/$saleRemoteId/installment-corrections',
      idempotencyKey:
          idempotencyKey ??
          'desktop-installment-$saleId-$action-'
              '${DateTime.now().microsecondsSinceEpoch}',
      body: {
        'action': action,
        'reason': reason,
        'expectedSaleVersion': expectedSaleVersion,
        'installmentId': ?remoteInstallment,
        'dueDate': ?dueDate?.toUtc().toIso8601String(),
        'principalAmount': ?principalAmount,
        'interestAmount': ?interestAmount,
        'installmentCount': ?installmentCount,
        'firstDueDate': ?firstDueDate?.toUtc().toIso8601String(),
      },
    );
    final data = response is Map ? response['data'] : null;
    return data is Map
        ? data.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> fetchAudit({required int saleId}) async {
    final saleRemoteId = _saleRemoteId(saleId);
    if (saleRemoteId == null || saleRemoteId.isEmpty) {
      throw const BackendApiException(
        'Esta venta aun no esta sincronizada con el servidor: no hay auditoria.',
      );
    }
    final response = await _apiClient.get(
      '/authoritative/sales/$saleRemoteId/installment-corrections/audit',
    );
    final data = response is Map ? response['data'] : null;
    return data is Map
        ? data.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};
  }
}
