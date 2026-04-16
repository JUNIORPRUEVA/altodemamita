import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/database/app_database.dart';
import '../../../core/resilience/friendly_error_messages.dart';
import '../../../core/system/system_config_service.dart';
import '../../../features/auth/domain/admin_override_scope.dart';
import '../../../features/auth/domain/permission_model.dart';
import '../../../features/auth/presentation/admin_override_prompt.dart';
import '../../../features/auth/presentation/auth_provider.dart';
import '../data/financial_params_repository.dart';
import '../data/settings_repository.dart';
import '../domain/financial_params.dart';
import '../../../shared/widgets/base_layout.dart';
import '../../../shared/widgets/recovery_experience.dart';

class FinancialParamsPage extends StatefulWidget {
  const FinancialParamsPage({super.key});

  @override
  State<FinancialParamsPage> createState() => _FinancialParamsPageState();
}

class _FinancialParamsPageState extends State<FinancialParamsPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _inicialPercentController;
  late final TextEditingController _interesController;
  late final TextEditingController _cuotasController;
  late final TextEditingController _monedaController;

  bool _isSaving = false;
  FriendlyErrorMessage? _loadError;

  @override
  void initState() {
    super.initState();
    _inicialPercentController = TextEditingController(text: '10');
    _interesController = TextEditingController(text: '1');
    _cuotasController = TextEditingController(text: '12');
    _monedaController = TextEditingController(text: 'RD\$');
    _loadParams();
  }

  @override
  void dispose() {
    _inicialPercentController.dispose();
    _interesController.dispose();
    _cuotasController.dispose();
    _monedaController.dispose();
    super.dispose();
  }

  bool _canManageFinancial(AuthProvider auth) {
    return auth.hasScopedAccess(
      scope: AdminOverrideScope.settingsFinancial,
      module: PermissionCatalog.settings,
      action: PermissionAction.update,
    );
  }

  Future<bool> _ensureAuthorized() async {
    final auth = context.read<AuthProvider>();
    if (_canManageFinancial(auth)) {
      return true;
    }

    return requestAdminOverride(
      context,
      scope: AdminOverrideScope.settingsFinancial,
      title: 'Autorización administrativa requerida',
      message:
          'Necesitas la clave de un administrador para abrir o modificar los parámetros financieros.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isReadOnly = context.watch<SystemConfigService>().isReadOnly;

    return BaseLayout(
      title: 'Parámetros Financieros',
      child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _loadError != null
                  ? Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: InlineModuleRecoveryCard(
                          title: _loadError!.title,
                          message: _loadError!.message,
                          details: _loadError!.details,
                          suggestions: _loadError!.suggestions,
                          onRetry: _loadParams,
                        ),
                      ),
                    )
                  : Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Valores por defecto',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Estos valores se usarán cuando se cree una nueva venta',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 24),

                          // Parámetros de pago
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Parámetros de pago',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextFormField(
                                          controller: _inicialPercentController,
                                          enabled: !isReadOnly,
                                          decoration: const InputDecoration(
                                            labelText: 'Inicial %',
                                            suffixText: '%',
                                            prefixIcon: Icon(
                                              Icons.percent_outlined,
                                            ),
                                          ),
                                          keyboardType: TextInputType.number,
                                          validator: (value) {
                                            final parsed = double.tryParse(
                                              value ?? '',
                                            );
                                            if (parsed == null ||
                                                parsed < 0 ||
                                                parsed >= 100) {
                                              return 'Entre 0-100';
                                            }
                                            return null;
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: TextFormField(
                                          controller: _interesController,
                                          enabled: !isReadOnly,
                                          decoration: const InputDecoration(
                                            labelText: 'Interés mensual %',
                                            suffixText: '%',
                                            prefixIcon: Icon(
                                              Icons.trending_up_outlined,
                                            ),
                                          ),
                                          keyboardType: TextInputType.number,
                                          validator: (value) {
                                            final parsed = double.tryParse(
                                              value ?? '',
                                            );
                                            if (parsed == null || parsed < 0) {
                                              return 'No negativo';
                                            }
                                            return null;
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: _cuotasController,
                                    enabled: !isReadOnly,
                                    decoration: const InputDecoration(
                                      labelText:
                                          'Cantidad de cuotas por defecto *',
                                      prefixIcon: Icon(
                                        Icons.calendar_month_outlined,
                                      ),
                                    ),
                                    keyboardType: TextInputType.number,
                                    validator: (value) {
                                      final parsed = int.tryParse(value ?? '');
                                      if (parsed == null || parsed <= 0) {
                                        return 'Debe ser mayor a 0';
                                      }
                                      return null;
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Configuración de moneda
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Configuración de moneda',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: _monedaController,
                                    enabled: !isReadOnly,
                                    decoration: const InputDecoration(
                                      labelText: 'Símbolo de moneda *',
                                      prefixIcon: Icon(
                                        Icons.currency_exchange_outlined,
                                      ),
                                      hintText: 'Ej: RD\$, \$, USD',
                                    ),
                                    validator: (value) {
                                      if (value == null ||
                                          value.trim().isEmpty) {
                                        return 'El símbolo es requerido';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Los valores se mostrarán con este símbolo en todo el sistema',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Botones
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => Navigator.pop(context),
                                  icon: const Icon(Icons.close),
                                  label: const Text('Cancelar'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _isSaving || isReadOnly
                                      ? null
                                      : _save,
                                  icon: const Icon(Icons.save_outlined),
                                  label: Text(
                                    _isSaving ? 'Guardando...' : 'Guardar',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
            ),
    );
  }

  Future<void> _loadParams() async {
    try {
      final db = await AppDatabase.instance.database;
      final repo = FinancialParamsRepository(db);
      final params = await repo.getParams();
      if (!mounted) return;
      setState(() {
        _inicialPercentController.text = params.initialPercentageDefault
            .toString();
        _interesController.text = params.monthlyInterestDefault.toString();
        _cuotasController.text = params.installmentCountDefault.toString();
        _monedaController.text = params.currencySymbol;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = FriendlyErrorMessages.moduleLoad(
          'parámetros financieros',
          error,
        );
      });
    }
  }

  Future<void> _save() async {
    if (!await _ensureAuthorized()) {
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSaving = true);

    try {
      final db = await AppDatabase.instance.database;
      final financialRepo = FinancialParamsRepository(db);
      final settingsRepo = SettingsRepository();

      final params = FinancialParams(
        initialPercentageDefault: double.parse(
          _inicialPercentController.text.trim(),
        ),
        monthlyInterestDefault: double.parse(_interesController.text.trim()),
        installmentCountDefault: int.parse(_cuotasController.text.trim()),
        currencySymbol: _monedaController.text.trim(),
        fechaActualizacion: DateTime.now(),
      );

      await financialRepo.saveParams(params);

      // Sincronizar con la tabla configuracion para que SalesController
      // los tome como defaults al cargar el formulario de venta.
      await settingsRepo.saveMultiple({
        SettingsRepository.saleDefaultDownPaymentKey: params
            .initialPercentageDefault
            .toString(),
        SettingsRepository.saleDefaultMonthlyInterestKey: params
            .monthlyInterestDefault
            .toString(),
        SettingsRepository.saleDefaultInstallmentCountKey: params
            .installmentCountDefault
            .toString(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Parámetros guardados correctamente')),
      );

      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      FriendlyErrorMessages.forOperation(
        'guardar los parámetros financieros',
        error,
        module: 'configuracion',
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
}
