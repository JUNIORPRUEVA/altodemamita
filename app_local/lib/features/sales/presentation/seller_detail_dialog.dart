import 'package:flutter/material.dart';

import '../../../core/resilience/friendly_error_messages.dart';
import '../data/sales_repository.dart';
import '../domain/sale_summary.dart';
import '../domain/seller.dart';
import 'sale_detail_dialog.dart';

class SellerDetailDialog extends StatefulWidget {
  const SellerDetailDialog({
    super.key,
    required this.seller,
    required this.salesRepository,
  });

  final Seller seller;
  final SalesRepository salesRepository;

  static Future<void> show(
    BuildContext context, {
    required Seller seller,
    required SalesRepository salesRepository,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => SellerDetailDialog(
        seller: seller,
        salesRepository: salesRepository,
      ),
    );
  }

  @override
  State<SellerDetailDialog> createState() => _SellerDetailDialogState();
}

class _SellerDetailDialogState extends State<SellerDetailDialog> {
  late Future<List<SaleSummary>> _salesFuture;

  @override
  void initState() {
    super.initState();
    _salesFuture = widget.salesRepository.fetchBySellerId(widget.seller.id!);
  }

  @override
  Widget build(BuildContext context) {
    final seller = widget.seller;

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SellerHeader(seller: seller),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<List<SaleSummary>>(
                future: _salesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    final message = FriendlyErrorMessages.forOperation(
                      'cargar las ventas del vendedor',
                      snapshot.error!,
                      module: 'ventas',
                      presentToUser: false,
                    );

                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF1F0),
                                  borderRadius: BorderRadius.circular(22),
                                ),
                                child: const Icon(
                                  Icons.error_outline,
                                  color: Color(0xFFB3261E),
                                  size: 34,
                                ),
                              ),
                              const SizedBox(height: 18),
                              const Text(
                                'No pudimos cargar el detalle del vendedor.',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1A2235),
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                message,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF6B7494),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  final sales = snapshot.data ?? const <SaleSummary>[];
                  final totalSold = sales.fold<double>(
                    0,
                    (total, sale) => total + sale.salePrice,
                  );

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _SellerStatChip(
                              label: 'Ventas realizadas',
                              value: '${sales.length}',
                              color: const Color(0xFF3B5BDB),
                            ),
                            _SellerStatChip(
                              label: 'Monto vendido',
                              value: _formatCurrency(totalSold),
                              color: const Color(0xFF2E7D32),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Ventas asociadas',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A2235),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (sales.isEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(22),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFD),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFFE4EAF2),
                              ),
                            ),
                            child: const Text(
                              'Este vendedor todavía no tiene ventas registradas.',
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF6B7494),
                              ),
                            ),
                          )
                        else
                          ...sales.map(
                            (sale) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _SellerSaleTile(
                                sale: sale,
                                onOpenSale: () => _openSaleDetail(sale.id),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSaleDetail(int saleId) async {
    try {
      final detail = await widget.salesRepository.fetchDetail(saleId);
      if (!mounted) {
        return;
      }

      if (detail == null) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('No se pudo encontrar el detalle de esta venta.'),
          ),
        );
        return;
      }

      await SaleDetailDialog.show(context, detail);
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            FriendlyErrorMessages.forOperation(
              'abrir el detalle de la venta',
              error,
              module: 'ventas',
            ),
          ),
        ),
      );
    }
  }

  String _formatCurrency(double value) {
    return 'RD\$ ${value.toStringAsFixed(2)}';
  }
}

class _SellerHeader extends StatelessWidget {
  const _SellerHeader({required this.seller});

  final Seller seller;

  @override
  Widget build(BuildContext context) {
    final initials = seller.name.isEmpty ? '?' : seller.name[0].toUpperCase();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 18, 20),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: const Color(0xFFE8EFF8),
            child: Text(
              initials,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E3A5F),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  seller.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A2235),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  seller.documentId,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6B7494),
                  ),
                ),
                if (seller.phone.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    seller.phone,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF6B7494),
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _SellerStatChip extends StatelessWidget {
  const _SellerStatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: color),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _SellerSaleTile extends StatelessWidget {
  const _SellerSaleTile({required this.sale, required this.onOpenSale});

  final SaleSummary sale;
  final VoidCallback onOpenSale;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4EAF2)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(
          'Venta #${sale.id} · ${sale.clientName}',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A2235),
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${sale.lotDisplayCode} · ${sale.clientDocumentId}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B7494)),
              ),
              const SizedBox(height: 4),
              Text(
                'Precio total RD\$ ${sale.salePrice.toStringAsFixed(2)} · Estado ${sale.status}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B7494)),
              ),
            ],
          ),
        ),
        trailing: IconButton(
          tooltip: 'Abrir venta',
          onPressed: onOpenSale,
          icon: const Icon(Icons.open_in_new_outlined),
        ),
      ),
    );
  }
}