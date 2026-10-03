import 'package:flutter/foundation.dart';

import '../data/installments_repository.dart';
import '../domain/installment_detail.dart';

class InstallmentsController extends ChangeNotifier {
  InstallmentsController({
    required InstallmentsRepository installmentsRepository,
  }) : _installmentsRepository = installmentsRepository;

  final InstallmentsRepository _installmentsRepository;
  static final Map<String, _InstallmentsMemorySnapshot> _lastGoodByScope = {};

  List<InstallmentDetail> _installments = const [];
  List<InstallmentDetail> _filteredInstallments = const [];
  SaleInstallmentsSummary? _selectedSaleSummary;
  bool _isLoading = false;
  bool _isRefreshing = false;
  bool _refreshFailed = false;
  String _searchQuery = '';
  String? _selectedStatus;
  int _generation = 0;

  // Getters
  List<InstallmentDetail> get installments => _filteredInstallments;
  SaleInstallmentsSummary? get selectedSaleSummary => _selectedSaleSummary;
  bool get isLoading => _isLoading;
  bool get isRefreshing => _isRefreshing;
  bool get refreshFailed => _refreshFailed;
  bool get hasVisibleData => _filteredInstallments.isNotEmpty;
  String get searchQuery => _searchQuery;
  String? get selectedStatus => _selectedStatus;

  // Calculated statistics
  double get totalFinanced =>
      _selectedSaleSummary?.totalFinanced ??
      _filteredInstallments.fold(0.0, (sum, inst) => sum + inst.totalAmount);

  double get totalPaid =>
      _selectedSaleSummary?.totalPaid ??
      _filteredInstallments.fold(0.0, (sum, inst) => sum + inst.paidAmount);

  double get totalPending =>
      _selectedSaleSummary?.totalPending ??
      _filteredInstallments.fold(
        0.0,
        (sum, inst) => sum + inst.remainingAmount,
      );

  int get totalInstallments =>
      _selectedSaleSummary?.totalInstallments ?? _filteredInstallments.length;

  int get paidInstallments =>
      _selectedSaleSummary?.paidInstallments ??
      _filteredInstallments
          .where((inst) => inst.remainingAmount <= 0.009)
          .length;

  int get pendingInstallments => totalInstallments - paidInstallments;

  // Load all installments
  Future<void> load() async {
    final generation = ++_generation;
    final scope = _allScope;
    final hadVisible = _installments.isNotEmpty;
    final memoryApplied = _restoreLastGood(scope);
    _isLoading = !hadVisible && !memoryApplied;
    _isRefreshing = false;
    _refreshFailed = false;
    notifyListeners();

    if (!hadVisible && !memoryApplied) {
      try {
        final cached = await _installmentsRepository.fetchCachedList();
        if (generation != _generation) {
          return;
        }
        if (cached.isNotEmpty) {
          _installments = cached;
          _selectedSaleSummary = null;
          _applyFilters();
          _rememberLastGood(scope);
          _isLoading = false;
          notifyListeners();
        }
      } catch (_) {
        // Cache best-effort: si falla, se continua con la lectura viva.
      }
    }

    try {
      final next = await _installmentsRepository.getAll();
      if (generation != _generation) {
        return;
      }
      _installments = next;
      _selectedSaleSummary = null;
      _applyFilters();
      _rememberLastGood(scope);
    } catch (e) {
      _refreshFailed = _installments.isNotEmpty;
      if (kDebugMode) {
        print('Error loading installments: $e');
      }
    } finally {
      if (generation == _generation) {
        _isLoading = false;
        _isRefreshing = false;
        notifyListeners();
      }
    }
  }

  // Load installments for a specific sale
  Future<void> loadBySaleId(int saleId) async {
    final generation = ++_generation;
    final scope = _saleScope(saleId);
    final hadVisible = _installments.isNotEmpty;
    final memoryApplied = _restoreLastGood(scope);
    _isLoading = !hadVisible && !memoryApplied;
    _isRefreshing = false;
    _refreshFailed = false;
    notifyListeners();

    try {
      final results = await Future.wait<Object?>([
        _installmentsRepository.getBySaleId(saleId),
        _installmentsRepository.getSaleSummary(saleId),
      ]);
      if (generation != _generation) {
        return;
      }
      _installments = results[0] as List<InstallmentDetail>;
      _selectedSaleSummary = results[1] as SaleInstallmentsSummary?;
      _applyFilters();
      _rememberLastGood(scope);
    } catch (e) {
      _refreshFailed = _installments.isNotEmpty;
      if (kDebugMode) {
        print('Error loading sale installments: $e');
      }
    } finally {
      if (generation == _generation) {
        _isLoading = false;
        _isRefreshing = false;
        notifyListeners();
      }
    }
  }

  // Search installments
  Future<void> search(String query) async {
    _searchQuery = query;
    _applyFilters();
    notifyListeners();
  }

  // Filter by status
  void filterByStatus(String? status) {
    _selectedStatus = status;
    _applyFilters();
    notifyListeners();
  }

  // Clear all filters
  void clearFilters() {
    _searchQuery = '';
    _selectedStatus = null;
    _applyFilters();
    notifyListeners();
  }

  // Apply current filters
  void _applyFilters() {
    Iterable<InstallmentDetail> working = _installments;

    final normalizedQuery = _searchQuery.trim().toLowerCase();
    if (normalizedQuery.isNotEmpty) {
      working = working.where((inst) {
        return inst.clientName.toLowerCase().contains(normalizedQuery) ||
            inst.clientDocumentId.toLowerCase().contains(normalizedQuery) ||
            inst.lotCode.toLowerCase().contains(normalizedQuery) ||
            inst.saleId.toString().contains(normalizedQuery);
      });
    }

    // Apply status filter if selected
    if (_selectedStatus != null && _selectedStatus!.isNotEmpty) {
      working = working.where(
        (inst) => inst.calculatedStatus == _selectedStatus,
      );
    }

    _filteredInstallments = working.toList();
  }

  String get _allScope => 'all';

  String _saleScope(int saleId) => 'sale:$saleId';

  bool _restoreLastGood(String scope) {
    final snapshot = _lastGoodByScope[scope];
    if (snapshot == null || snapshot.installments.isEmpty) {
      return false;
    }
    _installments = snapshot.installments;
    _selectedSaleSummary = snapshot.selectedSaleSummary;
    _applyFilters();
    return true;
  }

  void _rememberLastGood(String scope) {
    if (_installments.isEmpty) {
      return;
    }
    _lastGoodByScope[scope] = _InstallmentsMemorySnapshot(
      installments: List<InstallmentDetail>.unmodifiable(_installments),
      selectedSaleSummary: _selectedSaleSummary,
    );
  }

  // Get grouped installments by status
  Map<String, List<InstallmentDetail>> get installmentsByStatus {
    final grouped = <String, List<InstallmentDetail>>{
      'pendiente': [],
      'parcial': [],
      'pagada': [],
      'vencida': [],
    };

    for (final inst in _filteredInstallments) {
      final status = inst.calculatedStatus;
      if (grouped.containsKey(status)) {
        grouped[status]!.add(inst);
      }
    }

    return grouped;
  }

  // Format currency for display
  static String formatCurrency(double amount) {
    final formatter = RegExp(r'\B(?=(\d{3})+(?!\d))');
    final parts = amount.toStringAsFixed(2).split('.');
    final integerPart = parts[0].replaceAllMapped(formatter, (Match m) => ',');
    return '$integerPart.${parts[1]}';
  }

  // Check if there are overdue installments
  bool get hasOverdue =>
      _filteredInstallments.any((inst) => inst.calculatedStatus == 'vencida');

  // Get total overdue amount
  double get totalOverdueAmount => _filteredInstallments
      .where((inst) => inst.calculatedStatus == 'vencida')
      .fold(0.0, (sum, inst) => sum + inst.remainingAmount);
}

class _InstallmentsMemorySnapshot {
  const _InstallmentsMemorySnapshot({
    required this.installments,
    required this.selectedSaleSummary,
  });

  final List<InstallmentDetail> installments;
  final SaleInstallmentsSummary? selectedSaleSummary;
}
