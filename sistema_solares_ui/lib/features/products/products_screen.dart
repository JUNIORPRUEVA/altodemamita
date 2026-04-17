import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:sistema_solares_ui/core/network/api_client.dart';
import 'package:sistema_solares_ui/core/realtime/realtime_controller.dart';
import 'package:sistema_solares_ui/features/products/products_service.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final _searchController = TextEditingController();
  Future<ProductsPage>? _future;
  int _lastTick = -1;
  bool _includeInactive = true;
  bool _includeDeleted = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() => _future = null);
  }

  @override
  Widget build(BuildContext context) {
    final refreshTick = context.watch<RealtimeController>().refreshTick;
    final currency = NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$ ');

    if (_future == null || refreshTick != _lastTick) {
      _lastTick = refreshTick;
      _future = ProductsService(context.read<ApiClient>()).fetch(
        search: _searchController.text,
        includeInactive: _includeInactive,
        includeDeleted: _includeDeleted,
      );
    }

    return FutureBuilder<ProductsPage>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text(snapshot.error.toString()));
        }

        final data = snapshot.data!;
        return ListView(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Solares y productos',
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Este modulo expone el catalogo sincronizado desde el backend para auditar que los registros realmente visibles no esten quedando ocultos por filtros de estado o borrado logico.',
                      style: TextStyle(color: Color(0xFF5F6570)),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 420,
                          child: TextField(
                            controller: _searchController,
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              labelText: 'Buscar por codigo, nombre o descripcion',
                            ),
                            onSubmitted: (_) => _reload(),
                          ),
                        ),
                        FilledButton(
                          onPressed: _reload,
                          child: const Text('Buscar'),
                        ),
                        FilterChip(
                          selected: _includeInactive,
                          label: const Text('Incluir inactivos'),
                          onSelected: (value) {
                            _includeInactive = value;
                            _reload();
                          },
                        ),
                        FilterChip(
                          selected: _includeDeleted,
                          label: const Text('Incluir eliminados'),
                          onSelected: (value) {
                            _includeDeleted = value;
                            _reload();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total visibles: ${data.total}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    if (data.items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'No hay productos para los filtros actuales.',
                          style: TextStyle(color: Color(0xFF5F6570)),
                        ),
                      )
                    else
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Codigo')),
                            DataColumn(label: Text('Nombre')),
                            DataColumn(label: Text('Precio contado')),
                            DataColumn(label: Text('Precio financiado')),
                            DataColumn(label: Text('Stock')),
                            DataColumn(label: Text('Estado')),
                          ],
                          rows: data.items
                              .map(
                                (item) => DataRow(
                                  cells: [
                                    DataCell(Text(item['code']?.toString() ?? '-')),
                                    DataCell(
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(maxWidth: 280),
                                        child: Text(item['name']?.toString() ?? '-'),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        currency.format(_readNum(item['price'])),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        currency.format(_readNum(item['financingPrice'])),
                                      ),
                                    ),
                                    DataCell(Text('${_readNum(item['stock']).toStringAsFixed(0)}')),
                                    DataCell(
                                      _StatusBadge(
                                        isActive: item['isActive'] == true,
                                        isDeleted: item['deletedAt'] != null,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                              .toList(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  double _readNum(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.isActive, required this.isDeleted});

  final bool isActive;
  final bool isDeleted;

  @override
  Widget build(BuildContext context) {
    late final Color background;
    late final String label;

    if (isDeleted) {
      background = const Color(0xFFD76C6C);
      label = 'Eliminado';
    } else if (isActive) {
      background = const Color(0xFF266A54);
      label = 'Activo';
    } else {
      background = const Color(0xFFC96F3B);
      label = 'Inactivo';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      ),
    );
  }
}