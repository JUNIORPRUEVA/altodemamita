import 'dart:async';

import 'package:flutter/material.dart';

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

  PaymentReminderAdminState? _state;
  String? _error;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _repository = widget._repository ?? PaymentReminderSettingsRepository();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = await _repository.load();
      if (!mounted) return;
      setState(() {
        _state = state;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No pudimos cargar la informacion.';
        _loading = false;
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
    final current = _state;
    if (current == null || _saving) return;
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
    await _save(enabled: nextValue);
  }

  Future<void> _editPhone() async {
    final state = _state;
    if (state == null) return;
    final value = await showDialog<String>(
      context: context,
      builder: (context) =>
          _PhoneDialog(initialValue: state.config.senderWhatsAppNumber),
    );
    if (value == null) return;
    await _save(phone: value);
  }

  Future<void> _editMessage() async {
    final state = _state;
    if (state == null) return;
    final value = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => _MessageEditorPage(
          initialValue: state.config.editableMessageFragment,
          maxLength: state.config.maxMessageFragmentLength,
        ),
      ),
    );
    if (value == null) return;
    await _save(message: value);
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
            onPressed: _saving ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const _Skeleton()
            : _error != null && _state == null
            ? MobileSearchFailedView(
                title: 'No pudimos cargar la informacion.',
                onRetry: _load,
              )
            : RefreshIndicator(
                onRefresh: _load,
                child: _Content(
                  state: _state!,
                  saving: _saving,
                  error: _error,
                  onRetry: _load,
                  onToggle: _toggle,
                  onEditPhone: _editPhone,
                  onEditMessage: _editMessage,
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
    required this.error,
    required this.onRetry,
    required this.onToggle,
    required this.onEditPhone,
    required this.onEditMessage,
  });

  final PaymentReminderAdminState state;
  final bool saving;
  final String? error;
  final VoidCallback onRetry;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEditPhone;
  final VoidCallback onEditMessage;

  @override
  Widget build(BuildContext context) {
    final configured = state.system.whatsappConfigured;
    final enabled = state.config.notificationsEnabled;
    final effective = state.config.effectiveEnabled;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        if (error != null) ...[
          MobileRefreshFailedBanner(onRetry: onRetry),
          const SizedBox(height: 12),
        ],
        Text(
          'Mantén informados a tus clientes sobre sus cuotas y vencimientos.',
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
        _InfoActionCard(
          icon: Icons.chat_bubble_outline_rounded,
          title: 'WhatsApp de envio',
          value: configured
              ? _readablePhone(state.config.senderWhatsAppNumber)
              : 'Sin numero visible configurado',
          detail:
              'Numero mostrado para administracion. Los identificadores tecnicos del proveedor no se muestran aqui.',
          actionLabel: 'Editar numero',
          onTap: saving ? null : onEditPhone,
        ),
        const SizedBox(height: 12),
        _InfoActionCard(
          icon: Icons.sms_outlined,
          title: 'Mensaje al cliente',
          value: state.config.editableMessageFragment,
          detail: 'La plantilla oficial de Meta permanece bloqueada.',
          actionLabel: 'Configurar mensaje',
          onTap: saving ? null : onEditMessage,
        ),
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

class _InfoActionCard extends StatelessWidget {
  const _InfoActionCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.detail,
    required this.actionLabel,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final String detail;
  final String actionLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: MobileUi.primary),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: MobileUi.itemTitle)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value.isEmpty ? 'Sin configurar' : value,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: MobileUi.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(detail, style: MobileUi.itemSubtitle),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(onPressed: onTap, child: Text(actionLabel)),
          ),
        ],
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
    required this.initialValue,
    required this.maxLength,
  });

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
            const _SectionLabel('Vista previa'),
            const SizedBox(height: 8),
            _SectionCard(
              child: Text(
                'Hola Juan Perez.\n\n${text.isEmpty ? 'Te recordamos que tienes cuotas vencidas pendientes de pago.' : text}\n\nSolar: A-12\nCuotas vencidas: 2\nTotal vencido: RD\$15,000.00\nFecha de corte: 20 Sep 2026',
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: MobileUi.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Plantilla oficial bloqueada. Solo se guarda el texto personalizado.',
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

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: List.generate(
        5,
        (index) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            height: index == 0 ? 126 : 92,
            decoration: mobileCardDecoration(color: MobileUi.surface),
          ),
        ),
      ),
    );
  }
}

String _friendlyError(Object error) {
  final message = error.toString();
  if (message.contains('No hay una sesion online')) {
    return 'No hay una sesion cloud activa.';
  }
  if (message.contains('permiso') || message.contains('autorizado')) {
    return 'No tienes permiso para administrar recordatorios.';
  }
  return 'No pudimos guardar el cambio.';
}

String _readablePhone(String value) {
  final digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 11) {
    return '+${digits[0]} ${digits.substring(1, 4)} ${digits.substring(4, 7)} ${digits.substring(7)}';
  }
  return value;
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
