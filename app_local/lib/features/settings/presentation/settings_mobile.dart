import 'package:flutter/material.dart';

import '../../../shared/mobile/mobile_ui.dart';

/// Opción de la lista compacta de configuración.
class SettingsEntry {
  const SettingsEntry({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

/// Configuración en el layout compacto (PWA / mobile).
///
/// Reglas acordadas:
/// - Lista COMPACTA, sin una tarjeta por opción.
/// - Contenido alineado a la izquierda y con texto mínimo.
/// - Solo se muestran las opciones que aplican en mobile/PWA (fuera
///   Impresoras y Respaldo, que son herramientas de escritorio).
class SettingsMobileView extends StatelessWidget {
  const SettingsMobileView({super.key, required this.entries});

  final List<SettingsEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF5F6F8),
      child: ListView(
        padding: const EdgeInsets.only(top: 10, bottom: 24),
        children: [
          Container(
            color: MobileUi.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < entries.length; index++) ...[
                  _SettingsTile(entry: entries[index]),
                  if (index != entries.length - 1)
                    const Divider(
                      height: 1,
                      thickness: 1,
                      color: MobileUi.divider,
                      indent: 54,
                      endIndent: 16,
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({required this.entry});

  final SettingsEntry entry;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: entry.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
        child: Row(
          children: [
            Icon(entry.icon, size: 20, color: MobileUi.primary),
            const SizedBox(width: 18),
            Expanded(
              child: Text(
                entry.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: MobileUi.textPrimary,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: MobileUi.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
