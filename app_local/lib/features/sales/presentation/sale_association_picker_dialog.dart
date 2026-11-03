import 'package:flutter/material.dart';

import '../../../core/network/backend_entity_id_registry.dart';
import '../../clients/data/client_repository.dart';
import '../../lots/data/lot_repository.dart';

/// FASE 03B — Resultado de la selección de cliente o solar.
class SaleAssociationTarget {
  const SaleAssociationTarget({
    required this.remoteId,
    required this.label,
    required this.subtitle,
  });

  /// Identificador autoritativo (uuid) que espera el backend.
  final String remoteId;
  final String label;
  final String subtitle;
}

/// FASE 03B — Selector OWNER de cliente o solar.
///
/// Reutiliza los repositorios existentes del sistema (`ClientRepository` y
/// `LotRepository`) con su búsqueda y su normalización de texto (01B). Para
/// solares solo se listan los disponibles, y el backend vuelve a validar la
/// disponibilidad al aplicar la corrección.
class SaleAssociationPickerDialog extends StatefulWidget {
  const SaleAssociationPickerDialog({
    super.key,
    required this.isClient,
    required this.currentLabel,
    this.currentSubtitle,
  });

  final bool isClient;
  final String currentLabel;
  final String? currentSubtitle;

  @override
  State<SaleAssociationPickerDialog> createState() =>
      _SaleAssociationPickerDialogState();
}

class _SaleAssociationPickerDialogState
    extends State<SaleAssociationPickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  final ClientRepository _clientRepository = ClientRepository();
  final LotRepository _lotRepository = LotRepository();

  List<SaleAssociationTarget> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load(String query) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final targets = <SaleAssociationTarget>[];
      if (widget.isClient) {
        final clients = await _clientRepository.fetchAll(query: query);
        for (final client in clients) {
          // El backend resuelve el cliente por su id remoto (PK), igual que
          // hace con los solares. Enviar el syncId hacia fallar con
          // "El cliente seleccionado no existe en la empresa".
          final remoteId =
              (BackendEntityIdRegistry.instance.resolveRemoteId(
                    'clients',
                    client.id,
                  ) ??
                  client.syncId ??
                  '')
                  .trim();
          if (remoteId.isEmpty) continue;
          targets.add(
            SaleAssociationTarget(
              remoteId: remoteId,
              label: client.fullName,
              subtitle: [
                if (client.documentId.trim().isNotEmpty) client.documentId,
                if ((client.phone ?? '').trim().isNotEmpty) client.phone!,
              ].join(' · '),
            ),
          );
        }
        // La búsqueda (nombre, cédula, teléfono, dirección) la resuelve el
        // repositorio de clientes, ya usado por el módulo de Clientes.
      } else {
        final lots = await _lotRepository.fetchAvailable(query: query);
        for (final lot in lots) {
          final remoteId =
              BackendEntityIdRegistry.instance.resolveRemoteId(
                'products',
                lot.id,
              ) ??
              '';
          if (remoteId.isEmpty) continue;
          targets.add(
            SaleAssociationTarget(
              remoteId: remoteId,
              label: '${lot.blockNumber}-${lot.lotNumber}',
              subtitle:
                  '${lot.statusLabel} · ${lot.area.toStringAsFixed(2)} m²',
            ),
          );
        }
      }
      if (!mounted) return;
      setState(() {
        _items = targets;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudo cargar la lista: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isClient ? 'Cambiar cliente' : 'Cambiar solar';
    return AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 460,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Actual: ${widget.currentLabel}'
              '${(widget.currentSubtitle ?? '').trim().isEmpty ? '' : ' — ${widget.currentSubtitle}'}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _searchController,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                labelText: widget.isClient ? 'Buscar cliente' : 'Buscar solar',
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 16),
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) => _load(value),
            ),
            const SizedBox(height: 8),
            if (_error != null)
              Text(
                _error!,
                style: const TextStyle(fontSize: 11, color: Color(0xFFB91C1C)),
              ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : _items.isEmpty
                  ? const Center(
                      child: Text(
                        'Sin resultados disponibles.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF7C89A3)),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        return ListTile(
                          dense: true,
                          title: Text(
                            item.label,
                            style: const TextStyle(fontSize: 13),
                          ),
                          subtitle: item.subtitle.isEmpty
                              ? null
                              : Text(
                                  item.subtitle,
                                  style: const TextStyle(fontSize: 11),
                                ),
                          trailing: const Icon(Icons.chevron_right, size: 18),
                          onTap: () => Navigator.of(context).pop(item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}
