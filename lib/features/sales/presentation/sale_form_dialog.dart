import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/dominican_formatters.dart';
import '../../../features/auth/domain/permission_model.dart';
import '../../../features/auth/presentation/auth_provider.dart';
import '../../../core/resilience/friendly_error_messages.dart';
import '../../clients/data/client_repository.dart';
import '../../clients/domain/client.dart';
import '../../clients/presentation/client_form_dialog.dart';
import '../../lots/data/lot_repository.dart';
import '../../lots/domain/lot.dart';
import '../../lots/presentation/lot_form_dialog.dart';
import '../domain/sale.dart';
import '../data/seller_repository.dart';
import '../domain/sale_calculator.dart';
import '../domain/sale_detail.dart';
import '../domain/sale_defaults.dart';
import '../domain/sale_draft.dart';
import '../domain/seller.dart';
import '../presentation/sale_detail_dialog.dart';
import '../presentation/seller_form_dialog.dart';

const Key saleFormCreateClientButtonKey = Key('sale_form_create_client');
const Key saleFormCreateSellerButtonKey = Key('sale_form_create_seller');
const Key saleFormCreateLotButtonKey = Key('sale_form_create_lot');

class SaleFormDialog extends StatefulWidget {
  const SaleFormDialog({
    super.key,
    required this.clients,
    required this.availableLots,
    required this.sellers,
    required this.defaults,
    required this.clientRepository,
    required this.lotRepository,
    required this.sellerRepository,
    this.initialDraft,
    this.dialogTitle = 'Nueva venta',
    this.submitLabel = 'Crear venta',
    this.onClientCreated,
    this.onLotCreated,
    this.onSellerCreated,
  });

  final List<Client> clients;
  final List<Lot> availableLots;
  final List<Seller> sellers;
  final SaleDefaults defaults;
  final ClientRepository clientRepository;
  final LotRepository lotRepository;
  final SellerRepository sellerRepository;
  final SaleDraft? initialDraft;
  final String dialogTitle;
  final String submitLabel;
  final Future<void> Function()? onClientCreated;
  final Future<void> Function()? onLotCreated;
  final Future<void> Function()? onSellerCreated;

  static Future<SaleDraft?> show(
    BuildContext context, {
    required List<Client> clients,
    required List<Lot> availableLots,
    required List<Seller> sellers,
    required SaleDefaults defaults,
    required ClientRepository clientRepository,
    required LotRepository lotRepository,
    required SellerRepository sellerRepository,
    SaleDraft? initialDraft,
    String dialogTitle = 'Nueva venta',
    String submitLabel = 'Crear venta',
    Future<void> Function()? onClientCreated,
    Future<void> Function()? onLotCreated,
    Future<void> Function()? onSellerCreated,
  }) {
    return showDialog<SaleDraft>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SaleFormDialog(
        clients: clients,
        availableLots: availableLots,
        sellers: sellers,
        defaults: defaults,
        clientRepository: clientRepository,
        lotRepository: lotRepository,
        sellerRepository: sellerRepository,
        initialDraft: initialDraft,
        dialogTitle: dialogTitle,
        submitLabel: submitLabel,
        onClientCreated: onClientCreated,
        onLotCreated: onLotCreated,
        onSellerCreated: onSellerCreated,
      ),
    );
  }

  @override
  State<SaleFormDialog> createState() => _SaleFormDialogState();
}

class _SaleFormDialogState extends State<SaleFormDialog> {
  static const List<String> _initialPaymentMethods = [
    'efectivo',
    'transferencia',
    'cheque',
    'tarjeta',
  ];
  static final RdCurrencyInputFormatter _currencyFormatter =
      RdCurrencyInputFormatter();

  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _clientSearchController;
  late final TextEditingController _sellerSearchController;
  late final TextEditingController _lotSearchController;
  late final TextEditingController _saleDateController;
  late final TextEditingController _downPaymentController;
  late final TextEditingController _initialPaidController;
  late final TextEditingController _initialDeadlineController;
  late final TextEditingController _monthlyInterestController;
  late final TextEditingController _installmentCountController;
  late final TextEditingController _lotPriceController;

  late List<Client> _clients;
  late List<Lot> _availableLots;
  late List<Seller> _sellers;
  int? _selectedClientId;
  int? _selectedLotId;
  int? _selectedSellerId;
  final Set<int> _additionalLotIds = {};
  DateTime _saleDate = DateTime.now();
  bool _isCreatingClient = false;
  bool _isCreatingLot = false;
  bool _isCreatingSeller = false;
  bool _isEditingLot = false;
  bool _useDirectInstallmentCount = true;
  int _durationYears = 5;
  String _selectedInitialPaymentMethod = _initialPaymentMethods.first;

  bool get _canCreateClients => context.read<AuthProvider>().canAccess(
    PermissionCatalog.clients,
    PermissionAction.create,
  );

  bool get _canUpdateClients => context.read<AuthProvider>().canAccess(
    PermissionCatalog.clients,
    PermissionAction.update,
  );

  bool get _canCreateSellers => context.read<AuthProvider>().canAccess(
    PermissionCatalog.sellers,
    PermissionAction.create,
  );

  bool get _canUpdateSellers => context.read<AuthProvider>().canAccess(
    PermissionCatalog.sellers,
    PermissionAction.update,
  );

  bool get _canCreateLots => context.read<AuthProvider>().canAccess(
    PermissionCatalog.lots,
    PermissionAction.create,
  );

  bool get _canUpdateLots => context.read<AuthProvider>().canAccess(
    PermissionCatalog.lots,
    PermissionAction.update,
  );
  int? get _currentUserId => context.read<AuthProvider>().currentUser?.id;
  int _durationMonths = 0;
  DateTime? _initialPaymentDeadline;
  bool _isInitialDeadlineManuallyEdited = false;

  bool get _isEditingSale => widget.initialDraft != null;

  List<Client> get _filteredClients {
    final normalizedQuery = _clientSearchController.text.trim().toLowerCase();
    final filtered = normalizedQuery.isEmpty
        ? List<Client>.from(_clients)
        : _clients.where((client) {
            return client.fullName.toLowerCase().contains(normalizedQuery) ||
                client.documentId.toLowerCase().contains(normalizedQuery) ||
                (client.phone?.toLowerCase().contains(normalizedQuery) ??
                    false);
          }).toList();

    if (_selectedClientId != null &&
        !filtered.any((client) => client.id == _selectedClientId)) {
      final selectedClient = _findClientById(_selectedClientId);
      if (selectedClient != null) {
        filtered.insert(0, selectedClient);
      }
    }

    return filtered;
  }

  List<Seller> get _filteredSellers {
    final normalizedQuery = _sellerSearchController.text.trim().toLowerCase();
    final filtered = normalizedQuery.isEmpty
        ? List<Seller>.from(_sellers)
        : _sellers.where((seller) {
            return seller.name.toLowerCase().contains(normalizedQuery) ||
                seller.documentId.toLowerCase().contains(normalizedQuery);
          }).toList();

    if (_selectedSellerId != null &&
        !filtered.any((seller) => seller.id == _selectedSellerId)) {
      final selectedSeller = _findSellerById(_selectedSellerId);
      if (selectedSeller != null) {
        filtered.insert(0, selectedSeller);
      }
    }

    return filtered;
  }

  List<Lot> get _filteredLots {
    final availableLotsFiltered = _availableLots
        .where(
          (lot) =>
              (lot.status == 'disponible' || lot.id == _selectedLotId) &&
              (!_additionalLotIds.contains(lot.id) || lot.id == _selectedLotId),
        )
        .toList();

    final normalizedQuery = _lotSearchController.text.trim().toLowerCase();
    final filtered = normalizedQuery.isEmpty
        ? List<Lot>.from(availableLotsFiltered)
        : availableLotsFiltered.where((lot) {
            return lot.displayCode.toLowerCase().contains(normalizedQuery) ||
                lot.area.toString().contains(normalizedQuery);
          }).toList();

    if (_selectedLotId != null &&
        !filtered.any((lot) => lot.id == _selectedLotId)) {
      final selectedLot = _selectedLot;
      if (selectedLot != null) {
        filtered.insert(0, selectedLot);
      }
    }

    return filtered;
  }

  bool get _hasFormData {
    return _selectedClientId != null ||
        _selectedSellerId != null ||
        _selectedLotId != null ||
        _additionalLotIds.isNotEmpty ||
        _lotPriceController.text.isNotEmpty ||
        _downPaymentController.text.trim().isNotEmpty ||
        _initialPaidController.text.trim().isNotEmpty ||
        _monthlyInterestController.text.trim().isNotEmpty ||
        _installmentCountController.text.trim().isNotEmpty ||
        _initialPaymentDeadline != null ||
        _saleDate != DateTime.now();
  }

  Lot? _findLotById(int? lotId) {
    if (lotId == null) {
      return null;
    }

    for (final lot in _availableLots) {
      if (lot.id == lotId) {
        return lot;
      }
    }

    return null;
  }

  Lot? get _selectedLot {
    return _findLotById(_selectedLotId);
  }

  double get _selectedLotsBasePrice {
    double totalPrice = _selectedLot?.totalPrice ?? 0;

    if (_additionalLotIds.isNotEmpty) {
      for (final lotId in _additionalLotIds) {
        final lot = _findLotById(lotId);
        if (lot != null) {
          totalPrice += lot.totalPrice;
        }
      }
    }

    return totalPrice;
  }

  double get _salePrice {
    final controllerValue = _parseDouble(_lotPriceController.text, -1);
    if (controllerValue >= 0) {
      return controllerValue;
    }

    return _selectedLotsBasePrice;
  }

  double get _downPaymentPercentage => _parseDouble(
    _downPaymentController.text,
    widget.defaults.downPaymentPercentage,
  );

  double get _monthlyInterest => _parseDouble(
    _monthlyInterestController.text,
    widget.defaults.monthlyInterest,
  );

  int get _installmentCount => _parseInt(
    _installmentCountController.text,
    widget.defaults.installmentCount,
  );

  double get _requiredInitialPayment =>
      SaleCalculator.calculateDownPaymentAmount(
        salePrice: _salePrice,
        downPaymentPercentage: _downPaymentPercentage,
      );

  double get _appliedInitialPayment {
    final parsed = _parseDouble(_initialPaidController.text, 0);
    if (parsed <= 0) {
      return 0;
    }

    return parsed > _salePrice ? _salePrice : parsed;
  }

  double get _financedBalance => SaleCalculator.calculateFinancedBalance(
    salePrice: _salePrice,
    downPaymentAmount: _appliedInitialPayment,
  );

  double get _initialPaymentPaid =>
      _parseDouble(_initialPaidController.text, 0);

  double get _pendingInitialPayment =>
      SaleCalculator.calculatePendingInitialPayment(
        requiredInitialPayment: _requiredInitialPayment,
        initialPaymentPaid: _appliedInitialPayment,
      );

  String get _saleLifecycleStatus {
    if (_financedBalance <= 0.009) {
      return 'pagada';
    }
    if (_appliedInitialPayment >= _requiredInitialPayment - 0.009) {
      return 'activa';
    }
    if (_appliedInitialPayment <= 0) {
      return 'apartado';
    }
    return 'inicial_incompleto';
  }

  double get _estimatedInstallmentAmount =>
      SaleCalculator.calculateEstimatedInstallmentAmount(
        financedBalance: _financedBalance,
        monthlyInterest: _monthlyInterest,
        installmentCount: _installmentCount,
      );

  double get _totalFinancingAmount =>
      SaleCalculator.calculateTotalFinancingAmount(
        financedBalance: _financedBalance,
        monthlyInterest: _monthlyInterest,
        installmentCount: _installmentCount,
      );

  @override
  void initState() {
    super.initState();
    _clients = List<Client>.from(widget.clients);
    _availableLots = List<Lot>.from(widget.availableLots);
    _sellers = List<Seller>.from(widget.sellers);
    _clientSearchController = TextEditingController();
    _sellerSearchController = TextEditingController();
    _lotSearchController = TextEditingController();
    final initialDraft = widget.initialDraft;
    _selectedClientId = initialDraft?.clientId;
    _selectedLotId = initialDraft?.lotId;
    _selectedSellerId = initialDraft?.sellerId;
    _saleDate = initialDraft?.saleDate ?? _saleDate;

    _saleDateController = TextEditingController(text: _formatDate(_saleDate));
    _downPaymentController = TextEditingController(
      text:
          (initialDraft?.downPaymentPercentage ??
                  widget.defaults.downPaymentPercentage)
              .toStringAsFixed(0),
    );
    _initialPaidController = TextEditingController(
      text: _formatCurrencyInput(initialDraft?.initialPaymentPaid ?? 0),
    );
    final normalizedInitialPaymentMethod =
        (initialDraft?.initialPaymentMethod ?? _initialPaymentMethods.first)
            .trim()
            .toLowerCase();
    _selectedInitialPaymentMethod =
        _initialPaymentMethods.contains(normalizedInitialPaymentMethod)
        ? normalizedInitialPaymentMethod
        : _initialPaymentMethods.first;
    _initialPaymentDeadline = initialDraft?.initialPaymentDeadline;
    _isInitialDeadlineManuallyEdited = _initialPaymentDeadline != null;
    _initialDeadlineController = TextEditingController(
      text: _initialPaymentDeadline == null
          ? ''
          : _formatDate(_initialPaymentDeadline!),
    );
    _monthlyInterestController = TextEditingController(
      text: (initialDraft?.monthlyInterest ?? widget.defaults.monthlyInterest)
          .toStringAsFixed(0),
    );
    _installmentCountController = TextEditingController(
      text: (initialDraft?.installmentCount ?? widget.defaults.installmentCount)
          .toString(),
    );
    _lotPriceController = TextEditingController(
      text: initialDraft == null
          ? ''
          : _formatCurrencyInput(initialDraft.salePrice),
    );

    if (_selectedLotId != null &&
        !_availableLots.any((lot) => lot.id == _selectedLotId)) {
      widget.lotRepository.findById(_selectedLotId!).then((lot) {
        if (!mounted || lot == null) {
          return;
        }

        setState(() {
          _availableLots = [lot, ..._availableLots];
        });
      });
    }

    _syncInitialDeadline();
  }

  @override
  void dispose() {
    _clientSearchController.dispose();
    _sellerSearchController.dispose();
    _lotSearchController.dispose();
    _saleDateController.dispose();
    _downPaymentController.dispose();
    _initialPaidController.dispose();
    _initialDeadlineController.dispose();
    _monthlyInterestController.dispose();
    _installmentCountController.dispose();
    _lotPriceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final dialogWidth = math.min(screenSize.width - 20, 1220.0);
    final dialogHeight = math.min(screenSize.height - 20, 736.0);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogWidth,
          maxHeight: dialogHeight,
        ),
        child: Column(
          children: [
            _buildDialogHeader(),
            Divider(
              height: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
                child: _buildForm(),
              ),
            ),
            Divider(
              height: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            _buildDialogFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogHeader() {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.point_of_sale_outlined,
              size: 22,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.dialogTitle,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text('Registro de venta', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          Text(
            _formatDate(_saleDate),
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          Widget buildContent({required bool allowFlexibleSpacing}) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSelectorGroup(),
                const SizedBox(height: 12),
                Divider(
                  height: 1,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                const SizedBox(height: 12),
                _buildSaleTermsBand(),
                const SizedBox(height: 10),
                _buildInitialPaymentBand(),
                if (allowFlexibleSpacing)
                  const Spacer()
                else
                  const SizedBox(height: 16),
                Divider(
                  height: 1,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                const SizedBox(height: 10),
                _buildLiveSummary(),
              ],
            );
          }

          final needsScroll =
              constraints.maxWidth < 1024 || constraints.maxHeight < 560;

          if (needsScroll) {
            return SingleChildScrollView(
              child: buildContent(allowFlexibleSpacing: false),
            );
          }

          return buildContent(allowFlexibleSpacing: true);
        },
      ),
    );
  }

  Widget _buildDialogFooter() {
    final pendingFields = <String>[
      if (_selectedClientId == null) 'cliente',
      if (_selectedLotId == null) 'solar',
    ];
    final readyToSave = pendingFields.isEmpty;
    final helperText = readyToSave
        ? 'Listo para registrar la venta.'
        : 'Completa ${_formatPendingFields(pendingFields)} para continuar.';
    final helperColor = readyToSave
        ? Theme.of(context).colorScheme.secondary
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 760;
          final actionButtons = Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.end,
            children: [
              TextButton(
                onPressed: _handleCancel,
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                onPressed: readyToSave ? _save : null,
                icon: const Icon(Icons.task_alt_outlined, size: 18),
                label: Text(widget.submitLabel),
              ),
            ],
          );

          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  helperText,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: helperColor,
                    fontWeight: readyToSave ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 10),
                actionButtons,
              ],
            );
          }

          return Row(
            children: [
              Expanded(
                child: Text(
                  helperText,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: helperColor,
                    fontWeight: readyToSave ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              actionButtons,
            ],
          );
        },
      ),
    );
  }

  Widget _buildSelectorGroup() {
    return Column(
      children: [
        _buildClientLine(),
        const SizedBox(height: 10),
        _buildSellerLine(),
        const SizedBox(height: 10),
        _buildLotLine(),
      ],
    );
  }

  Widget _buildClientLine() {
    final selectedClient = _findClientById(_selectedClientId);
    return _buildSelectorLine(
      field: DropdownButtonFormField<int>(
        initialValue: _selectedClientId,
        isExpanded: true,
        menuMaxHeight: 320,
        decoration: const InputDecoration(labelText: 'Seleccionar cliente'),
        items: _filteredClients
            .map(
              (client) => DropdownMenuItem<int>(
                value: client.id,
                child: Text(
                  '${client.fullName} • ${client.documentId}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: (value) {
          setState(() {
            _selectedClientId = value;
          });
        },
        validator: (value) => value == null ? 'Seleccione un cliente' : null,
      ),
      onSearch: _pickClientFromDialog,
      createLabel: _isCreatingClient ? 'Guardando...' : 'Nuevo cliente',
      createKey: saleFormCreateClientButtonKey,
      onCreate: !_canCreateClients || _isCreatingClient
          ? null
          : _createClientQuickly,
      trailingActions: [
        if (selectedClient != null && _canUpdateClients)
          _buildCompactIconButton(
            icon: Icons.edit_outlined,
            tooltip: 'Editar cliente',
            onPressed: () => _editClientInline(selectedClient),
          ),
      ],
    );
  }

  Widget _buildSellerLine() {
    final selectedSeller = _findSellerById(_selectedSellerId);
    return _buildSelectorLine(
      field: DropdownButtonFormField<int>(
        initialValue: _selectedSellerId,
        isExpanded: true,
        menuMaxHeight: 320,
        decoration: const InputDecoration(
          labelText: 'Seleccionar vendedor',
          helperText: 'Opcional',
        ),
        items: _filteredSellers
            .map(
              (seller) => DropdownMenuItem<int>(
                value: seller.id,
                child: Text(
                  '${seller.name} • ${seller.documentId}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: (value) {
          setState(() {
            _selectedSellerId = value;
          });
        },
      ),
      onSearch: _pickSellerFromDialog,
      createLabel: _isCreatingSeller ? 'Guardando...' : 'Nuevo vendedor',
      createKey: saleFormCreateSellerButtonKey,
      onCreate: !_canCreateSellers || _isCreatingSeller
          ? null
          : _createSellerQuickly,
      trailingActions: [
        if (selectedSeller != null)
          _buildCompactIconButton(
            icon: Icons.clear_outlined,
            tooltip: 'Quitar vendedor',
            onPressed: () {
              setState(() {
                _selectedSellerId = null;
              });
            },
          ),
        if (selectedSeller != null && _canUpdateSellers)
          _buildCompactIconButton(
            icon: Icons.edit_outlined,
            tooltip: 'Editar vendedor',
            onPressed: () => _editSellerInline(selectedSeller),
          ),
      ],
    );
  }

  Widget _buildLotLine() {
    final selectedLot = _selectedLot;
    final showInlineHint = _availableLots.isEmpty;
    final showAdditionalLots =
        _additionalLotIds.isNotEmpty ||
        (!_isEditingSale && _getAvailableLotsForAddition().isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSelectorLine(
          field: DropdownButtonFormField<int>(
            initialValue: _selectedLotId,
            isExpanded: true,
            menuMaxHeight: 320,
            decoration: const InputDecoration(labelText: 'Seleccionar solar'),
            items: _filteredLots
                .map(
                  (lot) => DropdownMenuItem<int>(
                    value: lot.id,
                    child: Text(
                      '${lot.displayCode} • ${lot.area.toStringAsFixed(1)} m² • RD\$${formatRdCurrency(lot.pricePerSquareMeter)}/m² • ${_formatCurrency(lot.totalPrice)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              setState(() {
                _selectedLotId = value;
                _additionalLotIds.remove(value);
                _syncLotPriceFromSelection();
                _syncInitialDeadline();
              });
            },
            validator: (value) => value == null ? 'Seleccione un solar' : null,
          ),
          onSearch: _pickLotFromDialog,
          createLabel: _isCreatingLot ? 'Guardando...' : 'Nuevo solar',
          createKey: saleFormCreateLotButtonKey,
          onCreate: !_canCreateLots || _isCreatingLot
              ? null
              : _createLotQuickly,
          trailingActions: [
            if (!_isEditingSale && _getAvailableLotsForAddition().isNotEmpty)
              _buildCompactIconButton(
                icon: Icons.add_box_outlined,
                tooltip: 'Agregar otro solar',
                onPressed: _showAddLotDialog,
              ),
            if (selectedLot != null &&
                _canUpdateLots)
              _buildCompactIconButton(
                icon: Icons.edit_outlined,
                tooltip: 'Editar solar',
                onPressed: _isEditingLot
                    ? null
                    : () => _editLotInline(selectedLot),
              ),
            if (selectedLot != null)
              _buildCompactIconButton(
                icon: Icons.info_outline,
                tooltip: 'Ver detalles del solar',
                onPressed: () => _viewLotDetails(selectedLot),
              ),
          ],
        ),
        if (showInlineHint) ...[
          const SizedBox(height: 6),
          Text(
            'No hay solares disponibles. Puedes crear uno desde este formulario.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (showAdditionalLots) ...[
          const SizedBox(height: 8),
          _buildAdditionalLotsRow(),
        ],
      ],
    );
  }

  Widget _buildSaleTermsBand() {
    final compactFieldWidth = math.max(
      118.0,
      (MediaQuery.sizeOf(context).width - 440) / 6,
    );

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 150,
          child: TextFormField(
            controller: _saleDateController,
            readOnly: true,
            decoration: const InputDecoration(
              labelText: 'Fecha de venta',
              suffixIcon: Icon(Icons.calendar_month_outlined),
            ),
            onTap: _pickSaleDate,
            validator: (value) =>
                value == null || value.isEmpty ? 'Seleccione fecha' : null,
          ),
        ),
        SizedBox(
          width: 190,
          child: TextFormField(
            controller: _lotPriceController,
            readOnly: true,
            decoration: const InputDecoration(
              labelText: 'Precio total',
              prefixText: 'RD\$ ',
            ),
            validator: (value) {
              final parsed = _parseDouble(value, -1);
              if (parsed < 0) {
                return 'Precio requerido';
              }
              return null;
            },
          ),
        ),
        SizedBox(
          width: compactFieldWidth,
          child: TextFormField(
            controller: _downPaymentController,
            readOnly: true,
            decoration: InputDecoration(
              labelText: 'Inicial %',
              suffixIcon: Icon(
                Icons.lock_outlined,
                color: Theme.of(context).colorScheme.outline,
                size: 18,
              ),
            ),
          ),
        ),
        SizedBox(
          width: compactFieldWidth,
          child: TextFormField(
            controller: _monthlyInterestController,
            readOnly: true,
            decoration: InputDecoration(
              labelText: 'Interés %',
              suffixIcon: Icon(
                Icons.lock_outlined,
                color: Theme.of(context).colorScheme.outline,
                size: 18,
              ),
            ),
          ),
        ),
        SizedBox(
          width: 340,
          child: _InstallmentCountInput(
            useDirectCount: _useDirectInstallmentCount,
            directCountController: _installmentCountController,
            durationYears: _durationYears,
            durationMonths: _durationMonths,
            onModeChanged: (useDirectCount) {
              setState(() {
                _useDirectInstallmentCount = useDirectCount;
                if (!useDirectCount) {
                  final calculatedCount =
                      (_durationYears * 12) + _durationMonths;
                  _installmentCountController.text = calculatedCount.toString();
                }
              });
            },
            onDurationChanged: (years, months) {
              setState(() {
                _durationYears = years;
                _durationMonths = months;
                if (!_useDirectInstallmentCount) {
                  final calculatedCount = (years * 12) + months;
                  _installmentCountController.text = calculatedCount.toString();
                }
              });
            },
            onDirectCountChanged: (_) => setState(() {}),
            salePrice: _salePrice,
          ),
        ),
      ],
    );
  }

  Widget _buildInitialPaymentBand() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        SizedBox(
          width: 165,
          child: TextFormField(
            key: ValueKey(
              'required-initial-${_requiredInitialPayment.toStringAsFixed(2)}',
            ),
            initialValue: _formatCurrencyInput(_requiredInitialPayment),
            readOnly: true,
            decoration: const InputDecoration(
              labelText: 'Inicial minimo requerido',
              prefixText: 'RD\$ ',
            ),
          ),
        ),
        SizedBox(
          width: 165,
          child: TextFormField(
            controller: _initialPaidController,
            decoration: const InputDecoration(
              labelText: 'Inicial real pagado',
              prefixText: 'RD\$ ',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [_currencyFormatter],
            validator: (value) {
              final parsed = _parseDouble(value, -1);
              if (parsed < 0) {
                return 'Monto válido';
              }
              if (parsed - _salePrice > 0.009) {
                return 'No puede exceder el precio total';
              }
              return null;
            },
            onChanged: (_) {
              setState(() {
                _syncInitialDeadline();
              });
            },
          ),
        ),
        SizedBox(
          width: 165,
          child: TextFormField(
            key: ValueKey(
              'pending-initial-${_pendingInitialPayment.toStringAsFixed(2)}',
            ),
            initialValue: _formatCurrencyInput(_pendingInitialPayment),
            readOnly: true,
            decoration: const InputDecoration(
              labelText: 'Inicial pendiente',
              prefixText: 'RD\$ ',
            ),
          ),
        ),
        SizedBox(
          width: 190,
          child: DropdownButtonFormField<String>(
            initialValue: _selectedInitialPaymentMethod,
            decoration: const InputDecoration(
              labelText: 'Metodo del primer pago',
            ),
            items: _initialPaymentMethods
                .map(
                  (method) => DropdownMenuItem<String>(
                    value: method,
                    child: Text(_formatPaymentMethod(method)),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) {
                return;
              }
              setState(() {
                _selectedInitialPaymentMethod = value;
              });
            },
          ),
        ),
        SizedBox(
          width: 190,
          child: TextFormField(
            controller: _initialDeadlineController,
            readOnly: true,
            decoration: InputDecoration(
              labelText: 'Fecha límite',
              suffixIcon: _initialPaymentDeadline == null
                  ? IconButton(
                      onPressed: _pendingInitialPayment > 0
                          ? _pickInitialDeadline
                          : null,
                      icon: const Icon(Icons.calendar_month_outlined),
                    )
                  : SizedBox(
                      width: 96,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            onPressed: _pickInitialDeadline,
                            icon: const Icon(Icons.edit_calendar_outlined),
                          ),
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _isInitialDeadlineManuallyEdited = false;
                                _initialPaymentDeadline = null;
                                _initialDeadlineController.clear();
                                _syncInitialDeadline();
                              });
                            },
                            icon: const Icon(Icons.close_outlined),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLiveSummary() {
    final theme = Theme.of(context);
    final statusColor = _saleLifecycleStatus == 'activa'
        ? theme.colorScheme.secondary
        : _saleLifecycleStatus == 'apartado'
        ? const Color(0xFF9C5A00)
        : theme.colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 18,
          runSpacing: 8,
          children: [
            _buildSummaryText(
              'Inicial pendiente',
              _formatCurrency(_pendingInitialPayment),
            ),
            _buildSummaryText(
              'Capital financiado',
              _formatCurrency(_financedBalance),
            ),
            _buildSummaryText(
              'Total del plan',
              _formatCurrency(_totalFinancingAmount),
            ),
            _buildSummaryText(
              'Cuota fija mensual',
              _formatCurrency(_estimatedInstallmentAmount),
            ),
            _buildSummaryText(
              'Estado',
              _formatSaleStatus(_saleLifecycleStatus),
              emphasisColor: statusColor,
            ),
            _buildSummaryActionButton(),
          ],
        ),
      ],
    );
  }

  Widget _buildSelectorLine({
    required Widget field,
    required VoidCallback onSearch,
    required String createLabel,
    Key? createKey,
    required VoidCallback? onCreate,
    List<Widget> trailingActions = const <Widget>[],
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final actions = <Widget>[
          _buildCompactIconButton(
            icon: Icons.search,
            tooltip: 'Buscar',
            onPressed: onSearch,
          ),
          _buildCompactActionButton(
            key: createKey,
            label: createLabel,
            onPressed: onCreate,
          ),
          ...trailingActions,
        ];

        if (constraints.maxWidth < 860) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              field,
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: actions),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: field),
            const SizedBox(width: 8),
            ..._withActionSpacing(actions),
          ],
        );
      },
    );
  }

  Widget _buildCompactIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: 18),
      style: IconButton.styleFrom(
        minimumSize: const Size(42, 42),
        maximumSize: const Size(42, 42),
        padding: EdgeInsets.zero,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        foregroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Widget _buildSummaryActionButton() {
    final canPreview =
        _selectedLot != null &&
        _findClientById(_selectedClientId) != null &&
        _installmentCount > 0;
    return OutlinedButton.icon(
      onPressed: !canPreview
          ? null
          : () {
              final previewDetail = _buildPreviewSaleDetail();
              if (previewDetail == null) {
                return;
              }
              openInstallmentsFullscreen(context, previewDetail);
            },
      icon: const Icon(Icons.visibility_outlined, size: 16),
      label: const Text('Ver'),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
    );
  }

  SaleDetail? _buildPreviewSaleDetail() {
    final selectedLot = _selectedLot;
    final selectedClient = _findClientById(_selectedClientId);
    if (selectedLot == null ||
        selectedClient == null ||
        _installmentCount <= 0) {
      return null;
    }

    final createdAt = DateTime.now();
    final sale = Sale(
      id: 0,
      clientId: selectedClient.id ?? 0,
      lotId: selectedLot.id ?? 0,
      userId: _currentUserId ?? 0,
      sellerId: _selectedSellerId,
      saleDate: _saleDate,
      salePrice: _salePrice,
      downPaymentPercentage: _downPaymentPercentage,
      downPaymentAmount: _appliedInitialPayment,
      requiredInitialPayment: _requiredInitialPayment,
      paidInitialPayment: _appliedInitialPayment,
      pendingInitialPayment: _pendingInitialPayment,
      minimumReserveAmount: null,
      initialPaymentDeadline: _initialPaymentDeadline,
      activationDate: _pendingInitialPayment <= 0.009 ? _saleDate : null,
      financedBalance: _financedBalance,
      pendingBalance: _financedBalance,
      monthlyInterest: _monthlyInterest,
      installmentCount: _installmentCount,
      status: _saleLifecycleStatus,
      createdAt: createdAt,
      updatedAt: createdAt,
    );

    final installments = SaleCalculator.buildInstallmentSchedule(
      saleId: 0,
      saleDate: _saleDate,
      financedBalance: _financedBalance,
      monthlyInterest: _monthlyInterest,
      installmentCount: _installmentCount,
      createdAt: createdAt,
    );

    final selectedSeller = _findSellerById(_selectedSellerId);
    return SaleDetail(
      sale: sale,
      clientName: selectedClient.fullName,
      clientDocumentId: selectedClient.documentId,
      lotDisplayCode: selectedLot.displayCode,
      lotArea: selectedLot.area,
      lotPricePerSquareMeter: selectedLot.pricePerSquareMeter,
      userName: 'Vista previa',
      initialPaymentMethod: _selectedInitialPaymentMethod,
      sellerName: selectedSeller?.name,
      sellerDocumentId: selectedSeller?.documentId,
      sellerPhone: selectedSeller?.phone,
      installments: installments,
    );
  }

  Widget _buildCompactActionButton({
    Key? key,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return FilledButton.tonal(
      key: key,
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      child: Text(label),
    );
  }

  Widget _buildAdditionalLotsRow() {
    if (_selectedLotId == null) {
      return const SizedBox.shrink();
    }

    final availableLotsForAddition = _getAvailableLotsForAddition();
    if (_additionalLotIds.isEmpty &&
        (_isEditingSale || availableLotsForAddition.isEmpty)) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ..._additionalLotIds.map((lotId) {
              final lot = _availableLots.firstWhere(
                (candidate) => candidate.id == lotId,
                orElse: () => Lot.empty(),
              );

              return Chip(
                label: Text(
                  '${lot.displayCode} • ${_formatCurrency(lot.totalPrice)}',
                  style: const TextStyle(fontSize: 11),
                ),
                onDeleted: () {
                  setState(() {
                    _additionalLotIds.remove(lotId);
                    _syncLotPriceFromSelection();
                  });
                },
                deleteIcon: const Icon(Icons.close, size: 16),
              );
            }),
            if (!_isEditingSale && availableLotsForAddition.isNotEmpty)
              ActionChip(
                onPressed: _showAddLotDialog,
                avatar: const Icon(Icons.add, size: 16),
                label: const Text(
                  'Agregar solar',
                  style: TextStyle(fontSize: 11),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryText(String label, String value, {Color? emphasisColor}) {
    final theme = Theme.of(context);
    return RichText(
      text: TextSpan(
        style: theme.textTheme.bodyMedium,
        children: [
          TextSpan(
            text: '$label: ',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(
            text: value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: emphasisColor ?? theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickClientFromDialog() async {
    final selectedId = await _showLookupDialog<Client>(
      title: 'Buscar cliente',
      controller: _clientSearchController,
      items: _clients,
      emptyMessage: 'No hay clientes registrados.',
      titleBuilder: (client) => client.fullName,
      subtitleBuilder: (client) =>
          '${client.documentId} • ${client.phone ?? ''}',
      matches: (client, query) {
        return client.fullName.toLowerCase().contains(query) ||
            client.documentId.toLowerCase().contains(query) ||
            (client.phone?.toLowerCase().contains(query) ?? false);
      },
      idBuilder: (client) => client.id,
    );

    if (!mounted || selectedId == null) {
      return;
    }

    setState(() {
      _selectedClientId = selectedId;
    });
  }

  Future<void> _pickSellerFromDialog() async {
    final selectedId = await _showLookupDialog<Seller>(
      title: 'Buscar vendedor',
      controller: _sellerSearchController,
      items: _sellers,
      emptyMessage: 'No hay vendedores registrados.',
      titleBuilder: (seller) => seller.name,
      subtitleBuilder: (seller) => '${seller.documentId} • ${seller.phone}',
      matches: (seller, query) {
        return seller.name.toLowerCase().contains(query) ||
            seller.documentId.toLowerCase().contains(query) ||
            seller.phone.toLowerCase().contains(query);
      },
      idBuilder: (seller) => seller.id,
    );

    if (!mounted || selectedId == null) {
      return;
    }

    setState(() {
      _selectedSellerId = selectedId;
    });
  }

  Future<void> _pickLotFromDialog() async {
    final selectedId = await _showLookupDialog<Lot>(
      title: 'Buscar solar',
      controller: _lotSearchController,
      items: _filteredLots,
      emptyMessage: 'No hay solares disponibles.',
      titleBuilder: (lot) => lot.displayCode,
      subtitleBuilder: (lot) =>
          '${lot.area.toStringAsFixed(1)} m² • RD\$${formatRdCurrency(lot.pricePerSquareMeter)}/m² • ${_formatCurrency(lot.totalPrice)}',
      matches: (lot, query) {
        return lot.displayCode.toLowerCase().contains(query) ||
            lot.area.toString().contains(query) ||
            lot.pricePerSquareMeter.toString().contains(query) ||
            lot.totalPrice.toString().contains(query);
      },
      idBuilder: (lot) => lot.id,
    );

    if (!mounted || selectedId == null) {
      return;
    }

    setState(() {
      _selectedLotId = selectedId;
      _additionalLotIds.remove(selectedId);
      _syncLotPriceFromSelection();
    });
  }

  Future<int?> _showLookupDialog<T>({
    required String title,
    required TextEditingController controller,
    required List<T> items,
    required String emptyMessage,
    required String Function(T item) titleBuilder,
    required String Function(T item) subtitleBuilder,
    required bool Function(T item, String query) matches,
    required int? Function(T item) idBuilder,
  }) async {
    final searchController = TextEditingController(text: controller.text);
    try {
      return await showDialog<int>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              final query = searchController.text.trim().toLowerCase();
              final filteredItems = query.isEmpty
                  ? items
                  : items.where((item) => matches(item, query)).toList();

              return AlertDialog(
                title: Text(title),
                content: SizedBox(
                  width: 560,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: searchController,
                        decoration: InputDecoration(
                          hintText: 'Buscar...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: searchController.text.isEmpty
                              ? null
                              : IconButton(
                                  onPressed: () {
                                    searchController.clear();
                                    setDialogState(() {});
                                  },
                                  icon: const Icon(Icons.clear),
                                ),
                        ),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        child: filteredItems.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Text(
                                    emptyMessage,
                                    style: Theme.of(
                                      dialogContext,
                                    ).textTheme.bodyMedium,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                itemCount: filteredItems.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final item = filteredItems[index];
                                  return ListTile(
                                    dense: true,
                                    title: Text(titleBuilder(item)),
                                    subtitle: Text(
                                      subtitleBuilder(item),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    onTap: () {
                                      controller.text = searchController.text;
                                      Navigator.of(
                                        dialogContext,
                                      ).pop(idBuilder(item));
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cerrar'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      searchController.dispose();
    }
  }

  List<Widget> _withActionSpacing(List<Widget> actions) {
    final spaced = <Widget>[];
    for (var index = 0; index < actions.length; index++) {
      if (index > 0) {
        spaced.add(const SizedBox(width: 8));
      }
      spaced.add(actions[index]);
    }
    return spaced;
  }

  String _formatCurrency(double value) {
    return 'RD\$${formatRdCurrency(value)}';
  }

  String _formatPendingFields(List<String> fields) {
    if (fields.length == 1) {
      return fields.first;
    }
    if (fields.length == 2) {
      return '${fields.first} y ${fields.last}';
    }

    final prefix = fields.sublist(0, fields.length - 1).join(', ');
    return '$prefix y ${fields.last}';
  }

  String _formatSaleStatus(String rawStatus) {
    return rawStatus
        .split('_')
        .where((segment) => segment.isNotEmpty)
        .map(
          (segment) =>
              '${segment[0].toUpperCase()}${segment.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  String _formatPaymentMethod(String value) {
    if (value.isEmpty) {
      return value;
    }

    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

  void _syncLotPriceFromSelection() {
    final computedPrice = _selectedLotsBasePrice;
    if (computedPrice <= 0) {
      _lotPriceController.clear();
      _syncInitialDeadline();
      return;
    }

    _lotPriceController.text = _formatCurrencyInput(computedPrice);
    _syncInitialDeadline();
  }

  Future<void> _createClientQuickly() async {
    if (!_canCreateClients) {
      print('[SALE-FORM][CLIENT] stop: no permission to create clients');
      return;
    }

    print('[SALE-FORM][CLIENT] start create client');
    final clientDraft = await ClientFormDialog.show(context);
    if (!mounted || clientDraft == null) {
      print(
        '[SALE-FORM][CLIENT] stop: dialog closed or not mounted (mounted=$mounted, draft=${clientDraft != null})',
      );
      return;
    }

    setState(() {
      _isCreatingClient = true;
    });

    try {
      print(
        '[SALE-FORM][CLIENT] after dialog -> docId=${clientDraft.documentId} name=${clientDraft.fullName}',
      );
      final existingClient = await widget.clientRepository.findByDocumentId(
        clientDraft.documentId,
      );
      if (existingClient != null) {
        print(
          '[SALE-FORM][CLIENT] existing client found -> selecting id=${existingClient.id}',
        );
        final updatedClients = await widget.clientRepository.fetchAll();

        setState(() {
          _clients = updatedClients;
          _selectedClientId = existingClient.id;
          _clientSearchController.text = existingClient.fullName;
        });

        if (!mounted) {
          return;
        }

        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text(
              'Ya existe un cliente con esa cedula. Se selecciono el registro existente.',
            ),
          ),
        );
        return;
      }

      print('[SALE-FORM][CLIENT] saving new client to repository...');
      await widget.clientRepository.save(clientDraft);
      print('[SALE-FORM][CLIENT] saved -> reloading clients');
      final updatedClients = await widget.clientRepository.fetchAll();
      final createdClient = updatedClients.firstWhere(
        (client) => client.documentId == clientDraft.documentId,
      );

      setState(() {
        _clients = updatedClients;
        _selectedClientId = createdClient.id;
        _clientSearchController.text = createdClient.fullName;
      });

      if (widget.onClientCreated != null) {
        await widget.onClientCreated!();
      }

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Cliente creado y seleccionado en la venta.'),
        ),
      );
    } catch (error, stack) {
      print('[SALE-FORM][CLIENT] ERROR $error');
      print(stack);
      if (!mounted) {
        return;
      }
      FriendlyErrorMessages.forOperation(
        'guardar el cliente',
        error,
        module: 'ventas',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingClient = false;
        });
      }
    }
  }

  Future<void> _createLotQuickly() async {
    if (!_canCreateLots) {
      print('[SALE-FORM][LOT] stop: no permission to create lots');
      return;
    }

    print('[SALE-FORM][LOT] start create lot');
    final lotDraft = await LotFormDialog.show(context, showStatusField: false);
    if (!mounted || lotDraft == null) {
      print(
        '[SALE-FORM][LOT] stop: dialog closed or not mounted (mounted=$mounted, draft=${lotDraft != null})',
      );
      return;
    }

    setState(() {
      _isCreatingLot = true;
    });

    try {
      print('[SALE-FORM][LOT] saving lot to repository...');
      await widget.lotRepository.save(lotDraft.copyWith(status: 'disponible'));
      print('[SALE-FORM][LOT] saved -> reloading available lots');
      final updatedLots = await widget.lotRepository.fetchAvailable();
      final createdLot = updatedLots.firstWhere(
        (lot) =>
            lot.blockNumber == lotDraft.blockNumber &&
            lot.lotNumber == lotDraft.lotNumber,
      );

      setState(() {
        _availableLots = updatedLots;
        _selectedLotId = createdLot.id;
        _syncLotPriceFromSelection();
      });

      if (widget.onLotCreated != null) {
        await widget.onLotCreated!();
      }

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Solar creado y seleccionado en la venta.'),
        ),
      );
    } on DuplicateLotException catch (error) {
      print('[SALE-FORM][LOT] DuplicateLotException: ${error.message}');
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error, stack) {
      print('[SALE-FORM][LOT] ERROR $error');
      print(stack);
      if (!mounted) {
        return;
      }

      FriendlyErrorMessages.forOperation(
        'guardar el solar',
        error,
        module: 'ventas',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingLot = false;
        });
      }
    }
  }

  Future<void> _createSellerQuickly() async {
    if (!_canCreateSellers) {
      print('[SALE-FORM][SELLER] stop: no permission to create sellers');
      return;
    }

    print('[SALE-FORM][SELLER] start create seller');
    final sellerDraft = await SellerFormDialog.show(context);
    if (!mounted || sellerDraft == null) {
      print(
        '[SALE-FORM][SELLER] stop: dialog closed or not mounted (mounted=$mounted, draft=${sellerDraft != null})',
      );
      return;
    }

    setState(() {
      _isCreatingSeller = true;
    });

    try {
      print(
        '[SALE-FORM][SELLER] after dialog -> docId=${sellerDraft.documentId} name=${sellerDraft.name}',
      );
      final existingSeller = await widget.sellerRepository
          .search(sellerDraft.documentId)
          .then(
            (sellers) => sellers
                .where((s) => s.documentId == sellerDraft.documentId)
                .firstOrNull,
          );

      if (existingSeller != null) {
        print(
          '[SALE-FORM][SELLER] existing seller found -> selecting id=${existingSeller.id}',
        );
        final updatedSellers = await widget.sellerRepository.getAll();

        setState(() {
          _sellers = updatedSellers;
          _selectedSellerId = existingSeller.id;
        });

        if (!mounted) {
          return;
        }

        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text(
              'Ya existe un vendedor con esa cedula. Se selecciono el registro existente.',
            ),
          ),
        );
        return;
      }

      print('[SALE-FORM][SELLER] inserting seller...');
      await widget.sellerRepository.insert(sellerDraft);
      print('[SALE-FORM][SELLER] inserted -> reloading sellers');
      final updatedSellers = await widget.sellerRepository.getAll();
      final createdSeller = updatedSellers.firstWhere(
        (seller) => seller.documentId == sellerDraft.documentId,
      );

      setState(() {
        _sellers = updatedSellers;
        _selectedSellerId = createdSeller.id;
      });

      if (widget.onSellerCreated != null) {
        await widget.onSellerCreated!();
      }

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Vendedor creado y seleccionado en la venta.'),
        ),
      );
    } catch (error, stack) {
      print('[SALE-FORM][SELLER] ERROR $error');
      print(stack);
      if (!mounted) {
        return;
      }

      final message = error.toString().contains('UNIQUE constraint failed')
          ? 'Ya existe un vendedor con esa cedula. Revise el registro existente.'
          : null;

      if (message != null) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text(message)));
      } else {
        FriendlyErrorMessages.forOperation(
          'guardar el vendedor',
          error,
          module: 'ventas',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingSeller = false;
        });
      }
    }
  }

  Future<void> _pickSaleDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _saleDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (pickedDate == null) {
      return;
    }

    setState(() {
      _saleDate = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        _saleDate.hour,
        _saleDate.minute,
      );
      _saleDateController.text = _formatDate(_saleDate);
      _syncInitialDeadline();
    });
  }

  Future<void> _pickInitialDeadline() async {
    if (_pendingInitialPayment <= 0.009) {
      return;
    }

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _initialPaymentDeadline ?? _buildAutomaticInitialDeadline(),
      firstDate: _saleDate,
      lastDate: DateTime(2100),
    );

    if (pickedDate == null) {
      return;
    }

    setState(() {
      _initialPaymentDeadline = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
      );
      _isInitialDeadlineManuallyEdited = true;
      _initialDeadlineController.text = _formatDate(_initialPaymentDeadline!);
    });
  }

  DateTime _buildAutomaticInitialDeadline() {
    final automaticDeadline = _saleDate.add(const Duration(days: 25));
    return DateTime(
      automaticDeadline.year,
      automaticDeadline.month,
      automaticDeadline.day,
    );
  }

  void _syncInitialDeadline() {
    if (_pendingInitialPayment <= 0.009) {
      _initialPaymentDeadline = null;
      _initialDeadlineController.clear();
      _isInitialDeadlineManuallyEdited = false;
      return;
    }

    if (_isInitialDeadlineManuallyEdited && _initialPaymentDeadline != null) {
      return;
    }

    _initialPaymentDeadline = _buildAutomaticInitialDeadline();
    _initialDeadlineController.text = _formatDate(_initialPaymentDeadline!);
  }

  void _save() {
    print('[SALE-FORM][SAVE] start');
    final valid = _formKey.currentState!.validate();
    print('[SALE-FORM][SAVE] form validate -> $valid');
    if (!valid) {
      print('[SALE-FORM][SAVE] stop: invalid form');
      return;
    }

    final selectedLot = _selectedLot;
    if (_selectedClientId == null ||
        selectedLot == null ||
        selectedLot.id == null) {
      print(
        '[SALE-FORM][SAVE] stop: missing selection clientId=$_selectedClientId lot=${selectedLot?.id}',
      );
      return;
    }

    final currentUserId = _currentUserId;
    if (currentUserId == null) {
      print('[SALE-FORM][SAVE] stop: currentUserId is null');
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            'No hay un usuario autenticado valido para registrar la venta.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final salePrice = _salePrice;
    if (salePrice <= 0) {
      print('[SALE-FORM][SAVE] stop: salePrice <= 0 ($salePrice)');
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('El precio total de la venta debe ser mayor que cero.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_initialPaymentPaid - salePrice > 0.009) {
      print(
        '[SALE-FORM][SAVE] stop: initialPaid exceeds salePrice initial=$_initialPaymentPaid salePrice=$salePrice',
      );
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            'El inicial pagado no puede exceder el precio total de la venta.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validación crítica: el solar debe estar disponible
    if (!_isEditingSale && selectedLot.status != 'disponible') {
      print(
        '[SALE-FORM][SAVE] stop: lot not available status=${selectedLot.status} code=${selectedLot.displayCode}',
      );
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            'El solar ${selectedLot.displayCode} no está disponible para venta. '
            'Estado actual: ${selectedLot.status}',
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    print(
      '[SALE-FORM][SAVE] ok -> pop draft clientId=$_selectedClientId lotId=${selectedLot.id} sellerId=$_selectedSellerId userId=$currentUserId price=$salePrice',
    );
    Navigator.of(context).pop(
      SaleDraft(
        clientId: _selectedClientId!,
        lotId: selectedLot.id!,
        userId: currentUserId,
        sellerId: _selectedSellerId,
        saleDate: _saleDate,
        salePrice: salePrice,
        downPaymentPercentage: _downPaymentPercentage,
        requiredInitialPayment: _requiredInitialPayment,
        initialPaymentPaid: _appliedInitialPayment,
        initialPaymentMethod: _selectedInitialPaymentMethod,
        minimumReserveAmount: null,
        initialPaymentDeadline: _initialPaymentDeadline,
        monthlyInterest: _monthlyInterest,
        installmentCount: _installmentCount,
        status: _saleLifecycleStatus,
        additionalLotIds: _additionalLotIds.toList(),
      ),
    );
  }

  void _handleCancel() {
    if (!_hasFormData) {
      Navigator.of(context).pop();
      return;
    }

    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Cancelar formulario?'),
        content: const Text(
          'Si cierras este formulario, se perderán todos los datos ingresados. ¿Estás seguro?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Continuar editando'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(true);
              Navigator.of(context).pop();
            },
            child: const Text('Descartar cambios'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString().padLeft(4, '0');
    return '$day/$month/$year';
  }

  double _parseDouble(String? value, double fallback) {
    if (value == null || value.trim().isEmpty) {
      return fallback;
    }

    final parsed = parseRdCurrency(value);
    if (!parsed.isFinite) {
      return fallback;
    }

    return parsed;
  }

  String _formatCurrencyInput(double value) {
    return formatRdCurrency(value);
  }

  int _parseInt(String? value, int fallback) {
    if (value == null || value.trim().isEmpty) {
      return fallback;
    }

    return int.tryParse(value.trim()) ?? fallback;
  }

  Client? _findClientById(int? clientId) {
    if (clientId == null) {
      return null;
    }

    for (final client in _clients) {
      if (client.id == clientId) {
        return client;
      }
    }

    return null;
  }

  Seller? _findSellerById(int? sellerId) {
    if (sellerId == null) {
      return null;
    }

    for (final seller in _sellers) {
      if (seller.id == sellerId) {
        return seller;
      }
    }

    return null;
  }

  /// Abre el diálogo para editar un cliente sin cerrar el formulario de venta
  Future<void> _editClientInline(Client clientToEdit) async {
    if (!_canUpdateClients) {
      return;
    }

    final editedClient = await ClientFormDialog.show(
      context,
      initialClient: clientToEdit,
    );

    if (!mounted || editedClient == null) {
      return;
    }

    try {
      await widget.clientRepository.save(editedClient);
      final updatedClients = await widget.clientRepository.fetchAll();
      final selectedClient = updatedClients
          .where((client) => client.id == editedClient.id)
          .firstOrNull;

      if (!mounted) {
        return;
      }

      setState(() {
        _clients = updatedClients;
        _selectedClientId = selectedClient?.id;
        _clientSearchController.text = selectedClient?.fullName ?? '';
      });

      if (widget.onClientCreated != null) {
        await widget.onClientCreated!();
      }

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Cliente actualizado correctamente.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      FriendlyErrorMessages.forOperation(
        'actualizar el cliente',
        error,
        module: 'ventas',
      );
    }
  }

  /// Abre el diálogo para editar un vendedor sin cerrar el formulario de venta
  Future<void> _editSellerInline(Seller sellerToEdit) async {
    if (!_canUpdateSellers) {
      return;
    }

    final editedSeller = await SellerFormDialog.show(
      context,
      initialSeller: sellerToEdit,
    );

    if (!mounted || editedSeller == null) {
      return;
    }

    try {
      await widget.sellerRepository.update(editedSeller);
      final updatedSellers = await widget.sellerRepository.getAll();
      final selectedSeller = updatedSellers
          .where((seller) => seller.id == editedSeller.id)
          .firstOrNull;

      if (!mounted) {
        return;
      }

      setState(() {
        _sellers = updatedSellers;
        _selectedSellerId = selectedSeller?.id;
        _sellerSearchController.text = selectedSeller?.name ?? '';
      });

      if (widget.onSellerCreated != null) {
        await widget.onSellerCreated!();
      }

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Vendedor actualizado correctamente.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      FriendlyErrorMessages.forOperation(
        'actualizar el vendedor',
        error,
        module: 'ventas',
      );
    }
  }

  /// Dialog discreto para agregar otro solar
  Future<void> _showAddLotDialog() async {
    final searchController = TextEditingController();
    try {
      final lotId = await showDialog<int>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              final availableLots = _getAvailableLotsForAddition();
              final searchQuery = searchController.text.trim().toLowerCase();
              final filteredLots = searchQuery.isEmpty
                  ? availableLots
                  : availableLots.where((lot) {
                      return lot.displayCode.toLowerCase().contains(
                            searchQuery,
                          ) ||
                          lot.area.toString().contains(searchQuery) ||
                          lot.pricePerSquareMeter.toString().contains(
                            searchQuery,
                          ) ||
                          lot.totalPrice.toString().contains(searchQuery);
                    }).toList();

              return AlertDialog(
                title: const Text('Agregar otro solar'),
                content: SizedBox(
                  width: 500,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: searchController,
                        decoration: InputDecoration(
                          hintText:
                              'Buscar por código, área, precio por metro o total...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    searchController.clear();
                                    setDialogState(() {});
                                  },
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                        onChanged: (_) {
                          setDialogState(() {});
                        },
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        child: filteredLots.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(
                                    searchQuery.isEmpty
                                        ? 'No hay solares disponibles'
                                        : 'No hay coincidencias con la búsqueda',
                                    style: TextStyle(
                                      color: Theme.of(
                                        dialogContext,
                                      ).colorScheme.outline,
                                    ),
                                  ),
                                ),
                              )
                            : SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ...filteredLots.map((lot) {
                                      return ListTile(
                                        title: Text(
                                          '${lot.displayCode} • ${lot.area.toStringAsFixed(2)} m²',
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                        subtitle: Text(
                                          'RD\$${formatRdCurrency(lot.pricePerSquareMeter)}/m² • Total RD\$${formatRdCurrency(lot.totalPrice)}',
                                          style: TextStyle(
                                            color: Theme.of(
                                              dialogContext,
                                            ).colorScheme.primary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        onTap: () {
                                          Navigator.of(
                                            dialogContext,
                                          ).pop(lot.id);
                                        },
                                      );
                                    }),
                                  ],
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancelar'),
                  ),
                ],
              );
            },
          );
        },
      );

      if (lotId != null && mounted) {
        setState(() {
          _additionalLotIds.add(lotId);
          _syncLotPriceFromSelection();
        });
      }
    } finally {
      searchController.dispose();
    }
  }

  /// Retorna solares disponibles para agregar (excluyendo el principal y ya seleccionados)
  List<Lot> _getAvailableLotsForAddition() {
    final selectedIds = {_selectedLotId, ..._additionalLotIds};
    return _availableLots
        .where((lot) => !selectedIds.contains(lot.id))
        .toList();
  }

  /// Edita un solar creado en este formulario
  Future<void> _editLotInline(Lot lotToEdit) async {
    if (!_canUpdateLots) {
      return;
    }

    final editedLot = await LotFormDialog.show(
      context,
      initialLot: lotToEdit,
      showStatusField: false,
    );

    if (!mounted || editedLot == null) {
      return;
    }

    setState(() {
      _isEditingLot = true;
    });

    try {
      await widget.lotRepository.save(editedLot.copyWith(status: 'disponible'));
      final updatedLots = await widget.lotRepository.fetchAvailable();
      final selectedLotId = _selectedLotId;
      final selectedLotExists =
          selectedLotId != null && updatedLots.any((lot) => lot.id == selectedLotId);

      if (!mounted) {
        return;
      }

      setState(() {
        _availableLots = updatedLots;
        if (!selectedLotExists) {
          _selectedLotId = null;
          _additionalLotIds.clear();
        }
        _syncLotPriceFromSelection();
      });

      if (widget.onLotCreated != null) {
        await widget.onLotCreated!();
      }

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Solar actualizado correctamente.')),
      );
    } on DuplicateLotException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      FriendlyErrorMessages.forOperation(
        'actualizar el solar',
        error,
        module: 'ventas',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isEditingLot = false;
        });
      }
    }
  }

  /// Muestra detalles del solar seleccionado
  Future<void> _viewLotDetails(Lot lot) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Detalles del Solar ${lot.displayCode}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('Código', lot.displayCode),
              _buildDetailRow('Manzana', lot.blockNumber.toString()),
              _buildDetailRow('Número', lot.lotNumber.toString()),
              _buildDetailRow(
                'Metros cuadrados',
                '${lot.area.toStringAsFixed(2)} m²',
              ),
              _buildDetailRow(
                'Precio por metro',
                'RD\$${formatRdCurrency(lot.pricePerSquareMeter)} /m²',
              ),
              _buildDetailRow(
                'Precio total',
                'RD\$${formatRdCurrency(lot.totalPrice)}',
              ),
              _buildDetailRow('Estado', lot.status),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.of(context).pop();
              await _editLotInline(lot);
            },
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Editar'),
          ),
        ],
      ),
    );
  }

  /// Widget helper para mostrar detalles en dos columnas
  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: Colors.grey[600]),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _InstallmentCountInput extends StatefulWidget {
  const _InstallmentCountInput({
    required this.useDirectCount,
    required this.directCountController,
    required this.durationYears,
    required this.durationMonths,
    required this.onModeChanged,
    required this.onDurationChanged,
    required this.onDirectCountChanged,
    required this.salePrice,
  });

  final bool useDirectCount;
  final TextEditingController directCountController;
  final int durationYears;
  final int durationMonths;
  final ValueChanged<bool> onModeChanged;
  final Function(int years, int months) onDurationChanged;
  final ValueChanged<String> onDirectCountChanged;
  final double salePrice;

  @override
  State<_InstallmentCountInput> createState() => _InstallmentCountInputState();
}

class _InstallmentCountInputState extends State<_InstallmentCountInput> {
  late int _years;
  late int _months;

  @override
  void initState() {
    super.initState();
    _years = widget.durationYears;
    _months = widget.durationMonths;
  }

  @override
  Widget build(BuildContext context) {
    final calculatedInstallments = (_years * 12) + _months;
    final theme = Theme.of(context);
    final modeSelector = _buildModeSelector(theme);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 390;
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cuotas',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(width: double.infinity, child: modeSelector),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Cuotas',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: modeSelector,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        if (widget.useDirectCount)
          TextFormField(
            controller: widget.directCountController,
            decoration: const InputDecoration(
              labelText: 'Número de cuotas',
              prefixIcon: Icon(Icons.numbers_outlined),
            ),
            keyboardType: TextInputType.number,
            onChanged: widget.onDirectCountChanged,
            validator: (value) {
              final parsed = int.tryParse(value?.trim() ?? '');
              if (parsed == null || parsed <= 0) {
                return 'Debe ser mayor que 0';
              }
              if (widget.salePrice <= 0) {
                return 'Solar con precio válido';
              }
              return null;
            },
          )
        else
          Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildDurationField(
                      context,
                      label: 'Años',
                      value: _years,
                      maxValue: 99,
                      onChanged: (nextValue) {
                        setState(() => _years = nextValue);
                        widget.onDurationChanged(_years, _months);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildDurationField(
                      context,
                      label: 'Meses',
                      value: _months,
                      maxValue: 11,
                      onChanged: (nextValue) {
                        setState(() => _months = nextValue);
                        widget.onDurationChanged(_years, _months);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '$calculatedInstallments cuotas mensuales',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildModeSelector(ThemeData theme) {
    return Container(
      constraints: const BoxConstraints(minHeight: 46, maxWidth: 250),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: _buildModeOption(
              theme,
              selected: widget.useDirectCount,
              icon: Icons.input_outlined,
              label: 'Directo',
              onTap: () => widget.onModeChanged(true),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildModeOption(
              theme,
              selected: !widget.useDirectCount,
              icon: Icons.schedule_outlined,
              label: 'Duración',
              onTap: () => widget.onModeChanged(false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeOption(
    ThemeData theme, {
    required bool selected,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final foregroundColor = selected
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onSurfaceVariant;

    return Material(
      color: selected
          ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.95)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: foregroundColor),
                const SizedBox(width: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: foregroundColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDurationField(
    BuildContext context, {
    required String label,
    required int value,
    required int maxValue,
    required ValueChanged<int> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 32,
          child: IconButton(
            onPressed: value > 0 ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove, size: 16),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: TextFormField(
            initialValue: value.toString(),
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: label),
            onChanged: (rawValue) {
              final parsed = int.tryParse(rawValue.trim()) ?? 0;
              onChanged(parsed.clamp(0, maxValue));
            },
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 32,
          child: IconButton(
            onPressed: value < maxValue ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add, size: 16),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }
}
