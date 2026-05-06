import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/system/system_config_service.dart';
import '../../features/auth/presentation/auth_provider.dart';

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
    required this.onClaimPrimary,
  });

  /// Refresca el estado del dispositivo (sin reclamar primario).
  final Future<void> Function() onRefresh;

  /// Solicita a la nube convertir esta PC en la PC principal con permiso de
  /// escritura. Es una operación delicada: el caller normalmente debe pedir
  /// confirmación + contraseña antes de invocarlo.
  final Future<void> Function() onClaimPrimary;

  @override
  Widget build(BuildContext context) {
    final systemConfig = context.watch<SystemConfigService>();
    final auth = context.watch<AuthProvider>();
    final canClaimPrimary =
        auth.currentUser?.isAdmin == true && !systemConfig.canWrite;

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
              TextButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.sync_rounded, size: 16),
                label: const Text('Actualizar estado'),
              ),
              if (canClaimPrimary)
                FilledButton.tonalIcon(
                  onPressed: onClaimPrimary,
                  icon: const Icon(Icons.computer_rounded, size: 16),
                  label: const Text('Reclamar esta PC'),
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
          ],
        ],
      ),
    );
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
