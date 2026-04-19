import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:sistema_solares_ui/core/network/api_client.dart';
import 'package:sistema_solares_ui/core/realtime/realtime_controller.dart';
import 'package:sistema_solares_ui/features/payments/payments_service.dart';
import 'package:sistema_solares_ui/shared/desktop_ui.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  final _searchController = TextEditingController();
  Future<PaymentsPageData>? _future;
  int _lastTick = -1;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _future = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final refreshTick = context.watch<RealtimeController>().refreshTick;
    if (_future == null || refreshTick != _lastTick) {
      _lastTick = refreshTick;
      _future = PaymentsService(
        context.read<ApiClient>(),
      ).fetch(search: _searchController.text);
    }

    return FutureBuilder<PaymentsPageData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return DesktopPageError(
            message: snapshot.error.toString(),
            onRetry: _reload,
          );
        }

        final data = snapshot.data!;
        final payments = data.items;
        final compact = MediaQuery.sizeOf(context).width < 760;
        final currency = NumberFormat.currency(locale: 'es_DO', symbol: r'$');
        final totalCollected = payments.fold<double>(
          0,
          (total, payment) => total + _asNum(payment['amount']),
        );
        final averageTicket = payments.isEmpty
            ? 0.0
            : totalCollected / payments.length;
        final methods = payments
            .map((payment) => payment['method']?.toString().trim() ?? '')
            .where((method) => method.isNotEmpty)
            .toSet();
        final lastPaymentDate = payments
            .map((payment) => _parseDate(payment['paymentDate']))
            .whereType<DateTime>()
            .fold<DateTime?>(
              null,
              (latest, current) =>
                  latest == null || current.isAfter(latest) ? current : latest,
            );

        return DesktopPageScaffold(
          title: 'Pagos',
          subtitle: compact
              ? 'Cobros clave del periodo con lectura rapida.'
              : 'Seguimiento compacto de los pagos sincronizados y recibidos.',
          toolbar: DesktopFieldToolbar(
            child: DesktopToolbar(
              searchField: DesktopSearchField(
                controller: _searchController,
                hintText: 'Buscar por cliente, referencia o contrato',
                onSubmitted: (_) => _reload(),
              ),
              actions: [
                OutlinedButton.icon(
                  onPressed: () {
                    _searchController.clear();
                    _reload();
                  },
                  icon: const Icon(Icons.cleaning_services_outlined),
                  label: const Text('Limpiar'),
                ),
                FilledButton.icon(
                  onPressed: _reload,
                  icon: const Icon(Icons.search_rounded),
                  label: const Text('Buscar'),
                ),
              ],
              compactActions: [
                OutlinedButton.icon(
                  onPressed: () {
                    _searchController.clear();
                    _reload();
                  },
                  icon: const Icon(Icons.cleaning_services_outlined),
                  label: const Text('Limpiar'),
                ),
                FilledButton.icon(
                  onPressed: _reload,
                  icon: const Icon(Icons.search_rounded),
                  label: const Text('Buscar'),
                ),
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DesktopInfoStrip(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    DesktopTag(
                      label: compact
                          ? '${payments.length} cobros'
                          : 'Cobros ${payments.length}',
                      background: const Color(0xFFF1F4FA),
                    ),
                    DesktopTag(
                      label: currency.format(totalCollected),
                      background: const Color(0xFFEAF4ED),
                      foreground: const Color(0xFF2F6F5C),
                    ),
                    if (!compact)
                      DesktopTag(
                        label: 'Ticket ${currency.format(averageTicket)}',
                        background: const Color(0xFFF6EFE3),
                        foreground: const Color(0xFF8C5A2C),
                      ),
                    if (!compact)
                      DesktopTag(
                        label: 'Metodos ${methods.length}',
                        background: const Color(0xFFF5EEF8),
                        foreground: const Color(0xFF7A4A97),
                      ),
                    if (!compact)
                      DesktopTag(
                        label: 'Pag. ${data.page}/${data.totalPages}',
                        background: const Color(0xFFF1F4FA),
                      ),
                    if (lastPaymentDate != null)
                      DesktopTag(
                        label: DateFormat(
                          'dd MMM yyyy',
                          'es_DO',
                        ).format(lastPaymentDate),
                        background: const Color(0xFFF1F4FA),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: payments.isEmpty
                    ? const DesktopEmptyState(
                        icon: Icons.payments_outlined,
                        title: 'Sin pagos en este corte',
                        message:
                            'Ajusta el rango o espera la siguiente sincronizacion para ver nuevos cobros.',
                      )
                    : DesktopModuleList(
                        children: payments.map((payment) {
                          final client = _readClientName(payment);
                          final sale = payment['sale'] as Map<String, dynamic>?;
                          final product =
                              (sale?['product']
                                      as Map<String, dynamic>?)?['name']
                                  ?.toString() ??
                              'Sin solar';
                          final method =
                              payment['method']?.toString() ??
                              'Metodo no definido';
                          final date = _formatDate(payment['paymentDate']);
                          final contract =
                              sale?['contractNumber']?.toString().trim() ?? '';
                          final subtitleParts = <String>[
                            method,
                            if (contract.isNotEmpty) contract,
                            if (!compact && product.trim().isNotEmpty) product,
                            date,
                          ];

                          return DesktopListRow(
                            height: compact ? 104 : 86,
                            leading: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEAF4ED),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.payments_outlined,
                                color: Color(0xFF2F6F5C),
                              ),
                            ),
                            title: Text(
                              client,
                              maxLines: compact ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              subtitleParts.join(compact ? '\n' : '  •  '),
                              maxLines: compact ? 4 : 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Color(0xFF6E7791)),
                            ),
                            trailing: DesktopTag(
                              label: currency.format(_asNum(payment['amount'])),
                              background: const Color(0xFFF6EFE3),
                              foreground: const Color(0xFF8C5A2C),
                            ),
                          );
                        }).toList(),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _readClientName(Map<String, dynamic> payment) {
    final sale = payment['sale'] as Map<String, dynamic>?;
    final client = sale?['client'] as Map<String, dynamic>?;
    final firstName = client?['firstName']?.toString().trim() ?? '';
    final lastName = client?['lastName']?.toString().trim() ?? '';
    final fullName = [
      firstName,
      lastName,
    ].where((value) => value.isNotEmpty).join(' ').trim();
    return fullName.isEmpty ? 'Cliente no disponible' : fullName;
  }

  String _formatDate(Object? value) {
    final parsed = _parseDate(value);
    if (parsed == null) {
      return '-';
    }
    return DateFormat('dd MMM yyyy', 'es_DO').format(parsed);
  }

  DateTime? _parseDate(Object? value) {
    final raw = value?.toString();
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw);
  }

  double _asNum(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
