import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/system/system_config_service.dart';

/// Panel reusable que muestra el estado de la PC respecto al sistema:
/// si es la PC principal, si tiene permiso de escritura y permite refrescar
/// el estado o reclamar la PC como principal (solo administradores).
///
/// Se usa principalmente dentro de Configuración. Antes vivía como una fila
/// inline en el header global de la app.
class DeviceStatusPanel extends StatelessWidget {
  const DeviceStatusPanel({
    super.key,
    required this.onRefresh,
    required this.onCopyDeviceId,
  });

  /// Refresca el estado del dispositivo (sin reclamar primario).
  final Future<void> Function() onRefresh;

  /// Copia el ID de esta PC para pegarlo en el panel administrativo.
  final Future<void> Function() onCopyDeviceId;

  @override
  Widget build(BuildContext context) {
    final systemConfig = context.watch<SystemConfigService>();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4EAF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Estado de esta PC',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0D2640),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _DeviceStatusBadge(
                label: 'PC principal',
                value: systemConfig.isPrimaryDevice ? 'Sí' : 'No',
                highlighted: systemConfig.isPrimaryDevice,
              ),
              _DeviceStatusBadge(
                label: 'Permiso de escritura',
                value: systemConfig.canWrite ? 'Sí' : 'No',
                highlighted: systemConfig.canWrite,
                critical: !systemConfig.canWrite,
              ),
              _DeviceStatusBadge(
                label: 'ID de esta PC',
                value: systemConfig.currentDeviceId.isEmpty
                    ? 'No disponible'
                    : _compactId(systemConfig.currentDeviceId),
              ),
              TextButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.sync_rounded, size: 16),
                label: const Text('Actualizar estado'),
              ),
              FilledButton.tonalIcon(
                onPressed: onCopyDeviceId,
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Copiar ID de PC'),
              ),
            ],
          ),
          if (!systemConfig.canWrite &&
              systemConfig.deviceWriteReason.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              systemConfig.deviceWriteReason,
              style: const TextStyle(
                color: Color(0xFF8F2436),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Usa "Copiar ID de PC" y pegalo en el panel web para autorizar esta computadora.',
              style: TextStyle(
                color: Color(0xFF8F2436),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _compactId(String value) {
    final normalized = value.trim();
    if (normalized.length <= 12) {
      return normalized;
    }
    return '${normalized.substring(0, 6)}...${normalized.substring(normalized.length - 6)}';
  }
}

class _DeviceStatusBadge extends StatelessWidget {
  const _DeviceStatusBadge({
    required this.label,
    required this.value,
    this.highlighted = false,
    this.critical = false,
  });

  final String label;
  final String value;
  final bool highlighted;
  final bool critical;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = critical
        ? const Color(0xFFFDECEC)
        : highlighted
        ? const Color(0xFFEAF7EE)
        : const Color(0xFFF5F7FA);
    final borderColor = critical
        ? const Color(0xFFF2C6CC)
        : highlighted
        ? const Color(0xFFBEDFC8)
        : const Color(0xFFDCE3EA);
    final valueColor = critical
        ? const Color(0xFF8F2436)
        : highlighted
        ? const Color(0xFF246B3D)
        : const Color(0xFF415365);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF5C6C7D),
            fontWeight: FontWeight.w600,
          ),
          children: [
            TextSpan(text: '$label: '),
            TextSpan(
              text: value,
              style: TextStyle(color: valueColor, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}
