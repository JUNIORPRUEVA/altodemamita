import 'package:flutter/foundation.dart';

import '../../../core/resilience/friendly_error_messages.dart';
import '../../clients/data/client_repository.dart';
import '../../clients/domain/client.dart';
import '../../lots/data/lot_repository.dart';
import '../../lots/domain/lot.dart';
import '../../settings/data/settings_repository.dart';
import '../data/sales_repository.dart';
import '../data/seller_repository.dart';
import '../domain/sale_defaults.dart';
import '../domain/sale_detail.dart';
import '../domain/sale_draft.dart';
import '../domain/sale_summary.dart';
import '../domain/seller.dart';

class SalesController extends ChangeNotifier {
  SalesController({
    required SalesRepository salesRepository,
    required ClientRepository clientRepository,
    required LotRepository lotRepository,
    required SellerRepository sellerRepository,
    required SettingsRepository settingsRepository,
  }) : _salesRepository = salesRepository,
       _clientRepository = clientRepository,
       _lotRepository = lotRepository,
       _sellerRepository = sellerRepository,
       _settingsRepository = settingsRepository;

  final SalesRepository _salesRepository;
  final ClientRepository _clientRepository;
  final LotRepository _lotRepository;
  final SellerRepository _sellerRepository;
  final SettingsRepository _settingsRepository;

  bool isLoading = false;
  bool isSaving = false;
  String currentQuery = '';
  FriendlyErrorMessage? loadError;
  List<SaleSummary> sales = const [];
  List<Client> clients = const [];
  List<Lot> availableLots = const [];
  List<Seller> sellers = const [];
  SaleDefaults defaults = const SaleDefaults(
    downPaymentPercentage: 10,
    monthlyInterest: 1,
    installmentCount: 12,
  );

  Future<void> load({String? query}) async {
    if (query != null) {
      currentQuery = query;
    }

    isLoading = true;
    loadError = null;
    notifyListeners();

    try {
      final settings = await _settingsRepository.fetchByKeysWithDefaults({
        SettingsRepository.saleDefaultDownPaymentKey: '10',
        SettingsRepository.saleDefaultMonthlyInterestKey: '1',
        SettingsRepository.saleDefaultInstallmentCountKey: '12',
      });

      final results = await Future.wait([
        _salesRepository.fetchAll(query: currentQuery),
        _clientRepository.fetchAll(),
        _lotRepository.fetchAvailable(),
        _sellerRepository.getAll(),
      ]);

      sales = results[0] as List<SaleSummary>;
      clients = results[1] as List<Client>;
      availableLots = results[2] as List<Lot>;
      sellers = results[3] as List<Seller>;
      defaults = SaleDefaults(
        downPaymentPercentage: _parseDouble(
          settings[SettingsRepository.saleDefaultDownPaymentKey]?.value,
          fallback: 10,
        ),
        monthlyInterest: _parseDouble(
          settings[SettingsRepository.saleDefaultMonthlyInterestKey]?.value,
          fallback: 1,
        ),
        installmentCount: _parseInt(
          settings[SettingsRepository.saleDefaultInstallmentCountKey]?.value,
          fallback: 12,
        ),
      );
    } catch (error) {
      loadError = FriendlyErrorMessages.moduleLoad('ventas', error);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<int?> createSale(SaleDraft draft) async {
    isSaving = true;
    loadError = null;
    notifyListeners();

    try {
      final saleId = await _salesRepository.createSale(draft);
      await load(query: currentQuery);
      return saleId;
    } catch (error) {
      FriendlyErrorMessages.forOperation(
        'guardar la venta',
        error,
        module: 'ventas',
      );
      return null;
    } finally {
      isSaving = false;
      notifyListeners();
    }
  }

  Future<String?> updateSale(int saleId, SaleDraft draft) async {
    isSaving = true;
    notifyListeners();

    try {
      await _salesRepository.updateSale(saleId, draft);
      await load(query: currentQuery);
      return null;
    } catch (error) {
      return FriendlyErrorMessages.forOperation(
        'actualizar la venta',
        error,
        module: 'ventas',
      );
    } finally {
      isSaving = false;
      notifyListeners();
    }
  }

  Future<String?> deleteSale(int saleId) async {
    isSaving = true;
    notifyListeners();

    try {
      await _salesRepository.deleteSale(saleId);
      await load(query: currentQuery);
      return null;
    } catch (error) {
      return FriendlyErrorMessages.forOperation(
        'eliminar la venta',
        error,
        module: 'ventas',
      );
    } finally {
      isSaving = false;
      notifyListeners();
    }
  }

  Future<SaleDetail?> fetchDetail(int saleId) {
    return _salesRepository.fetchDetail(saleId);
  }

  double _parseDouble(String? value, {required double fallback}) {
    if (value == null || value.trim().isEmpty) {
      return fallback;
    }

    return double.tryParse(value.replaceAll(',', '.').trim()) ?? fallback;
  }

  int _parseInt(String? value, {required int fallback}) {
    if (value == null || value.trim().isEmpty) {
      return fallback;
    }

    return int.tryParse(value.trim()) ?? fallback;
  }
}
