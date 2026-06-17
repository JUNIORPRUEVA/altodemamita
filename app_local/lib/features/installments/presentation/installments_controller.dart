import 'package:flutter/foundation.dart';

import '../data/installments_repository.dart';
import '../domain/installment_detail.dart';

class InstallmentsController extends ChangeNotifier {
  InstallmentsController({required InstallmentsRepository installmentsRepository})
    : _installmentsRepository = installmentsRepository;

  final InstallmentsRepository _installmentsRepository;

  List<InstallmentDetail> _installments = const [];
  List<InstallmentDetail> _filteredInstallments = const [];
  SaleInstallmentsSummary? _selectedSaleSummary;
  bool _isLoading = true;
  String _searchQuery = '';
  String? _selectedStatus;

  // Getters
  List<InstallmentDetail> get installments => _filteredInstallments;
  SaleInstallmentsSummary? get selectedSaleSummary => _selectedSaleSummary;
  bool get isLoading => _isLoading;
  String get searchQuery => _searchQuery;
  String? get selectedStatus => _selectedStatus;

  // Calculated statistics
  double get totalFinanced => _selectedSaleSummary?.totalFinanced ?? 
    _filteredInstallments.fold(0.0, (sum, inst) => sum + inst.totalAmount);
  
  double get totalPaid => _selectedSaleSummary?.totalPaid ?? 
    _filteredInstallments.fold(0.0, (sum, inst) => sum + inst.paidAmount);
  
  double get totalPending => _selectedSaleSummary?.totalPending ?? 
    _filteredInstallments.fold(0.0, (sum, inst) => sum + inst.remainingAmount);

  int get totalInstallments => _selectedSaleSummary?.totalInstallments ?? _filteredInstallments.length;
  
  int get paidInstallments => _selectedSaleSummary?.paidInstallments ?? 
    _filteredInstallments.where((inst) => inst.remainingAmount <= 0.009).length;
  
  int get pendingInstallments => totalInstallments - paidInstallments;

  // Load all installments
  Future<void> load() async {
    _isLoading = true;
    notifyListeners();

    try {
      _installments = await _installmentsRepository.getAll();
      _applyFilters();
    } catch (e) {
      if (kDebugMode) {
        print('Error loading installments: $e');
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  // Load installments for a specific sale
  Future<void> loadBySaleId(int saleId) async {
    _isLoading = true;
    notifyListeners();

    try {
      _installments = await _installmentsRepository.getBySaleId(saleId);
      _selectedSaleSummary = await _installmentsRepository.getSaleSummary(saleId);
      _applyFilters();
    } catch (e) {
      if (kDebugMode) {
        print('Error loading sale installments: $e');
      }
    }

    _isLoading = false;
    notifyListeners();
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
      working = working.where((inst) => inst.calculatedStatus == _selectedStatus);
    }

    _filteredInstallments = working.toList();
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
