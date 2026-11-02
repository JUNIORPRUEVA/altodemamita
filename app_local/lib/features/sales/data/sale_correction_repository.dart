import '../../../core/network/backend_api_client.dart';
import '../../../core/system/system_config_service.dart';
import '../domain/sale_correction.dart';

/// FASE 03 — Acceso a los endpoints OWNER de corrección de ventas.
///
/// La venta usa directamente su `syncId` autoritativo (no depende del registro
/// de ids en memoria). Si falta, se bloquea la operación (fail-closed).
class SaleCorrectionRepository {
  SaleCorrectionRepository({
    BackendApiClient? apiClient,
    SystemConfigService? systemConfigService,
  }) : _apiClient = apiClient ?? BackendApiClient(),
       _systemConfigService = systemConfigService ?? SystemConfigService.instance;

  final BackendApiClient _apiClient;
  final SystemConfigService _systemConfigService;

  Future<SaleCorrectionPreview> preview({
    required String saleSyncId,
    required String action,
    DateTime? saleDate,
    double? totalPrice,
    double? initialPaidAmount,
    int? installmentCount,
    double? monthlyInterestRate,
    String? clientSyncId,
    String? lotSyncId,
  }) async {
    if (saleSyncId.trim().isEmpty) {
      return SaleCorrectionPreview.blocked(
        'Esta venta aún no está sincronizada con el servidor: no se puede corregir.',
      );
    }
    final query = <String, String>{'action': action};
    if (saleDate != null) query['saleDate'] = saleDate.toUtc().toIso8601String();
    if (totalPrice != null) query['totalPrice'] = totalPrice.toStringAsFixed(2);
    if (initialPaidAmount != null) {
      query['initialPaidAmount'] = initialPaidAmount.toStringAsFixed(2);
    }
    if (installmentCount != null) {
      query['installmentCount'] = installmentCount.toString();
    }
    if (monthlyInterestRate != null) {
      query['monthlyInterestRate'] = monthlyInterestRate.toStringAsFixed(2);
    }
    if (clientSyncId != null) query['clientId'] = clientSyncId;
    if (lotSyncId != null) query['lotId'] = lotSyncId;
    try {
      final response = await _apiClient.get(
        '/authoritative/sales/$saleSyncId/corrections/preview',
        queryParameters: query,
      );
      final data = response is Map ? response['data'] : null;
      final map = data is Map
          ? data.map((key, value) => MapEntry(key.toString(), value))
          : <String, dynamic>{};
      return SaleCorrectionPreview.fromMap(map);
    } catch (error) {
      return SaleCorrectionPreview.blocked(
        'No se pudo validar la corrección con el servidor: ${error.toString()}',
      );
    }
  }

  Future<Map<String, dynamic>> apply({
    required String saleSyncId,
    required String action,
    required String reason,
    required int expectedSaleVersion,
    DateTime? saleDate,
    double? totalPrice,
    double? initialPaidAmount,
    int? installmentCount,
    double? monthlyInterestRate,
    String? clientSyncId,
    String? lotSyncId,
    String? idempotencyKey,
  }) async {
    _systemConfigService.ensureWritable();
    if (saleSyncId.trim().isEmpty) {
      throw const BackendApiException(
        'Esta venta aún no está sincronizada con el servidor.',
      );
    }
    final response = await _apiClient.post(
      '/authoritative/sales/$saleSyncId/corrections',
      idempotencyKey:
          idempotencyKey ??
          'desktop-sale-correction-$saleSyncId-$action-'
              '${DateTime.now().microsecondsSinceEpoch}',
      body: {
        'action': action,
        'reason': reason,
        'expectedSaleVersion': expectedSaleVersion,
        'saleDate': ?saleDate?.toUtc().toIso8601String(),
        'totalPrice': ?totalPrice,
        'initialPaidAmount': ?initialPaidAmount,
        'installmentCount': ?installmentCount,
        'monthlyInterestRate': ?monthlyInterestRate,
        'clientId': ?clientSyncId,
        'lotId': ?lotSyncId,
      },
    );
    final data = response is Map ? response['data'] : null;
    return data is Map
        ? data.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> fetchAudit({required String saleSyncId}) async {
    if (saleSyncId.trim().isEmpty) {
      throw const BackendApiException(
        'Esta venta aún no está sincronizada con el servidor: no hay auditoría.',
      );
    }
    final response = await _apiClient.get(
      '/authoritative/sales/$saleSyncId/corrections/audit',
    );
    final data = response is Map ? response['data'] : null;
    return data is Map
        ? data.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};
  }
}
