import 'package:flutter/material.dart';

import '../../app/app_colors.dart';
import '../../app/safe_area_padding.dart';
import '../../widgets/animated_list_item.dart';

class DocumentationPage extends StatefulWidget {
  const DocumentationPage({super.key});

  @override
  State<DocumentationPage> createState() => _DocumentationPageState();
}

class _DocumentationPageState extends State<DocumentationPage> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  static const List<_GuideSection> _sections = [
    _GuideSection(
      title: 'Panel',
      icon: Icons.space_dashboard_outlined,
      summary:
          'Muestra el resumen general del negocio, métricas principales y accesos rápidos.',
      steps: [
        'Revise ventas, pagos, cuotas pendientes, solares y clientes desde las tarjetas principales.',
        'Use la lupa flotante para buscar cualquier cliente, venta, solar, vendedor, cuota o pago.',
        'Toque una métrica para abrir el módulo relacionado cuando esté disponible.',
        'Use actualizar para traer la información más reciente del servidor.',
      ],
      tips: [
        'La app abre con datos guardados localmente y luego actualiza en segundo plano.',
        'Si acaba de sincronizar desde appLocal, espere el refresco automático o toque actualizar.',
      ],
    ),
    _GuideSection(
      title: 'Ventas',
      icon: Icons.point_of_sale_outlined,
      summary:
          'Permite consultar ventas, balances, cliente, solar, vendedor, cuotas y pagos relacionados.',
      steps: [
        'Toque la lupa del topbar y escriba nombre, documento, solar, estado o monto.',
        'Use el filtro del topbar para ver ventas activas, pendientes, pagadas o vencidas.',
        'Abra una venta para ver resumen financiero, datos de operación, cliente, solar y vendedor.',
        'Entre a cuotas o pagos desde la venta usando las tarjetas con flecha.',
      ],
      tips: [
        'El monto pendiente corresponde al balance actual de la venta.',
        'Las referencias dentro del detalle permiten navegar y regresar al punto anterior.',
      ],
    ),
    _GuideSection(
      title: 'Clientes',
      icon: Icons.people_alt_outlined,
      summary:
          'Centraliza datos del cliente y sus relaciones con ventas y solares.',
      steps: [
        'Busque por nombre, cédula, teléfono, dirección o cualquier dato visible del registro.',
        'Use filtros para ver clientes con ventas, sin ventas o con deuda.',
        'Abra un cliente para ver sus datos principales sin información repetida.',
        'Use las tarjetas de referencia para ir a ventas o solares asociados.',
      ],
      tips: [
        'El nombre completo aparece en el topbar del detalle cuando corresponde.',
        'Si un texto es largo, toque el registro para verlo dentro del detalle.',
      ],
    ),
    _GuideSection(
      title: 'Solares',
      icon: Icons.map_outlined,
      summary: 'Muestra solares, manzanas, estado, precio y ventas asociadas.',
      steps: [
        'Busque por manzana, número de solar, estado o precio.',
        'Filtre por disponibles, vendidos o apartados.',
        'Abra un solar para ver sus datos y las referencias relacionadas.',
        'Desde una venta puede regresar al solar asignado usando la tarjeta de solar.',
      ],
      tips: [
        'El estado del solar ayuda a identificar disponibilidad o relación con ventas.',
        'Las ventas relacionadas aparecen cuando el solar tiene operación asociada.',
      ],
    ),
    _GuideSection(
      title: 'Vendedores',
      icon: Icons.badge_outlined,
      summary: 'Permite revisar vendedores, contactos y ventas asignadas.',
      steps: [
        'Busque por nombre, documento, teléfono o datos asociados.',
        'Use filtros para ver vendedores con ventas o sin ventas.',
        'Abra un vendedor para consultar sus datos y sus referencias.',
        'Desde una venta puede entrar al vendedor asignado en datos de operación.',
      ],
      tips: [
        'Las ventas asignadas dependen de que el registro venga sincronizado con sellerSyncId.',
        'Si falta una referencia, actualice la app después de sincronizar appLocal.',
      ],
    ),
    _GuideSection(
      title: 'Cuotas',
      icon: Icons.event_note_outlined,
      summary:
          'Lista cuotas del plan de pago, ordenadas de menor a mayor y con vencidas en rojo.',
      steps: [
        'Busque desde el topbar por número de cuota, cliente, solar, fecha o estado.',
        'Filtre por todas, pendientes, vencidas o pagadas.',
        'Las cuotas vencidas se muestran como Vencida y resaltadas en rojo.',
        'El campo Pendiente muestra lo que falta de esa cuota, no el balance completo de la venta.',
      ],
      tips: [
        'El orden natural es 1, 2, 3, 4 para facilitar revisión del plan.',
        'Una cuota puede marcarse vencida por estado o por fecha vencida si no está pagada.',
      ],
    ),
    _GuideSection(
      title: 'Pagos',
      icon: Icons.payments_outlined,
      summary:
          'Consulta pagos realizados, método, referencia, fecha y relación con venta o solar.',
      steps: [
        'Busque por referencia, método, cliente, solar o fecha.',
        'Los pagos se ordenan cronológicamente para revisar el historial completo.',
        'Abra pagos desde una venta para ver solo los pagos de esa operación.',
        'Compare el total pagado con el balance restante en el resumen de la venta.',
      ],
      tips: [
        'Si un pago fue creado en appLocal, debe sincronizarse primero al backend.',
        'Después de sincronizar, appOwner lo verá en el próximo refresco silencioso.',
      ],
    ),
    _GuideSection(
      title: 'Búsqueda global',
      icon: Icons.manage_search_outlined,
      summary: 'Encuentra datos cruzados sin saber en qué módulo están.',
      steps: [
        'Desde Panel, toque la lupa flotante.',
        'Escriba nombre, cédula, teléfono, solar, vendedor o referencia.',
        'Abra el resultado para ver datos globales del cliente, venta, solar, vendedor, cuotas y pagos.',
        'Use las flechas de cada sección para entrar al detalle relacionado.',
      ],
      tips: [
        'La búsqueda global usa todos los datos cargados en el snapshot actual.',
        'Si no aparece algo recién creado, actualice después de que appLocal sincronice.',
      ],
    ),
    _GuideSection(
      title: 'Sincronización',
      icon: Icons.sync_rounded,
      summary:
          'Explica cómo appOwner recibe datos creados o editados desde appLocal.',
      steps: [
        'appLocal guarda cambios localmente y los sube al backend mediante su cola de sincronización.',
        'appOwner lee el backend y actualiza sus módulos en segundo plano.',
        'Al abrir appOwner, primero muestra cache local para entrar rápido.',
        'Luego descarga el snapshot actualizado y reemplaza los datos en pantalla.',
      ],
      tips: [
        'La cache no reemplaza al backend: solo acelera la entrada a la app.',
        'Si no hay internet, se mostrará la última información guardada.',
        'Al volver a abrir la app desde segundo plano, se ejecuta un refresco silencioso.',
      ],
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<_GuideSection> get _filteredSections {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _sections;
    return _sections
        .where((section) {
          final haystack = [
            section.title,
            section.summary,
            ...section.steps,
            ...section.tips,
          ].join(' ').toLowerCase();
          return haystack.contains(query);
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final sections = _filteredSections;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SearchBox(
            controller: _controller,
            onChanged: (value) => setState(() => _query = value),
            onClear: () {
              _controller.clear();
              setState(() => _query = '');
            },
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(
                top: 12,
                bottom: mobileSafeBottomPadding(context) + 16,
              ),
              itemCount: sections.isEmpty ? 2 : sections.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(left: 2, bottom: 8),
                    child: Text(
                      '${sections.length} ${sections.length == 1 ? 'tema' : 'temas'}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }

                if (sections.isEmpty) {
                  return const _EmptyGuideState();
                }

                final itemIndex = index - 1;
                return AnimatedListItem(
                  index: itemIndex,
                  child: _GuideCard(section: sections[itemIndex]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Buscar en la documentación...',
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: AppColors.textSecondary,
          size: 20,
        ),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded, size: 18),
                color: AppColors.textSecondary,
              ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
        ),
      ),
    );
  }
}

class _GuideCard extends StatelessWidget {
  const _GuideCard({required this.section});

  final _GuideSection section;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(top: 6),
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(section.icon, color: AppColors.primary, size: 20),
          ),
          title: Text(
            section.title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              section.summary,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.4,
                fontWeight: FontWeight.w500,
                height: 1.25,
              ),
            ),
          ),
          children: [
            _GuideBlock(title: 'Cómo usarlo', items: section.steps),
            const SizedBox(height: 8),
            _GuideBlock(title: 'Notas importantes', items: section.tips),
          ],
        ),
      ),
    );
  }
}

class _GuideBlock extends StatelessWidget {
  const _GuideBlock({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 5,
                  height: 5,
                  margin: const EdgeInsets.only(top: 7),
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.4,
                      height: 1.32,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyGuideState extends StatelessWidget {
  const _EmptyGuideState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: const Text(
          'No encontramos una guía con ese criterio.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _GuideSection {
  const _GuideSection({
    required this.title,
    required this.icon,
    required this.summary,
    required this.steps,
    required this.tips,
  });

  final String title;
  final IconData icon;
  final String summary;
  final List<String> steps;
  final List<String> tips;
}
