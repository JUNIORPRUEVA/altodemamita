import 'package:flutter/material.dart';

import '../../../shared/widgets/base_layout.dart';

class DocumentationPage extends StatefulWidget {
  const DocumentationPage({super.key});

  @override
  State<DocumentationPage> createState() => _DocumentationPageState();
}

class _DocumentationPageState extends State<DocumentationPage> {
  static const List<String> _quickQueries = [
    'instalacion',
    'ventas',
    'pagos',
    'backup',
    'usuarios',
    'impresoras',
    'recibo',
    'cuotas',
  ];

  late final TextEditingController _searchController;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sections = _documentationSections;
    final visibleSections = sections
        .map((section) => section.filter(_query))
        .where((section) => section.entries.isNotEmpty)
        .toList(growable: false);
    final totalEntries = sections.fold<int>(
      0,
      (total, section) => total + section.entries.length,
    );
    final visibleEntries = visibleSections.fold<int>(
      0,
      (total, section) => total + section.entries.length,
    );

    return BaseLayout(
      title: 'Documentacion',
      showPageTitle: false,
      appBarToolbarHeight: 42,
      centerTitle: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 1120;

          return SelectionArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _CompactHeaderBar(
                    totalSections: sections.length,
                    totalEntries: totalEntries,
                    visibleEntries: visibleEntries,
                    query: _query,
                  ),
                  const SizedBox(height: 10),
                  _buildSearchCard(context),
                  const SizedBox(height: 12),
                  if (compact) ...[
                    _buildSidebar(context, sections, visibleSections),
                    const SizedBox(height: 12),
                    _buildContent(context, visibleSections),
                  ] else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 318,
                          child: _buildSidebar(
                            context,
                            sections,
                            visibleSections,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildContent(context, visibleSections),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearchCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText:
                    'Buscar: ventas, pagos, backup, impresoras, instalacion',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.trim().isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpiar busqueda',
                        onPressed: _clearSearch,
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
              onChanged: (value) {
                setState(() {
                  _query = value;
                });
              },
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final query in _quickQueries)
                  ActionChip(
                    label: Text(query),
                    avatar: const Icon(Icons.north_east_rounded, size: 16),
                    onPressed: () => _applyQuickQuery(query),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar(
    BuildContext context,
    List<_DocSection> allSections,
    List<_DocSection> visibleSections,
  ) {
    final totalTopics = allSections.fold<int>(
      0,
      (total, section) => total + section.entries.length,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cobertura del manual',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                _StatLine(
                  label: 'Secciones documentadas',
                  value: '${allSections.length}',
                ),
                _StatLine(label: 'Temas operativos', value: '$totalTopics'),
                _StatLine(
                  label: 'Resultado actual',
                  value: '${visibleSections.length} secciones',
                ),
                const SizedBox(height: 10),
                Text(
                  'Incluye uso diario, configuracion, respaldo, instalacion, especificaciones y lineamientos para despliegue.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF667085),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF4E8),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.verified_user_outlined,
                        color: Color(0xFFAA5B12),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Uso en otro equipo',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Este sistema esta previsto para un solo equipo de trabajo. Si se necesita instalar en otra PC o dispositivo, se debe contactar al desarrollador para solicitar una instalacion adicional autorizada.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF7A4A14),
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Indice de secciones',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                for (final section in allSections) ...[
                  _SectionIndexTile(
                    section: section,
                    onTap: () => _applyQuickQuery(section.title),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context, List<_DocSection> sections) {
    if (sections.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 34),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF1FB),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(
                  Icons.search_off_rounded,
                  color: Color(0xFF315E92),
                  size: 34,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'No se encontraron coincidencias en el manual.',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Prueba con terminos como ventas, cuotas, backup, impresoras, recibo o instalacion.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF667085),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final section in sections) ...[
          _DocumentationSectionCard(section: section),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  void _applyQuickQuery(String value) {
    _searchController
      ..text = value
      ..selection = TextSelection.collapsed(offset: value.length);
    setState(() {
      _query = value;
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _query = '';
    });
  }
}

class _CompactHeaderBar extends StatelessWidget {
  const _CompactHeaderBar({
    required this.totalSections,
    required this.totalEntries,
    required this.visibleEntries,
    required this.query,
  });

  final int totalSections;
  final int totalEntries;
  final int visibleEntries;
  final String query;

  @override
  Widget build(BuildContext context) {
    final hasQuery = query.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF102C47), Color(0xFF1B4F72), Color(0xFF2B6B4A)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A102C47),
            blurRadius: 28,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Manual operativo',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _HeroMetric(label: 'Sec', value: '$totalSections'),
                    _HeroMetric(label: 'Temas', value: '$totalEntries'),
                    _HeroMetric(
                      label: hasQuery ? 'Match' : 'Estado',
                      value: hasQuery ? '$visibleEntries' : 'Activo',
                    ),
                  ],
                ),
              ],
            );
          }

          return Row(
            children: [
              const Expanded(
                child: Text(
                  'Manual operativo del sistema',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _HeroMetric(label: 'Sec', value: '$totalSections'),
              const SizedBox(width: 8),
              _HeroMetric(label: 'Temas', value: '$totalEntries'),
              const SizedBox(width: 8),
              _HeroMetric(
                label: hasQuery ? 'Match' : 'Estado',
                value: hasQuery ? '$visibleEntries' : 'Activo',
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.70),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentationSectionCard extends StatelessWidget {
  const _DocumentationSectionCard({required this.section});

  final _DocSection section;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: section.accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(section.icon, color: section.accentColor),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        section.title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        section.summary,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF667085),
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F7FB),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${section.entries.length} temas',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF44536A),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (final entry in section.entries) ...[
              _DocumentationEntryCard(
                entry: entry,
                accentColor: section.accentColor,
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _DocumentationEntryCard extends StatelessWidget {
  const _DocumentationEntryCard({
    required this.entry,
    required this.accentColor,
  });

  final _DocEntry entry;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFDFDFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8ECF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entry.title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            entry.summary,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              height: 1.55,
              color: const Color(0xFF344054),
            ),
          ),
          if (entry.steps.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Como usar esta parte',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: accentColor,
              ),
            ),
            const SizedBox(height: 10),
            for (var index = 0; index < entry.steps.length; index++) ...[
              _StepTile(
                index: index + 1,
                text: entry.steps[index],
                accentColor: accentColor,
              ),
              const SizedBox(height: 8),
            ],
          ],
          if (entry.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final note in entry.notes) ...[
              _NoteTile(text: note),
              const SizedBox(height: 8),
            ],
          ],
          if (entry.keywords.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final keyword in entry.keywords)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      keyword,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: accentColor,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.index,
    required this.text,
    required this.accentColor,
  });

  final int index;
  final String text;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$index',
            style: TextStyle(color: accentColor, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF475467),
                height: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5EAF2)),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: const Color(0xFF4B5565),
          height: 1.5,
        ),
      ),
    );
  }
}

class _SectionIndexTile extends StatelessWidget {
  const _SectionIndexTile({required this.section, required this.onTap});

  final _DocSection section;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE7ECF3)),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: section.accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(section.icon, size: 18, color: section.accentColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                section.title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF243241),
                ),
              ),
            ),
            Text(
              '${section.entries.length}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF667085),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatLine extends StatelessWidget {
  const _StatLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: const Color(0xFF667085)),
            ),
          ),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _DocSection {
  const _DocSection({
    required this.id,
    required this.title,
    required this.summary,
    required this.icon,
    required this.accentColor,
    required this.entries,
  });

  final String id;
  final String title;
  final String summary;
  final IconData icon;
  final Color accentColor;
  final List<_DocEntry> entries;

  _DocSection filter(String query) {
    final normalizedQuery = _normalize(query);
    if (normalizedQuery.isEmpty) {
      return this;
    }

    final sectionText = _normalize('$title $summary $id');
    if (sectionText.contains(normalizedQuery)) {
      return this;
    }

    final filteredEntries = entries
        .where((entry) => entry.matches(normalizedQuery))
        .toList(growable: false);

    return _DocSection(
      id: id,
      title: title,
      summary: summary,
      icon: icon,
      accentColor: accentColor,
      entries: filteredEntries,
    );
  }
}

class _DocEntry {
  const _DocEntry({
    required this.title,
    required this.summary,
    required this.steps,
    required this.notes,
    required this.keywords,
  });

  final String title;
  final String summary;
  final List<String> steps;
  final List<String> notes;
  final List<String> keywords;

  bool matches(String normalizedQuery) {
    final combined = _normalize(
      [title, summary, ...steps, ...notes, ...keywords].join(' '),
    );
    return combined.contains(normalizedQuery);
  }
}

String _normalize(String value) {
  return value
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ñ', 'n');
}

const List<_DocSection> _documentationSections = [
  _DocSection(
    id: 'acceso',
    title: 'Acceso e inicio de sesion',
    summary:
        'Explica como entrar al sistema, como interpretar los permisos y como moverse por la interfaz principal.',
    icon: Icons.lock_open_rounded,
    accentColor: Color(0xFF1E4F8A),
    entries: [
      _DocEntry(
        title: 'Ingreso al sistema',
        summary:
            'La pantalla de inicio solicita correo electronico y contrasena. Solo despues de autenticarse el usuario accede a los modulos autorizados dentro del sistema.',
        steps: [
          'Escribe el correo del usuario en el campo Correo electronico.',
          'Escribe la contrasena y pulsa Iniciar sesion.',
          'Si el acceso es correcto, el sistema abre el panel principal o el primer modulo habilitado para ese usuario.',
        ],
        notes: [
          'Si el usuario no tiene permisos de lectura sobre modulos, el sistema muestra un aviso de acceso insuficiente y no permite operar hasta que un administrador habilite los permisos.',
          'La autenticacion controla que cada usuario solo vea los modulos asignados en su perfil.',
        ],
        keywords: ['login', 'correo', 'contrasena', 'sesion', 'acceso'],
      ),
      _DocEntry(
        title: 'Navegacion principal',
        summary:
            'La app muestra una barra lateral con los modulos principales y un area central donde se carga la pantalla seleccionada. En movil se usa un menu lateral desplegable.',
        steps: [
          'Usa la barra lateral para cambiar entre Resumen, Ventas, Buscador, Clientes, Solares, Pagos, Cuotas, Vendedores y Configuracion.',
          'Observa el encabezado superior para confirmar en que modulo estas trabajando.',
          'Usa el boton de perfil para ver informacion de usuario y el boton de cerrar sesion al final de la jornada.',
        ],
        notes: [
          'El sistema adapta la navegacion a escritorio o pantalla reducida sin cambiar las funciones del modulo.',
        ],
        keywords: [
          'menu',
          'modulos',
          'barra lateral',
          'perfil',
          'cerrar sesion',
        ],
      ),
    ],
  ),
  _DocSection(
    id: 'dashboard',
    title: 'Resumen ejecutivo',
    summary:
        'Presenta indicadores globales del negocio para seguimiento rapido de clientes, solares, cobros y financiamiento.',
    icon: Icons.space_dashboard_rounded,
    accentColor: Color(0xFF16324F),
    entries: [
      _DocEntry(
        title: 'Panel principal de indicadores',
        summary:
            'La pantalla Resumen concentra metricas como total de clientes, solares, solares vendidos, pagos pendientes, iniciales incompletos y saldos por cobrar.',
        steps: [
          'Abre el modulo Resumen desde el menu lateral.',
          'Revisa las tarjetas superiores para conocer el estado general del portafolio.',
          'Usa los paneles ejecutivos para priorizar la gestion de cobro, disponibilidad de inventario y seguimiento financiero.',
        ],
        notes: [
          'Este modulo sirve para supervision y control diario. No reemplaza la operacion detallada de Ventas, Cuotas o Pagos.',
          'Los indicadores cambian automaticamente segun los datos guardados en clientes, solares, ventas y cuotas.',
        ],
        keywords: [
          'resumen',
          'dashboard',
          'indicadores',
          'metricas',
          'panel principal',
        ],
      ),
    ],
  ),
  _DocSection(
    id: 'clientes',
    title: 'Modulo de clientes',
    summary:
        'Gestiona el padron de clientes y su informacion base para ventas, cobros, recibos y reportes.',
    icon: Icons.people_alt_outlined,
    accentColor: Color(0xFF245A76),
    entries: [
      _DocEntry(
        title: 'Registrar un cliente nuevo',
        summary:
            'El formulario de cliente solicita nombre, cedula, telefono y direccion. Estos datos se reutilizan en ventas, pagos y documentos.',
        steps: [
          'Entra a Clientes y pulsa Nuevo cliente.',
          'Completa nombre, cedula dominicana, telefono y direccion.',
          'Pulsa Crear cliente para dejarlo disponible en futuras ventas.',
        ],
        notes: [
          'El sistema valida nombre, cedula, telefono y direccion antes de guardar.',
          'Si un dato no cumple formato, el formulario mostrara una advertencia y no dejara guardar hasta corregirlo.',
        ],
        keywords: [
          'cliente',
          'cedula',
          'telefono',
          'direccion',
          'crear cliente',
        ],
      ),
      _DocEntry(
        title: 'Consultar y mantener clientes',
        summary:
            'La pantalla de clientes permite buscar, editar y revisar rapidamente el registro de cada persona vinculada al negocio.',
        steps: [
          'Usa el buscador superior para localizar clientes por nombre, cedula u otra referencia disponible.',
          'Selecciona la accion de editar cuando necesites actualizar informacion.',
          'Mantén los datos correctos porque ventas, pagos y recibos dependen de esta ficha.',
        ],
        notes: [
          'Los permisos del usuario determinan si puede crear, editar o eliminar registros dentro de este modulo.',
        ],
        keywords: [
          'buscar cliente',
          'editar cliente',
          'mantenimiento',
          'padron',
        ],
      ),
    ],
  ),
  _DocSection(
    id: 'solares',
    title: 'Modulo de solares',
    summary:
      'Controla el inventario de solares disponibles, vendidos o reservados con sus dimensiones, precio por metro y precio total calculado.',
    icon: Icons.map_outlined,
    accentColor: Color(0xFF2E6A4B),
    entries: [
      _DocEntry(
        title: 'Crear y editar solares',
        summary:
            'Cada solar se registra con manzana, numero, area, precio por metro y estado. El precio total se calcula automaticamente y sirve de base para ventas.',
        steps: [
          'Abre el modulo Solares y pulsa Nuevo solar.',
          'Indica manzana, numero, metros cuadrados, precio por metro y estado.',
          'Guarda el registro para que quede disponible dentro del inventario.',
        ],
        notes: [
          'El codigo de presentacion del solar se usa luego dentro de ventas, cuotas y recibos.',
          'Los valores negativos no son aceptados en area ni precio por metro.',
        ],
        keywords: ['solar', 'manzana', 'numero', 'inventario', 'precio por metro'],
      ),
      _DocEntry(
        title: 'Estados del solar y disponibilidad',
        summary:
            'El estado del solar ayuda a saber si se puede vender de inmediato o si ya esta comprometido dentro del negocio.',
        steps: [
          'Revisa el listado para identificar solares disponibles, vendidos u otros estados configurados.',
          'Antes de registrar una venta, confirma que el solar este disponible.',
          'Actualiza el estado cuando la operacion comercial cambie.',
        ],
        notes: [
          'Durante el proceso de venta, el sistema utiliza el inventario disponible para evitar asignar un solar incorrecto.',
        ],
        keywords: ['estado solar', 'disponible', 'vendido', 'inventario'],
      ),
    ],
  ),
  _DocSection(
    id: 'ventas',
    title: 'Modulo de ventas y vendedores',
    summary:
        'Administra la venta del solar, la seleccion de cliente, el vendedor, el inicial, el financiamiento y los documentos PDF.',
    icon: Icons.point_of_sale_outlined,
    accentColor: Color(0xFF7A3E8E),
    entries: [
      _DocEntry(
        title: 'Crear una venta nueva',
        summary:
          'El asistente de venta permite elegir cliente, vendedor y solar, usar el precio total calculado del solar, definir porcentaje de inicial, monto pagado, tasa mensual y numero de cuotas.',
        steps: [
          'Entra a Ventas y pulsa Nueva venta.',
          'Busca o crea el cliente desde el mismo formulario si tienes permiso.',
          'Busca o crea el solar y el vendedor segun corresponda.',
          'Completa fecha, revisa el precio total calculado, porcentaje de inicial, monto inicial pagado, interes y plan de cuotas.',
          'Guarda la venta para que el sistema calcule el saldo y prepare el cronograma financiero.',
        ],
        notes: [
          'El formulario permite crear clientes, solares y vendedores sin salir del proceso de venta cuando el usuario tiene permisos.',
          'La venta utiliza parametros financieros por defecto, pero estos pueden ajustarse durante el registro si el flujo lo requiere.',
        ],
        keywords: ['nueva venta', 'inicial', 'interes', 'cuotas', 'vendedor'],
      ),
      _DocEntry(
        title: 'Consulta, edicion y detalle de ventas',
        summary:
            'La lista de ventas incluye buscador, estado comercial y un dialogo de detalle con resumen financiero, informacion del cliente, solar y cuotas.',
        steps: [
          'Usa el buscador de Ventas para localizar operaciones por cliente, cedula, solar o estado.',
          'Abre el detalle de la venta para revisar precio total, saldo pendiente, inicial pagado y cronograma asociado.',
          'Edita o elimina solo cuando tu rol y las reglas del sistema lo permitan.',
        ],
        notes: [
          'La edicion o eliminacion de una venta puede restringirse cuando ya existen pagos registrados.',
          'El detalle de venta sirve como punto de validacion antes de emitir documentos o registrar pagos.',
        ],
        keywords: [
          'detalle de venta',
          'editar venta',
          'estado de venta',
          'saldo pendiente',
        ],
      ),
      _DocEntry(
        title: 'Documentos de la venta',
        summary:
            'Desde cada venta se pueden generar documentos PDF como recibo inicial y tabla de amortizacion para impresion o revision.',
        steps: [
          'Abre la venta deseada y entra a la opcion de documentos.',
          'Selecciona el tipo de documento que necesitas generar.',
          'Previsualiza, imprime o comparte el PDF segun el flujo operativo del negocio.',
        ],
        notes: [
          'La informacion de empresa e impresora configurada impacta directamente en la salida documental.',
          'La tabla de amortizacion resume las cuotas proyectadas y el recibo inicial respalda el primer cobro de la operacion.',
        ],
        keywords: [
          'pdf',
          'recibo inicial',
          'tabla de amortizacion',
          'documentos',
        ],
      ),
      _DocEntry(
        title: 'Gestion de vendedores',
        summary:
            'El sistema incluye mantenimiento de vendedores para relacionarlos con las operaciones comerciales y sus consultas posteriores.',
        steps: [
          'Abre el modulo Vendedores desde el menu lateral.',
          'Crea o edita el registro comercial con nombre, cedula y telefono.',
          'Usa la lista y la busqueda para mantener la cartera de vendedores actualizada.',
        ],
        notes: [
          'Los vendedores pueden abrirse tambien desde el formulario de ventas para acelerar el registro si el permiso esta habilitado.',
        ],
        keywords: [
          'vendedores',
          'comercial',
          'cedula vendedor',
          'buscar vendedor',
        ],
      ),
    ],
  ),
  _DocSection(
    id: 'cuotas',
    title: 'Modulo de cuotas',
    summary:
        'Permite revisar el cronograma de amortizacion, estados de pago, cuotas vencidas y resumen financiero por venta.',
    icon: Icons.event_note_outlined,
    accentColor: Color(0xFF8C5A12),
    entries: [
      _DocEntry(
        title: 'Seguimiento de amortizacion',
        summary:
            'La pantalla Cuotas muestra la lista de cuotas por venta o de forma general, incluyendo monto, saldo y estado calculado.',
        steps: [
          'Abre Cuotas para ver todas las cuotas del sistema o las de una venta especifica cuando vienes desde otro modulo.',
          'Usa el buscador para localizar una cuota por cliente, solar o referencia visible.',
          'Consulta la franja resumen para revisar total financiado, total pagado y total pendiente.',
        ],
        notes: [
          'Si una venta todavia no completa el inicial, puede que aun no existan cuotas activas para esa operacion.',
        ],
        keywords: ['cuotas', 'amortizacion', 'saldo', 'vencida', 'pagada'],
      ),
      _DocEntry(
        title: 'Interpretacion de estados',
        summary:
            'El estado de cada cuota permite al operador saber si la obligacion esta pendiente, vencida o ya fue saldada.',
        steps: [
          'Revisa la tabla y prioriza las cuotas vencidas para gestion de cobro.',
          'Usa el estado para distinguir rapidamente compromisos al dia de compromisos atrasados.',
          'Coordina el modulo de Cuotas con Pagos para confirmar el efecto de cada cobro sobre el plan de financiamiento.',
        ],
        notes: [
          'El resumen por venta ayuda a supervisores y caja a conocer de inmediato el comportamiento de la cartera financiada.',
        ],
        keywords: ['estado cuota', 'pendiente', 'vencida', 'seguimiento'],
      ),
    ],
  ),
  _DocSection(
    id: 'pagos',
    title: 'Modulo de pagos, recibos y pagares',
    summary:
        'Gestiona el cobro del inicial, pagos a cuotas, abonos a capital, historial de cobros y emision documental.',
    icon: Icons.payments_outlined,
    accentColor: Color(0xFF0E6B4C),
    entries: [
      _DocEntry(
        title: 'Registrar un pago',
        summary:
            'El formulario de pago solicita monto, fecha y metodo. El sistema decide si el dinero se aplica al inicial pendiente, a la cuota exigible o directamente a capital.',
        steps: [
          'Abre Pagos y localiza la venta con el buscador principal del modulo.',
          'Pulsa Registrar pago sobre la venta seleccionada.',
          'Indica el monto, la fecha y el metodo de cobro.',
          'Confirma la operacion para que el sistema actualice saldo, historial y datos documentales.',
        ],
        notes: [
          'Si el financiamiento no esta activo, el pago se registra como apartado o abono al inicial.',
          'Si no existe una cuota exigible, el sistema puede aplicar el pago directamente a capital segun el contexto de la venta.',
        ],
        keywords: [
          'registrar pago',
          'abono',
          'capital',
          'metodo de pago',
          'cobro',
        ],
      ),
      _DocEntry(
        title: 'Filtros, historial y seleccion de venta',
        summary:
            'La pantalla de pagos permite buscar ventas activas, filtrar el historial y consultar el contexto financiero de cada caso.',
        steps: [
          'Busca la venta por cliente, solar o referencia comercial.',
          'Aplica filtros cuando necesites revisar historial por fecha, orden o estado.',
          'Verifica el contexto de la venta antes de registrar un nuevo cobro.',
        ],
        notes: [
          'El modulo se apoya en la venta seleccionada para mostrar historial, cuota accionable y saldo pendiente.',
        ],
        keywords: ['historial de pagos', 'filtros', 'venta activa', 'contexto'],
      ),
      _DocEntry(
        title: 'Recibos y pagares',
        summary:
            'Cada cobro puede derivar en la generacion de un recibo PDF, y el sistema tambien puede producir el pagare del cliente cuando el proceso operativo lo requiera.',
        steps: [
          'Despues del pago, genera o revisa el recibo correspondiente.',
          'Usa la opcion documental adecuada para imprimir o compartir el comprobante.',
          'Genera el pagare del cliente cuando necesites soporte formal del compromiso de pago.',
        ],
        notes: [
          'Los documentos toman datos de la empresa configurada y del historial real de la venta.',
          'Verifica impresora predeterminada y datos corporativos antes de emitir documentos finales.',
        ],
        keywords: ['recibo', 'pagare', 'pdf', 'imprimir', 'comprobante'],
      ),
    ],
  ),
  _DocSection(
    id: 'busqueda',
    title: 'Buscador global',
    summary:
        'Sirve para localizar clientes, solares, ventas y accesos operativos desde una sola pantalla.',
    icon: Icons.search_rounded,
    accentColor: Color(0xFF3D5A80),
    entries: [
      _DocEntry(
        title: 'Como usar la busqueda global',
        summary:
            'La busqueda global admite texto como nombre del cliente, cedula, telefono o numero de solar y devuelve resultados navegables.',
        steps: [
          'Abre Buscador desde el menu lateral.',
          'Escribe el termino de interes y pulsa Buscar.',
          'Selecciona el resultado adecuado para saltar al modulo correspondiente.',
        ],
        notes: [
          'Este modulo es ideal para reducir tiempos de consulta cuando ya conoces un dato clave del cliente o de la operacion.',
        ],
        keywords: ['busqueda global', 'buscar', 'cliente', 'solar', 'venta'],
      ),
    ],
  ),
  _DocSection(
    id: 'configuracion',
    title: 'Configuracion del sistema',
    summary:
        'Reune parametros de empresa, usuarios, impresoras, valores financieros, respaldo y este mismo centro de documentacion.',
    icon: Icons.settings_outlined,
    accentColor: Color(0xFF4A5568),
    entries: [
      _DocEntry(
        title: 'Informacion de la empresa',
        summary:
            'Permite definir nombre de empresa, telefono, direccion y logo institucional para recibos y reportes.',
        steps: [
          'Entra a Configuracion y abre Empresa.',
          'Carga o cambia el logo corporativo si corresponde.',
          'Actualiza nombre, telefono y direccion y luego guarda los cambios.',
        ],
        notes: [
          'La informacion corporativa impacta en recibos, reportes y documentos PDF del sistema.',
          'Modificar esta seccion puede requerir autorizacion administrativa.',
        ],
        keywords: [
          'empresa',
          'logo',
          'telefono',
          'direccion',
          'datos corporativos',
        ],
      ),
      _DocEntry(
        title: 'Impresoras',
        summary:
            'La pantalla de impresoras administra los equipos configurados para salida documental y define la impresora predeterminada.',
        steps: [
          'Abre la seccion Impresoras dentro de Configuracion.',
          'Registra nombre, modelo y tipo del equipo.',
          'Marca la impresora predeterminada para simplificar la emision de documentos.',
        ],
        notes: [
          'La impresora por defecto se utiliza como referencia en flujos de recibos y documentos de venta.',
        ],
        keywords: [
          'impresora',
          'predeterminada',
          'modelo',
          'configuracion de impresion',
        ],
      ),
      _DocEntry(
        title: 'Usuarios y permisos',
        summary:
            'Permite crear usuarios, cambiar su estado y asignar niveles de acceso a modulos y acciones del sistema.',
        steps: [
          'Entra a Usuarios desde Configuracion.',
          'Crea o edita usuarios con nombre, correo, telefono, rol y estado.',
          'Asigna permisos segun el nivel operativo que la persona necesita dentro del sistema.',
        ],
        notes: [
          'La visibilidad de modulos y acciones depende de estos permisos.',
          'El control de acceso es critico para proteger configuraciones sensibles y operaciones administrativas.',
        ],
        keywords: ['usuarios', 'permisos', 'rol', 'admin', 'operador'],
      ),
      _DocEntry(
        title: 'Parametros financieros',
        summary:
            'Define valores por defecto como porcentaje de inicial, interes mensual, cantidad de cuotas y simbolo monetario.',
        steps: [
          'Abre Financiero dentro de Configuracion.',
          'Ajusta los valores base que se usaran al crear nuevas ventas.',
          'Guarda los cambios y valida con el equipo responsable antes de aplicarlos en operacion diaria.',
        ],
        notes: [
          'Cambiar esta seccion afecta la experiencia de nuevas ventas y debe hacerse con control administrativo.',
        ],
        keywords: ['financiero', 'inicial', 'interes', 'cuotas', 'moneda'],
      ),
      _DocEntry(
        title: 'Respaldo y recuperacion',
        summary:
            'La seccion de respaldo muestra estado del sistema de copias, ruta activa, historial, destino sugerido y controles de recuperacion.',
        steps: [
          'Abre Respaldo desde Configuracion para revisar el estado actual.',
          'Confirma la ruta activa de backup y la fecha del ultimo respaldo.',
          'Usa copias manuales o restauracion solo con autorizacion y procedimiento controlado.',
        ],
        notes: [
          'El sistema prioriza respaldos en una unidad secundaria cuando esta disponible.',
          'La recuperacion de una copia debe realizarse con criterio tecnico, especialmente en ambientes productivos.',
        ],
        keywords: [
          'backup',
          'respaldo',
          'restauracion',
          'ruta activa',
          'copia de seguridad',
        ],
      ),
      _DocEntry(
        title: 'Centro de documentacion',
        summary:
            'Esta misma pantalla consolida el manual del sistema para consulta rapida por parte de usuarios, supervisores y personal de soporte.',
        steps: [
          'Entra a Configuracion y pulsa Documentacion.',
          'Usa el buscador superior para encontrar temas concretos.',
          'Consulta la seccion adecuada antes de realizar una operacion poco frecuente o sensible.',
        ],
        notes: [
          'El manual esta dividido por secciones para facilitar lectura, capacitacion y soporte operativo.',
        ],
        keywords: ['documentacion', 'manual', 'ayuda', 'buscador interno'],
      ),
    ],
  ),
  _DocSection(
    id: 'instalacion',
    title: 'Instalacion y puesta en marcha',
    summary:
        'Describe como preparar el equipo, instalar el sistema, activar el entorno correcto y las restricciones de uso por dispositivo.',
    icon: Icons.download_done_outlined,
    accentColor: Color(0xFF0F766E),
    entries: [
      _DocEntry(
        title: 'Preparacion del equipo',
        summary:
            'Sistema Solares opera como aplicacion local de escritorio con base de datos SQLite y almacenamiento persistente en rutas del usuario de Windows.',
        steps: [
          'Confirma que el equipo use Windows de 64 bits y cuente con permisos normales de operacion.',
          'Verifica espacio disponible para base de datos, respaldos, archivos generados y registros del sistema.',
          'Si el flujo requiere documentos fisicos, confirma la disponibilidad de impresora.',
        ],
        notes: [
          'La base principal, la configuracion, los logs y la carpeta de respaldos viven en rutas persistentes fuera de la carpeta temporal de instalacion.',
        ],
        keywords: ['instalacion', 'windows', 'sqlite', 'equipo', 'preparacion'],
      ),
      _DocEntry(
        title: 'Instalacion en este equipo',
        summary:
            'La instalacion debe dejar el sistema listo para ejecutar, conservar sus datos y respetar la estructura persistente definida para produccion.',
        steps: [
          'Solicita al responsable tecnico la instalacion inicial o la actualizacion aprobada.',
          'Verifica al terminar que el sistema abra, permita iniciar sesion y muestre los modulos esperados.',
          'Comprueba que la ruta de respaldo este configurada y que los datos de empresa e impresora esten correctos antes de operar.',
        ],
        notes: [
          'Las operaciones de instalacion y actualizacion deben mantenerse controladas para no comprometer datos ni configuracion de produccion.',
        ],
        keywords: [
          'instalar',
          'actualizacion',
          'puesta en marcha',
          'configuracion inicial',
        ],
      ),
      _DocEntry(
        title: 'Instalacion en otra PC o dispositivo',
        summary:
            'Si se desea usar el sistema en otra computadora, no se debe copiar ni desplegar por cuenta propia. La gestion debe canalizarse con el desarrollador.',
        steps: [
          'No intentes replicar la instalacion de forma manual en otro equipo sin autorizacion.',
          'Contacta al desarrollador para solicitar una instalacion adicional o una nueva licencia por equipo.',
          'Coordina la configuracion de datos, backup y parametros antes de habilitar la nueva estacion de trabajo.',
        ],
        notes: [
          'Este sistema esta preparado para un solo equipo. Cualquier despliegue adicional debe ser solicitado formalmente.',
          'La razon es preservar control operativo, soporte, licenciamiento y consistencia de datos.',
        ],
        keywords: [
          'otra pc',
          'nuevo equipo',
          'licencia',
          'desarrollador',
          'instalacion adicional',
        ],
      ),
    ],
  ),
  _DocSection(
    id: 'especificaciones',
    title: 'Especificaciones del sistema',
    summary:
        'Resume la arquitectura funcional, almacenamiento persistente y requerimientos operativos recomendados para el entorno.',
    icon: Icons.dns_outlined,
    accentColor: Color(0xFF355070),
    entries: [
      _DocEntry(
        title: 'Arquitectura funcional',
        summary:
            'La aplicacion esta construida para escritorio con Flutter y usa SQLite como base de datos local. Organiza la operacion en modulos: resumen, clientes, solares, ventas, cuotas, pagos, buscador y configuracion.',
        steps: [
          'Considera la app como un sistema local orientado a una estacion de trabajo principal.',
          'Entiende que cada modulo se apoya en la misma base de datos persistente del equipo.',
          'Usa respaldo y configuracion para mantener continuidad operativa.',
        ],
        notes: [
          'El sistema separa base, configuracion, logs, archivos generados y respaldos en carpetas persistentes de Windows.',
        ],
        keywords: [
          'flutter',
          'sqlite',
          'arquitectura',
          'modulos',
          'sistema local',
        ],
      ),
      _DocEntry(
        title: 'Requisitos recomendados',
        summary:
            'Para una operacion estable se recomienda Windows 10 o 11 de 64 bits, 8 GB de RAM, disco SSD y espacio libre suficiente para crecimiento de datos y respaldos.',
        steps: [
          'Usa un equipo con rendimiento estable para evitar interrupciones en caja o registro de ventas.',
          'Reserva espacio adicional para respaldos historicos y documentos PDF.',
          'Conecta impresora y almacenamiento secundario cuando el proceso documental y de backup lo requiera.',
        ],
        notes: [
          'Como minimo se recomienda 4 GB de RAM, pero para operacion comoda el escenario preferido es 8 GB o mas.',
          'Se recomienda una resolucion de pantalla amplia para aprovechar mejor la interfaz de escritorio.',
        ],
        keywords: ['requisitos', 'ram', 'ssd', 'windows 10', 'windows 11'],
      ),
      _DocEntry(
        title: 'Lineamientos de seguridad operativa',
        summary:
            'La seguridad del sistema depende del control de usuarios, permisos, respaldo y disciplina operativa diaria.',
        steps: [
          'Trabaja siempre con usuarios identificados y permisos correctos.',
          'Verifica respaldos periodicos y la integridad de la ruta activa.',
          'No permitas cambios administrativos o despliegues tecnicos sin responsable autorizado.',
        ],
        notes: [
          'La continuidad del sistema no depende solo de la app, sino tambien de una operacion disciplinada y respaldos consistentes.',
        ],
        keywords: [
          'seguridad',
          'permisos',
          'respaldo',
          'operacion',
          'continuidad',
        ],
      ),
    ],
  ),
  _DocSection(
    id: 'soporte',
    title: 'Soporte y buenas practicas',
    summary:
        'Reune recomendaciones de uso diario para mantener consistencia de datos, documentos correctos y continuidad operativa.',
    icon: Icons.support_agent_outlined,
    accentColor: Color(0xFF6B7280),
    entries: [
      _DocEntry(
        title: 'Buenas practicas de operacion diaria',
        summary:
            'El sistema funciona mejor cuando clientes, solares, ventas y pagos se registran de forma ordenada y con verificaciones previas.',
        steps: [
          'Valida los datos del cliente antes de generar la venta.',
          'Confirma disponibilidad del solar y parametros financieros antes de guardar.',
          'Antes de imprimir o compartir documentos, revisa empresa, impresora y montos finales.',
        ],
        notes: [
          'Evita duplicar registros y mantén el uso del buscador para consultar antes de crear.',
        ],
        keywords: [
          'buenas practicas',
          'operacion diaria',
          'validacion',
          'control',
        ],
      ),
      _DocEntry(
        title: 'Cuando contactar soporte o desarrollo',
        summary:
            'Cualquier requerimiento de instalacion adicional, restauracion delicada, cambio tecnico mayor o despliegue a otro equipo debe escalarse al desarrollador.',
        steps: [
          'Escala problemas de instalacion, licenciamiento o despliegue a otra PC.',
          'Solicita apoyo tecnico si necesitas restaurar una copia de seguridad o revisar errores persistentes.',
          'Canaliza por soporte cualquier cambio estructural que afecte datos, permisos o impresiones.',
        ],
        notes: [
          'Este criterio protege la operacion y evita decisiones tecnicas improvisadas sobre ambientes productivos.',
        ],
        keywords: [
          'soporte',
          'desarrollador',
          'licencia',
          'restauracion',
          'incidente',
        ],
      ),
    ],
  ),
];
