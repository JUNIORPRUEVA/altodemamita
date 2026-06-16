import 'dart:async';
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
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B2A45)),
        scaffoldBackgroundColor: const Color(0xFFF4F7FB),
        useMaterial3: true,
      ),
      home: const OwnerShell(),
    );
  }
}

class OwnerShell extends StatefulWidget {
  const OwnerShell({super.key});

  @override
  State<OwnerShell> createState() => _OwnerShellState();
}

class _OwnerShellState extends State<OwnerShell> {
  final ApiClient _api = const ApiClient(backendBaseUrl);
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  OwnerSnapshot? _snapshot;
  Object? _error;
  bool _loading = true;
  OwnerModule _selected = OwnerModule.dashboard;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _refresh(silent: true),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent) {
      setState(() => _loading = true);
    }
    try {
      final snapshot = await _api.fetchSnapshot();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(selected.title),
        leading: IconButton(
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          icon: const Icon(Icons.menu),
        ),
        actions: [
          IconButton(
            onPressed: () => _refresh(),
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
          ),
        ],
      ),
      drawer: OwnerDrawer(
        selected: selected,
        onSelected: (module) {
          Navigator.of(context).pop();
          setState(() => _selected = module);
        },
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _snapshot == null) {
      return ErrorView(error: _error.toString(), onRetry: () => _refresh());
    }
    final snapshot = _snapshot!;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null) ErrorBanner(error: _error.toString()),
          ModulePage(module: _selected, snapshot: snapshot),
        ],
      ),
    );
  }
}

enum OwnerModule {
  dashboard('Resumen', Icons.dashboard_outlined),
  clients('Clientes', Icons.people_alt_outlined),
  lots('Solares', Icons.map_outlined),
  sales('Ventas', Icons.point_of_sale_outlined),
  installments('Cuotas', Icons.event_note_outlined),
  payments('Pagos', Icons.payments_outlined),
  sellers('Vendedores', Icons.badge_outlined);

  const OwnerModule(this.title, this.icon);

  final String title;
  final IconData icon;
}

class OwnerDrawer extends StatelessWidget {
  const OwnerDrawer({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final OwnerModule selected;
  final ValueChanged<OwnerModule> onSelected;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              color: const Color(0xFF0B2A45),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white,
                    child: Icon(
                      Icons.real_estate_agent,
                      color: Color(0xFF0B2A45),
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Sistema Solares',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Owner App - solo lectura',
                    style: TextStyle(color: Color(0xFFC7D5E5)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                children: OwnerModule.values.map((module) {
                  return ListTile(
                    selected: selected == module,
                    leading: Icon(module.icon),
                    title: Text(module.title),
                    onTap: () => onSelected(module),
                  );
                }).toList(),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Los datos se actualizan automaticamente cada 10 segundos.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Color(0xFF667085)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ModulePage extends StatelessWidget {
  const ModulePage({super.key, required this.module, required this.snapshot});

  final OwnerModule module;
  final OwnerSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return switch (module) {
      OwnerModule.dashboard => DashboardPage(snapshot: snapshot),
      OwnerModule.clients => RecordsPage(
        title: 'Clientes',
        icon: module.icon,
        items: snapshot.clients,
        builder: RecordBuilders.client,
      ),
      OwnerModule.lots => RecordsPage(
        title: 'Solares',
        icon: module.icon,
        items: snapshot.lots,
        builder: RecordBuilders.lot,
      ),
      OwnerModule.sales => RecordsPage(
        title: 'Ventas',
        icon: module.icon,
        items: snapshot.sales,
        builder: RecordBuilders.sale,
      ),
      OwnerModule.installments => RecordsPage(
        title: 'Cuotas',
        icon: module.icon,
        items: snapshot.installments,
        builder: RecordBuilders.installment,
      ),
      OwnerModule.payments => RecordsPage(
        title: 'Pagos',
        icon: module.icon,
        items: snapshot.payments,
        builder: RecordBuilders.payment,
      ),
      OwnerModule.sellers => RecordsPage(
        title: 'Vendedores',
        icon: module.icon,
        items: snapshot.sellers,
        builder: RecordBuilders.seller,
      ),
    };
  }
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, required this.snapshot});

  final OwnerSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final counts = snapshot.dashboard['counts'] as Map<String, dynamic>? ?? {};
    final totals = snapshot.dashboard['totals'] as Map<String, dynamic>? ?? {};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader(
          title: 'Resumen general',
          subtitle: 'Vista rapida del negocio desde la nube.',
          icon: Icons.dashboard_outlined,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            MetricCard(
              label: 'Clientes',
              value: text(counts['clients'], '0'),
              icon: Icons.people_alt_outlined,
            ),
            MetricCard(
              label: 'Solares',
              value: text(counts['lots'], '0'),
              icon: Icons.map_outlined,
            ),
            MetricCard(
              label: 'Ventas',
              value: text(counts['sales'], '0'),
              icon: Icons.point_of_sale_outlined,
            ),
            MetricCard(
              label: 'Cuotas',
              value: text(counts['installments'], '0'),
              icon: Icons.event_note_outlined,
            ),
            MetricCard(
              label: 'Pagos',
              value: text(counts['payments'], '0'),
              icon: Icons.payments_outlined,
            ),
            MetricCard(
              label: 'Vendido',
              value: money(totals['sold']),
              icon: Icons.trending_up,
            ),
            MetricCard(
              label: 'Cobrado',
              value: money(totals['paid']),
              icon: Icons.account_balance_wallet_outlined,
            ),
            MetricCard(
              label: 'Balance',
              value: money(totals['balance']),
              icon: Icons.receipt_long_outlined,
            ),
          ],
        ),
      ],
    );
  }
}

class RecordsPage extends StatefulWidget {
  const RecordsPage({
    super.key,
    required this.title,
    required this.icon,
    required this.items,
    required this.builder,
  });

  final String title;
  final IconData icon;
  final List<Map<String, dynamic>> items;
  final RecordView Function(Map<String, dynamic>) builder;

  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final views = widget.items.map(widget.builder).where((view) {
      if (_query.trim().isEmpty) return true;
      return view.searchText.toLowerCase().contains(_query.toLowerCase());
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: widget.title,
          subtitle: '${views.length} registros visibles',
          icon: widget.icon,
        ),
        const SizedBox(height: 12),
        TextField(
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'Buscar en ${widget.title.toLowerCase()}...',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: 12),
        if (views.isEmpty)
          const EmptyCard()
        else
          ...views.map((view) => RecordCard(view: view)),
      ],
    );
  }
}

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: const Color(0xFFE7EEF7),
          child: Icon(icon, color: const Color(0xFF0B2A45)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(subtitle, style: const TextStyle(color: Color(0xFF667085))),
            ],
          ),
        ),
      ],
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 166,
      child: Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: const Color(0xFF0B2A45)),
              const SizedBox(height: 10),
              Text(label, style: const TextStyle(color: Color(0xFF667085))),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RecordCard extends StatelessWidget {
  const RecordCard({super.key, required this.view});

  final RecordView view;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    view.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (view.badge != null)
                  Chip(
                    label: Text(view.badge!),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              view.subtitle,
              style: const TextStyle(color: Color(0xFF667085)),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: view.fields.map((field) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F5F9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('${field.label}: ${field.value}'),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class EmptyCard extends StatelessWidget {
  const EmptyCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const Card(
      elevation: 0,
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('No hay datos para mostrar.')),
      ),
    );
  }
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFFFE9E7),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(error, style: const TextStyle(color: Color(0xFFB3261E))),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, required this.onRetry});

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

class RecordView {
  const RecordView({
    required this.title,
    required this.subtitle,
    required this.fields,
    required this.searchText,
    this.badge,
  });

  final String title;
  final String subtitle;
  final List<RecordField> fields;
  final String searchText;
  final String? badge;
}

class RecordField {
  const RecordField(this.label, this.value);

  final String label;
  final String value;
}

class RecordBuilders {
  static RecordView client(Map<String, dynamic> item) => RecordView(
    title: text(item['name'], 'Cliente sin nombre'),
    subtitle: 'Documento ${text(item['document'], '-')}',
    badge: text(item['phone'], '').isEmpty ? null : text(item['phone'], ''),
    fields: [
      RecordField('Telefono', text(item['phone'], '-')),
      RecordField('Direccion', text(item['address'], '-')),
      RecordField('Actualizado', dateText(item['updatedAt'])),
    ],
    searchText: item.toString(),
  );

  static RecordView seller(Map<String, dynamic> item) => RecordView(
    title: text(item['name'], 'Vendedor sin nombre'),
    subtitle: 'Documento ${text(item['document'], '-')}',
    fields: [
      RecordField('Telefono', text(item['phone'], '-')),
      RecordField('Activo', text(item['active'], '-')),
      RecordField('Actualizado', dateText(item['updatedAt'])),
    ],
    searchText: item.toString(),
  );

  static RecordView lot(Map<String, dynamic> item) => RecordView(
    title: 'Solar ${text(item['number'], '-')}',
    subtitle: 'Manzana ${text(item['block'], '-')}',
    badge: text(item['status'], '-'),
    fields: [
      RecordField('Area', money(item['area'])),
      RecordField('Precio/m2', money(item['price'])),
      RecordField('Actualizado', dateText(item['updatedAt'])),
    ],
    searchText: item.toString(),
  );

  static RecordView sale(Map<String, dynamic> item) => RecordView(
    title:
        'Venta ${text(item['syncId'], '').isEmpty ? '' : text(item['syncId'], '')}',
    subtitle: 'Estado ${text(item['status'], '-')}',
    badge: text(item['status'], '-'),
    fields: [
      RecordField('Total', money(item['total'])),
      RecordField('Inicial', money(item['initialPaid'])),
      RecordField('Balance', money(item['balance'])),
      RecordField('Fecha', dateText(item['saleDate'])),
    ],
    searchText: item.toString(),
  );

  static RecordView installment(Map<String, dynamic> item) => RecordView(
    title: 'Cuota ${text(item['installmentNumber'], '-')}',
    subtitle: 'Estado ${text(item['status'], '-')}',
    badge: text(item['status'], '-'),
    fields: [
      RecordField('Monto', money(item['totalAmount'])),
      RecordField('Pagado', money(item['paidAmount'])),
      RecordField('Balance final', money(item['endingBalance'])),
      RecordField('Vence', dateText(item['dueDate'])),
    ],
    searchText: item.toString(),
  );

  static RecordView payment(Map<String, dynamic> item) => RecordView(
    title: 'Pago ${money(item['amount'])}',
    subtitle: text(item['method'], 'Metodo no indicado'),
    badge: text(item['paymentType'], nullText),
    fields: [
      RecordField('Fecha', dateText(item['paidAt'])),
      RecordField('Referencia', text(item['reference'], '-')),
      RecordField('Ano', text(item['yearToPay'], '-')),
    ],
    searchText: item.toString(),
  );
}

const nullText = '-';

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
      clients: listOfMaps(results[1]['items']),
      sellers: listOfMaps(results[2]['items']),
      lots: listOfMaps(results[3]['items']),
      sales: listOfMaps(results[4]['items']),
      installments: listOfMaps(results[5]['items']),
      payments: listOfMaps(results[6]['items']),
    );
  }

  Future<Map<String, dynamic>> _list(String path) async {
    final body = await _get('$path?pageSize=200');
    return (body['data'] as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final uri = Uri.parse('$baseUrl$path');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
      final response = await request.close();
      final responseBody = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'HTTP ${response.statusCode}: $responseBody',
          uri: uri,
        );
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

List<Map<String, dynamic>> listOfMaps(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => item.cast<String, dynamic>())
      .toList(growable: false);
}

String text(Object? value, String fallback) {
  final resolved = value?.toString().trim() ?? '';
  return resolved.isEmpty ? fallback : resolved;
}

String dateText(Object? value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  if (parsed == null) return '-';
  return '${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.year}';
}

String money(Object? value) {
  final parsed = num.tryParse(value?.toString() ?? '');
  if (parsed == null) return 'RD\$0.00';
  return 'RD\$${parsed.toStringAsFixed(2)}';
}
