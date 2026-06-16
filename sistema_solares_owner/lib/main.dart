import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

const String backendBaseUrl =
    'https://altodemanita-altodemamita-backent.onqyr1.easypanel.host';

void main() {
  runApp(const OwnerApp());
}

class OwnerApp extends StatelessWidget {
  const OwnerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Sistema Solares Owner',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF12304F)),
        useMaterial3: true,
      ),
      home: const OwnerHomePage(),
    );
  }
}

class OwnerHomePage extends StatefulWidget {
  const OwnerHomePage({super.key});

  @override
  State<OwnerHomePage> createState() => _OwnerHomePageState();
}

class _OwnerHomePageState extends State<OwnerHomePage> {
  final ApiClient _api = ApiClient(backendBaseUrl);
  late Future<OwnerSnapshot> _snapshotFuture;

  @override
  void initState() {
    super.initState();
    _snapshotFuture = _api.fetchSnapshot();
  }

  void _refresh() {
    setState(() {
      _snapshotFuture = _api.fetchSnapshot();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        title: const Text('Sistema Solares Owner'),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: FutureBuilder<OwnerSnapshot>(
        future: _snapshotFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorView(error: snapshot.error.toString(), onRetry: _refresh);
          }
          final data = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _DashboardCard(snapshot: data),
                const SizedBox(height: 16),
                _Section(title: 'Solares', items: data.lots, itemBuilder: _lotTile),
                _Section(title: 'Clientes', items: data.clients, itemBuilder: _clientTile),
                _Section(title: 'Vendedores', items: data.sellers, itemBuilder: _sellerTile),
                _Section(title: 'Ventas', items: data.sales, itemBuilder: _saleTile),
                _Section(title: 'Cuotas', items: data.installments, itemBuilder: _installmentTile),
                _Section(title: 'Pagos', items: data.payments, itemBuilder: _paymentTile),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _clientTile(Map<String, dynamic> item) {
    return _DataTile(
      title: text(item['name'], 'Cliente sin nombre'),
      subtitle: 'Doc: ${text(item['document'], '-')}  Tel: ${text(item['phone'], '-')}',
    );
  }

  Widget _sellerTile(Map<String, dynamic> item) {
    return _DataTile(
      title: text(item['name'], 'Vendedor sin nombre'),
      subtitle: 'Doc: ${text(item['document'], '-')}  Tel: ${text(item['phone'], '-')}',
    );
  }

  Widget _lotTile(Map<String, dynamic> item) {
    return _DataTile(
      title: 'Solar ${text(item['number'], '-')}',
      subtitle:
          'Manzana ${text(item['block'], '-')}  Estado: ${text(item['status'], '-')}  Area: ${money(item['area'])}',
    );
  }

  Widget _saleTile(Map<String, dynamic> item) {
    return _DataTile(
      title: 'Venta ${text(item['status'], '-')}',
      subtitle:
          'Total: ${money(item['total'])}  Balance: ${money(item['balance'])}',
    );
  }

  Widget _installmentTile(Map<String, dynamic> item) {
    return _DataTile(
      title: 'Cuota ${text(item['installmentNumber'], '-')}',
      subtitle:
          'Monto: ${money(item['totalAmount'])}  Pagado: ${money(item['paidAmount'])}  Estado: ${text(item['status'], '-')}',
    );
  }

  Widget _paymentTile(Map<String, dynamic> item) {
    return _DataTile(
      title: 'Pago ${money(item['amount'])}',
      subtitle:
          '${text(item['method'], 'Metodo no indicado')}  ${text(item['paidAt'], '')}',
    );
  }
}

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({required this.snapshot});

  final OwnerSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final counts = snapshot.dashboard['counts'] as Map<String, dynamic>? ?? {};
    final totals = snapshot.dashboard['totals'] as Map<String, dynamic>? ?? {};
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Resumen',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _Metric(label: 'Clientes', value: text(counts['clients'], '0')),
                _Metric(label: 'Solares', value: text(counts['lots'], '0')),
                _Metric(label: 'Ventas', value: text(counts['sales'], '0')),
                _Metric(label: 'Cuotas', value: text(counts['installments'], '0')),
                _Metric(label: 'Pagos', value: text(counts['payments'], '0')),
                _Metric(label: 'Cobrado', value: money(totals['paid'])),
                _Metric(label: 'Balance', value: money(totals['balance'])),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF1FA),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF65748B))),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.items,
    required this.itemBuilder,
  });

  final String title;
  final List<Map<String, dynamic>> items;
  final Widget Function(Map<String, dynamic>) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      child: ExpansionTile(
        initiallyExpanded: title == 'Solares' || title == 'Pagos',
        title: Text('$title (${items.length})'),
        children: items.isEmpty
            ? const [
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Sin datos todavia.'),
                ),
              ]
            : items.take(100).map(itemBuilder).toList(),
      ),
    );
  }
}

class _DataTile extends StatelessWidget {
  const _DataTile({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 54, color: Color(0xFFB3261E)),
            const SizedBox(height: 12),
            const Text(
              'No se pudo cargar la nube',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}

class OwnerSnapshot {
  const OwnerSnapshot({
    required this.dashboard,
    required this.clients,
    required this.sellers,
    required this.lots,
    required this.sales,
    required this.installments,
    required this.payments,
  });

  final Map<String, dynamic> dashboard;
  final List<Map<String, dynamic>> clients;
  final List<Map<String, dynamic>> sellers;
  final List<Map<String, dynamic>> lots;
  final List<Map<String, dynamic>> sales;
  final List<Map<String, dynamic>> installments;
  final List<Map<String, dynamic>> payments;
}

class ApiClient {
  const ApiClient(this.baseUrl);

  final String baseUrl;

  Future<OwnerSnapshot> fetchSnapshot() async {
    final results = await Future.wait([
      _get('/owner/dashboard'),
      _list('/owner/clients'),
      _list('/owner/sellers'),
      _list('/owner/lots'),
      _list('/owner/sales'),
      _list('/owner/installments'),
      _list('/owner/payments'),
    ]);
    return OwnerSnapshot(
      dashboard: (results[0]['data'] as Map).cast<String, dynamic>(),
      clients: (results[1]['items'] as List).cast<Map<String, dynamic>>(),
      sellers: (results[2]['items'] as List).cast<Map<String, dynamic>>(),
      lots: (results[3]['items'] as List).cast<Map<String, dynamic>>(),
      sales: (results[4]['items'] as List).cast<Map<String, dynamic>>(),
      installments: (results[5]['items'] as List).cast<Map<String, dynamic>>(),
      payments: (results[6]['items'] as List).cast<Map<String, dynamic>>(),
    );
  }

  Future<Map<String, dynamic>> _list(String path) async {
    final body = await _get('$path?pageSize=100');
    return (body['data'] as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final uri = Uri.parse('$baseUrl$path');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
      final response = await request.close();
      final responseBody = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}: $responseBody', uri: uri);
      }
      final decoded = jsonDecode(responseBody);
      if (decoded is! Map) {
        throw const FormatException('Respuesta invalida del backend.');
      }
      return decoded.cast<String, dynamic>();
    } finally {
      client.close(force: true);
    }
  }
}

String text(Object? value, String fallback) {
  final resolved = value?.toString().trim() ?? '';
  return resolved.isEmpty ? fallback : resolved;
}

String money(Object? value) {
  final parsed = num.tryParse(value?.toString() ?? '');
  if (parsed == null) return 'RD\$0.00';
  return 'RD\$${parsed.toStringAsFixed(2)}';
}
