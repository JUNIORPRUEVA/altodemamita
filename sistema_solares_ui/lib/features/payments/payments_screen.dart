import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:sistema_solares_ui/core/network/api_client.dart';
import 'package:sistema_solares_ui/core/realtime/realtime_controller.dart';
import 'package:sistema_solares_ui/features/reports/reports_service.dart';
import 'package:sistema_solares_ui/shared/desktop_ui.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  int _days = 30;
  Future<List<Map<String, dynamic>>>? _future;
  int _lastTick = -1;

  void _reloadFor(int days) {
    setState(() {
      _days = days;
      _future = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final refreshTick = context.watch<RealtimeController>().refreshTick;
    if (_future == null || refreshTick != _lastTick) {
      _lastTick = refreshTick;
      _future = ReportsService(
        context.read<ApiClient>(),
      ).fetchPayments(days: _days);
    }

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return DesktopPageError(
            message: snapshot.error.toString(),
            onRetry: () => _reloadFor(_days),
          );
        }

        final payments = snapshot.data!;
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
              : 'Seguimiento compacto de los pagos recibidos en el periodo seleccionado.',
          toolbar: DesktopFieldToolbar(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (!compact)
                    const Text(
                      'Corte de pagos:',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ...[7, 30, 90].map(
                    (days) => ChoiceChip(
                      label: Text(
                        compact ? '$days dias' : 'Ultimos $days dias',
                      ),
                      selected: _days == days,
                      onSelected: (_) => _reloadFor(days),
                    ),
                  ),
                ],
              ),
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
                          final subtitleParts = <String>[
                            method,
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
