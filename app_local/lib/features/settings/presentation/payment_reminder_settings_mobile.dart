import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/network/backend_api_client.dart';
import '../../../shared/mobile/mobile_ui.dart';
import '../data/payment_reminder_settings_repository.dart';

class PaymentReminderSettingsMobilePage extends StatefulWidget {
  const PaymentReminderSettingsMobilePage({
    super.key,
    PaymentReminderSettingsRepository? repository,
  }) : _repository = repository;

  final PaymentReminderSettingsRepository? _repository;

  @override
  State<PaymentReminderSettingsMobilePage> createState() =>
      _PaymentReminderSettingsMobilePageState();
}

class _PaymentReminderSettingsMobilePageState
    extends State<PaymentReminderSettingsMobilePage> {
  late final PaymentReminderSettingsRepository _repository;

  late PaymentReminderAdminState _state;
  String? _error;
  bool _refreshing = false;
  bool _saving = false;
  static const _cloudLoadTimeout = Duration(seconds: 25);

  @override
  void initState() {
    super.initState();
    _state = PaymentReminderAdminState.fallback();
    _repository = widget._repository ?? PaymentReminderSettingsRepository();
    unawaited(_loadCached());
    unawaited(_load());
  }

  Future<void> _loadCached() async {
    final cached = await _repository.loadCached();
    if (!mounted || cached == null) {
      return;
    }
    setState(() {
      _state = cached;
    });
  }

  Future<void> _load() async {
    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      final state = await _repository.load().timeout(
        _cloudLoadTimeout,
      );
      if (!mounted) return;
      setState(() {
        _state = state;
        _refreshing = false;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _error = 'No pudimos conectarnos al servicio de recordatorios.';
        _refreshing = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(error);
        _refreshing = false;
      });
    }
  }

  Future<void> _save({
    bool? enabled,
    String? phone,
    String? message,
    bool showSaved = true,
  }) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final state = await _repository.save(
        notificationsEnabled: enabled,
        senderWhatsAppNumber: phone,
        editableMessageFragment: message,
      );
      if (!mounted) return;
      setState(() {
        _state = state;
        _saving = false;
      });
      if (showSaved) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Configuracion guardada')));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _friendlyError(error);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_error ?? 'No pudimos guardar el cambio.')),
      );
    }
  }

  Future<void> _toggle(bool nextValue) async {
    if (_saving) return;
    if (!nextValue) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Desactivar recordatorios'),
          content: const Text(
            'Los clientes dejaran de recibir recordatorios automaticos de cuotas.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Desactivar'),
            ),
          ],
        ),
      );
      if (confirmed != true) {
        return;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final state = await _repository
          .setNotificationsEnabled(nextValue)
          .timeout(_cloudLoadTimeout);
      if (!mounted) return;
      setState(() {
        _state = state;
        _saving = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Configuracion guardada')));
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'No pudimos conectarnos al servicio de recordatorios.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No pudimos guardar el cambio. Intenta nuevamente.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _friendlyError(error, saving: true);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _error ?? 'No pudimos guardar el cambio. Intenta nuevamente.',
          ),
        ),
      );
    }
  }

  Future<void> _editPhone() async {
    final value = await showDialog<String>(
      context: context,
      builder: (context) =>
          _PhoneDialog(initialValue: _state.config.senderWhatsAppNumber),
    );
    if (value == null) return;
    await _save(phone: value);
  }

  Future<void> _editMessage() async {
    final value = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => _MessageEditorPage(
          state: _state,
          initialValue: _state.config.editableMessageFragment,
          maxLength: _state.config.maxMessageFragmentLength,
        ),
      ),
    );
    if (value == null) return;
    await _save(message: value);
  }

  void _openHowItWorks() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => _HowItWorksPage(state: _state)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MobileUi.background,
      appBar: AppBar(
        title: const Text('Notificaciones y recordatorios'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _saving || _refreshing ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: _Content(
            state: _state,
            saving: _saving,
            refreshing: _refreshing,
            error: _error,
            onRetry: _load,
            onToggle: _toggle,
            onEditPhone: _editPhone,
            onEditMessage: _editMessage,
            onHowItWorks: _openHowItWorks,
          ),
        ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({
    required this.state,
    required this.saving,
    required this.refreshing,
    required this.error,
    required this.onRetry,
    required this.onToggle,
    required this.onEditPhone,
    required this.onEditMessage,
    required this.onHowItWorks,
  });

  final PaymentReminderAdminState state;
  final bool saving;
  final bool refreshing;
  final String? error;
  final VoidCallback onRetry;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEditPhone;
  final VoidCallback onEditMessage;
  final VoidCallback onHowItWorks;

  @override
  Widget build(BuildContext context) {
    final enabled = state.config.notificationsEnabled;
    final effective = state.config.effectiveEnabled;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        if (refreshing) ...[
          const _RefreshStatusCard(),
          const SizedBox(height: 12),
        ],
        if (error != null) ...[
          _ReminderRefreshFailedBanner(message: error!, onRetry: onRetry),
          const SizedBox(height: 12),
        ],
        Text(
          'Controla el canal, la plantilla y la logica de envio de recordatorios por WhatsApp.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: MobileUi.textSecondary,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 14),
        _SectionCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Recordatorios automaticos',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: MobileUi.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      enabled
                          ? 'Envio segun la configuracion del servicio.'
                          : 'Los recordatorios estan desactivados.',
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: MobileUi.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    MobileStatusChip(
                      label: effective
                          ? 'Activo'
                          : enabled
                          ? 'Pausado por seguridad'
                          : 'Desactivado',
                      color: effective
                          ? MobileUi.success
                          : enabled
                          ? MobileUi.warning
                          : MobileUi.textSecondary,
                      compact: false,
                    ),
                  ],
                ),
              ),
              Switch(value: enabled, onChanged: saving ? null : onToggle),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _StatusCard(state: state),
        const SizedBox(height: 12),
        _ProviderCard(state: state, onEditPhone: saving ? null : onEditPhone),
        const SizedBox(height: 12),
        _TemplateCard(
          state: state,
          onEditMessage: saving ? null : onEditMessage,
        ),
        const SizedBox(height: 12),
        _LogicCard(state: state, onHowItWorks: onHowItWorks),
        const SizedBox(height: 12),
        _CandidatesCard(candidates: state.candidates),
        const SizedBox(height: 12),
        _StatsCard(stats: state.stats),
        const SizedBox(height: 12),
        _LastRunCard(lastRun: state.lastRun),
        const SizedBox(height: 12),
        _HistoryCard(items: state.history),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.state});

  final PaymentReminderAdminState state;

  @override
  Widget build(BuildContext context) {
    final text = state.config.effectiveEnabled
        ? 'Todo listo'
        : state.config.notificationsEnabled && !state.system.whatsappConfigured
        ? 'Falta configurar WhatsApp'
        : state.config.notificationsEnabled
        ? 'Servicio pausado por seguridad'
        : 'Recordatorios desactivados';

    return _SectionCard(
      child: Row(
        children: [
          Icon(
            state.config.effectiveEnabled
                ? Icons.check_circle_outline_rounded
                : Icons.info_outline_rounded,
            color: state.config.effectiveEnabled
                ? MobileUi.success
                : MobileUi.warning,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: MobileUi.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({required this.state, required this.onEditPhone});

  final PaymentReminderAdminState state;
  final VoidCallback? onEditPhone;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel('Cuenta WhatsApp'),
          const SizedBox(height: 12),
          _DetailRow(
            icon: Icons.call_outlined,
            label: 'Numero visible',
            value: state.config.senderWhatsAppNumber.isEmpty
                ? 'Sin numero visible'
                : _readablePhone(state.config.senderWhatsAppNumber),
          ),
          _DetailRow(
            icon: Icons.tag_outlined,
            label: 'ID del numero',
            value: state.system.whatsappPhoneNumberId.isEmpty
                ? 'No configurado'
                : state.system.whatsappPhoneNumberId,
          ),
          _DetailRow(
            icon: Icons.business_center_outlined,
            label: 'ID de cuenta WhatsApp',
            value: state.system.whatsappBusinessAccountId.isEmpty
                ? 'No configurado'
                : state.system.whatsappBusinessAccountId,
          ),
          _DetailRow(
            icon: Icons.verified_outlined,
            label: 'Estado tecnico',
            value: state.system.whatsappConfigured
                ? 'Proveedor configurado'
                : 'Falta ID de numero WhatsApp',
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onEditPhone,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Editar numero visible'),
          ),
        ],
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.state, required this.onEditMessage});

  final PaymentReminderAdminState state;
  final VoidCallback? onEditMessage;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel('Plantilla y mensaje'),
          const SizedBox(height: 12),
          _DetailRow(
            icon: Icons.description_outlined,
            label: 'Plantilla activa',
            value: state.config.activeTemplateName.isEmpty
                ? 'No configurada'
                : state.config.activeTemplateName,
          ),
          _DetailRow(
            icon: Icons.science_outlined,
            label: 'Plantilla de prueba',
            value: state.config.testTemplateName.isEmpty
                ? 'No configurada'
                : state.config.testTemplateName,
          ),
          _DetailRow(
            icon: Icons.language_outlined,
            label: 'Idioma',
            value: state.config.templateLanguage.isEmpty
                ? 'No configurado'
                : state.config.templateLanguage,
          ),
          const SizedBox(height: 10),
          Text(
            state.config.editableMessageFragment,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              height: 1.35,
              color: MobileUi.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(state.system.templatePolicy, style: MobileUi.itemSubtitle),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onEditMessage,
            icon: const Icon(Icons.edit_note_outlined),
            label: const Text('Configurar mensaje'),
          ),
        ],
      ),
    );
  }
}

class _LogicCard extends StatelessWidget {
  const _LogicCard({required this.state, required this.onHowItWorks});

  final PaymentReminderAdminState state;
  final VoidCallback onHowItWorks;

  @override
  Widget build(BuildContext context) {
    final schedule = state.system.schedule;
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel('Logica de envio'),
          const SizedBox(height: 12),
          _DetailRow(
            icon: Icons.schedule_outlined,
            label: 'Frecuencia',
            value: state.system.runFrequency.isEmpty
                ? 'Una vez al dia'
                : state.system.runFrequency,
          ),
          _DetailRow(
            icon: Icons.access_time_outlined,
            label: 'Ventana',
            value: '${schedule.windowLabel} (${schedule.timezone})',
          ),
          _DetailRow(
            icon: Icons.calendar_month_outlined,
            label: 'Dias permitidos',
            value: schedule.allowedDaysLabel,
          ),
          _DetailRow(
            icon: Icons.group_outlined,
            label: 'Destinatarios',
            value: state.system.recipientPolicy,
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: onHowItWorks,
            icon: const Icon(Icons.help_outline_rounded),
            label: const Text('Ejemplo: como funciona'),
          ),
        ],
      ),
    );
  }
}

class _CandidatesCard extends StatelessWidget {
  const _CandidatesCard({required this.candidates});

  final PaymentReminderCandidateSummary candidates;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel('Clientes que aplican'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetricPill(
                label: 'Ventas activas',
                value: candidates.activeSales,
              ),
              _MetricPill(label: 'Con atraso', value: candidates.overdueSales),
              _MetricPill(
                label: 'Telefono valido',
                value: candidates.withValidPhone,
              ),
              _MetricPill(
                label: 'Bloqueados',
                value: candidates.blockedWithoutPhone,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Cuotas vencidas: ${candidates.totalOverdueInstallments} · Total vencido: ${_formatMoney(candidates.totalDue)}',
            style: MobileUi.itemSubtitle,
          ),
          const SizedBox(height: 10),
          if (candidates.preview.isEmpty)
            const Text(
              'No hay clientes con cuotas vencidas en este momento.',
              style: MobileUi.itemSubtitle,
            )
          else
            for (final item in candidates.preview) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(
                  item.status == 'READY'
                      ? Icons.check_circle_outline_rounded
                      : Icons.block_outlined,
                  color: item.status == 'READY'
                      ? MobileUi.success
                      : MobileUi.warning,
                ),
                title: Text(
                  item.clientName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MobileUi.itemTitle,
                ),
                subtitle: Text(
                  '${item.lotLabel} · ${item.phoneMasked}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: MobileUi.itemSubtitle,
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatMoney(item.totalDue),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: MobileUi.textPrimary,
                      ),
                    ),
                    Text(
                      '${item.overdueInstallments} cuota(s)',
                      style: MobileUi.itemMeta,
                    ),
                  ],
                ),
              ),
              if (item != candidates.preview.last)
                const Divider(height: 1, color: MobileUi.divider),
            ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: MobileUi.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: MobileUi.itemMeta),
                const SizedBox(height: 2),
                SelectableText(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                    color: MobileUi.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MobileUi.border),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: MobileUi.textPrimary,
        ),
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.stats});

  final PaymentReminderStats stats;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel('Actividad reciente'),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            childAspectRatio: 2.4,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _StatTile(label: 'Enviados', value: stats.sent),
              _StatTile(label: 'Entregados', value: stats.delivered),
              _StatTile(label: 'Leidos', value: stats.read),
              _StatTile(label: 'Fallidos', value: stats.failed),
              _StatTile(label: 'Pendientes', value: stats.pending),
              _StatTile(label: 'Pruebas', value: stats.dryRun),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MobileUi.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: MobileUi.itemMeta),
          const SizedBox(height: 4),
          Text(
            '$value',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: MobileUi.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _LastRunCard extends StatelessWidget {
  const _LastRunCard({required this.lastRun});

  final PaymentReminderLastRun? lastRun;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel('Ultimo envio'),
          const SizedBox(height: 9),
          if (lastRun == null)
            const Text(
              'Todavia no se han enviado recordatorios.',
              style: MobileUi.itemSubtitle,
            )
          else ...[
            Text(
              _formatDateTime(lastRun!.sentAt ?? lastRun!.createdAt),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: MobileUi.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${_statusLabel(lastRun!.status)} · ${lastRun!.processedCount} cuota(s) procesadas',
              style: MobileUi.itemSubtitle,
            ),
          ],
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.items});

  final List<PaymentReminderHistoryItem> items;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel('Historial'),
          const SizedBox(height: 10),
          if (items.isEmpty)
            const Text(
              'Todavia no hay actividad registrada.',
              style: MobileUi.itemSubtitle,
            )
          else
            for (final item in items.take(8)) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(
                  _historyIcon(item.status),
                  color: _statusColor(item.status),
                ),
                title: Text(
                  item.clientName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MobileUi.itemTitle,
                ),
                subtitle: Text(
                  '${item.phoneMasked} · ${item.installmentCount} cuota(s)',
                  style: MobileUi.itemSubtitle,
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    MobileStatusChip(
                      label: _statusLabel(item.status),
                      color: _statusColor(item.status),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _shortDate(item.displayDate),
                      style: MobileUi.itemMeta,
                    ),
                  ],
                ),
              ),
              if (item != items.take(8).last)
                const Divider(height: 1, color: MobileUi.divider),
            ],
        ],
      ),
    );
  }
}

class _PhoneDialog extends StatefulWidget {
  const _PhoneDialog({required this.initialValue});

  final String initialValue;

  @override
  State<_PhoneDialog> createState() => _PhoneDialogState();
}

class _PhoneDialogState extends State<_PhoneDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('WhatsApp de envio'),
      content: TextField(
        controller: _controller,
        keyboardType: TextInputType.phone,
        decoration: InputDecoration(
          labelText: 'Numero visible',
          hintText: '+18095551234',
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final value = _controller.text.trim();
            if (value.isNotEmpty &&
                !RegExp(r'^\+?[0-9 ()-]{10,20}$').hasMatch(value)) {
              setState(() => _error = 'Formato de numero invalido.');
              return;
            }
            Navigator.of(context).pop(value);
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _MessageEditorPage extends StatefulWidget {
  const _MessageEditorPage({
    required this.state,
    required this.initialValue,
    required this.maxLength,
  });

  final PaymentReminderAdminState state;
  final String initialValue;
  final int maxLength;

  @override
  State<_MessageEditorPage> createState() => _MessageEditorPageState();
}

class _MessageEditorPageState extends State<_MessageEditorPage> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _controller.text.trim();
    return Scaffold(
      backgroundColor: MobileUi.background,
      appBar: AppBar(title: const Text('Mensaje al cliente')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _SectionLabel('Texto personalizado'),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              minLines: 4,
              maxLines: 7,
              maxLength: widget.maxLength,
              onChanged: (_) => setState(() => _error = null),
              decoration: InputDecoration(
                filled: true,
                fillColor: MobileUi.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                errorText: _error,
              ),
            ),
            const SizedBox(height: 12),
            const _SectionLabel('Campos de la plantilla'),
            const SizedBox(height: 8),
            _SectionCard(
              child: Column(
                children: [
                  for (final field in widget.state.template.editableFields) ...[
                    _DetailRow(
                      icon: field.editable
                          ? Icons.edit_outlined
                          : Icons.lock_outline_rounded,
                      label: field.editable
                          ? '${field.label} editable'
                          : '${field.label} automatico',
                      value: field.value,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            const _SectionLabel('Vista previa'),
            const SizedBox(height: 8),
            _SectionCard(
              child: Text(
                widget.state.template.preview.isEmpty
                    ? 'Hola Juan Perez.\n\n${text.isEmpty ? 'Te recordamos que tienes cuotas vencidas pendientes de pago.' : text}\n\nSolar: A-12\nCuotas vencidas: 2\nTotal vencido: RD\$15,000.00\nFecha de corte: 20 Sep 2026'
                    : widget.state.template.preview.replaceFirst(
                        widget.initialValue,
                        text.isEmpty
                            ? 'Te recordamos que tienes cuotas vencidas pendientes de pago.'
                            : text,
                      ),
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: MobileUi.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.state.system.templatePolicy,
              style: MobileUi.itemSubtitle,
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () {
                final normalized = _controller.text
                    .replaceAll(RegExp(r'\s+'), ' ')
                    .trim();
                if (normalized.isEmpty) {
                  setState(() => _error = 'El mensaje no puede estar vacio.');
                  return;
                }
                if (normalized.contains('{{') || normalized.contains('}}')) {
                  setState(
                    () => _error = 'No escribas variables de plantilla.',
                  );
                  return;
                }
                Navigator.of(context).pop(normalized);
              },
              child: const Text('Guardar cambios'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HowItWorksPage extends StatelessWidget {
  const _HowItWorksPage({required this.state});

  final PaymentReminderAdminState state;

  @override
  Widget build(BuildContext context) {
    final schedule = state.system.schedule;
    return Scaffold(
      backgroundColor: MobileUi.background,
      appBar: AppBar(title: const Text('Como funciona')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            _ExplanationCard(
              title: '1. A quien revisa',
              lines: [
                'Revisa ventas activas o en proceso. No toma ventas pagadas, canceladas, anuladas, cerradas ni saldadas.',
                'Solo entra en cola una venta con una o mas cuotas vencidas y saldo pendiente.',
                'Si el cliente no tiene telefono WhatsApp valido, queda visible como bloqueado y no se envia.',
              ],
            ),
            const SizedBox(height: 12),
            _ExplanationCard(
              title: '2. Cuando corre',
              lines: [
                state.system.runFrequency.isEmpty
                    ? 'Corre una vez al dia.'
                    : state.system.runFrequency,
                'Ventana permitida: ${schedule.windowLabel} (${schedule.timezone}).',
                'Dias permitidos: ${schedule.allowedDaysLabel}.',
                if (schedule.startDate != null)
                  'Fecha minima configurada: ${schedule.startDate}.',
              ],
            ),
            const SizedBox(height: 12),
            _ExplanationCard(
              title: '3. Que calcula',
              lines: [
                'Cuenta las cuotas vencidas de cada venta.',
                'Calcula capital pendiente, mora y total actualizado.',
                'La mora configurada del backend es 1% diario y se limita hasta 30 dias por cuota.',
                'La plantilla se ajusta segun la cantidad de cuotas visibles, hasta cinco lineas de detalle.',
              ],
            ),
            const SizedBox(height: 12),
            _ExplanationCard(
              title: '4. A donde envia',
              lines: [
                state.system.recipientPolicy,
                'ID del numero WhatsApp: ${state.system.whatsappPhoneNumberId.isEmpty ? 'no configurado' : state.system.whatsappPhoneNumberId}.',
                'ID de cuenta WhatsApp: ${state.system.whatsappBusinessAccountId.isEmpty ? 'no configurado' : state.system.whatsappBusinessAccountId}.',
                'Nunca se muestra ni se guarda aqui el token secreto de Meta.',
              ],
            ),
            const SizedBox(height: 12),
            _ExplanationCard(
              title: '5. Reintentos y duplicados',
              lines: [
                state.system.retryPolicy,
                state.system.duplicatePolicy,
                'Los estados de WhatsApp se actualizan con el webhook: enviado, entregado, leido o fallido.',
              ],
            ),
            const SizedBox(height: 12),
            _ExplanationCard(
              title: '6. Plantilla',
              lines: [
                'Plantilla activa: ${state.config.activeTemplateName.isEmpty ? 'no configurada' : state.config.activeTemplateName}.',
                'Plantilla de prueba: ${state.config.testTemplateName.isEmpty ? 'no configurada' : state.config.testTemplateName}.',
                'Idioma: ${state.config.templateLanguage.isEmpty ? 'no configurado' : state.config.templateLanguage}.',
                state.system.templatePolicy,
              ],
            ),
            const SizedBox(height: 12),
            _SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionLabel('Ejemplo visual'),
                  const SizedBox(height: 10),
                  Text(
                    state.template.preview,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: MobileUi.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExplanationCard extends StatelessWidget {
  const _ExplanationCard({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: MobileUi.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          for (final line in lines.where((line) => line.trim().isNotEmpty))
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '• ',
                    style: TextStyle(
                      color: MobileUi.textSecondary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      line,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.35,
                        color: MobileUi.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: mobileCardDecoration(),
      child: child,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(label.toUpperCase(), style: MobileUi.sectionTitle);
  }
}

class _RefreshStatusCard extends StatelessWidget {
  const _RefreshStatusCard();

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Row(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Actualizando datos de notificaciones...',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: MobileUi.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReminderRefreshFailedBanner extends StatelessWidget {
  const _ReminderRefreshFailedBanner({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFFF7E6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: Color(0xFF8A5A00),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B4A00)),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 30),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Reintentar', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

String _friendlyError(Object error, {bool saving = false}) {
  if (saving) {
    return 'No pudimos guardar el cambio. Intenta nuevamente.';
  }
  if (error is BackendApiException) {
    final statusCode = error.statusCode;
    if (statusCode == 401) {
      return 'La sesion expiro. Inicia sesion nuevamente.';
    }
    if (statusCode == 403) {
      return 'No tienes permiso para administrar los recordatorios.';
    }
    if (statusCode != null && statusCode >= 500) {
      return 'No pudimos cargar la configuracion de recordatorios.';
    }
  }
  final message = error.toString();
  if (message.contains('No hay una sesion online')) {
    return 'La sesion expiro. Inicia sesion nuevamente.';
  }
  if (message.contains('permiso') || message.contains('autorizado')) {
    return 'No tienes permiso para administrar los recordatorios.';
  }
  if (message.contains('No se pudo completar la solicitud HTTP') ||
      message.contains('SocketException') ||
      message.contains('Failed to fetch') ||
      message.contains('XMLHttpRequest')) {
    return 'No pudimos conectarnos al servicio de recordatorios.';
  }
  return 'No pudimos cargar la configuracion de recordatorios.';
}

String _readablePhone(String value) {
  final digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 11) {
    return '+${digits[0]} ${digits.substring(1, 4)} ${digits.substring(4, 7)} ${digits.substring(7)}';
  }
  return value;
}

String _formatMoney(String value) {
  final amount = double.tryParse(value);
  if (amount == null) {
    return value.isEmpty ? 'RD\$0.00' : value;
  }
  final fixed = amount.toStringAsFixed(2);
  final parts = fixed.split('.');
  final whole = parts.first;
  final buffer = StringBuffer();
  for (var i = 0; i < whole.length; i += 1) {
    final remaining = whole.length - i;
    buffer.write(whole[i]);
    if (remaining > 1 && remaining % 3 == 1) {
      buffer.write(',');
    }
  }
  return 'RD\$${buffer.toString()}.${parts.last}';
}

String _formatDateTime(DateTime value) {
  return '${_shortDate(value)} · ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

String _shortDate(DateTime value) {
  return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
}

String _statusLabel(String status) {
  switch (status) {
    case 'SENT':
      return 'Enviado';
    case 'DELIVERED':
      return 'Entregado';
    case 'READ':
      return 'Leido';
    case 'FAILED':
      return 'Fallo';
    case 'PARTIAL_FAILED':
      return 'Parcial';
    case 'DRY_RUN':
      return 'Prueba';
    case 'PENDING':
      return 'Pendiente';
    default:
      return status.isEmpty ? 'Pendiente' : status;
  }
}

Color _statusColor(String status) {
  switch (status) {
    case 'SENT':
    case 'DELIVERED':
    case 'READ':
      return MobileUi.success;
    case 'FAILED':
    case 'PARTIAL_FAILED':
      return MobileUi.danger;
    case 'DRY_RUN':
      return MobileUi.info;
    default:
      return MobileUi.textSecondary;
  }
}

IconData _historyIcon(String status) {
  switch (status) {
    case 'FAILED':
    case 'PARTIAL_FAILED':
      return Icons.error_outline_rounded;
    case 'SENT':
    case 'DELIVERED':
    case 'READ':
      return Icons.check_circle_outline_rounded;
    default:
      return Icons.schedule_rounded;
  }
}
