import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_breakpoints.dart';

/// Padding de página dependiente del tamaño de pantalla.
///
/// En escritorio conserva el valor actual del sistema (16 px). En móvil usa
/// un valor ligeramente menor para aprovechar el ancho y respeta el safe area.
class ResponsivePagePadding extends StatelessWidget {
  const ResponsivePagePadding({
    super.key,
    required this.child,
    this.desktopPadding = 16,
    this.mobilePadding = 12,
    this.applySafeArea = true,
  });

  final Widget child;
  final double desktopPadding;
  final double mobilePadding;
  final bool applySafeArea;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final double value = AppBreakpoints.isDesktopWidth(width)
        ? desktopPadding
        : mobilePadding;

    final padded = Padding(
      padding: EdgeInsets.all(value),
      child: child,
    );

    if (!applySafeArea) {
      return padded;
    }

    return SafeArea(
      top: false,
      bottom: false,
      child: padded,
    );
  }
}

/// Contenedor de formulario adaptativo.
///
/// - Móvil: ancho completo (no comprime formularios de escritorio).
/// - Tableta / escritorio: limita el ancho para mantener legibilidad.
///
/// Debe usarse DENTRO del `SingleChildScrollView` de cada formulario.
class ResponsiveFormContainer extends StatelessWidget {
  const ResponsiveFormContainer({
    super.key,
    required this.child,
    this.maxWidth = AppBreakpoints.readableContentMax,
    this.centerOnWide = true,
  });

  final Widget child;
  final double maxWidth;
  final bool centerOnWide;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    if (AppBreakpoints.isMobileWidth(width)) {
      // Todo el ancho útil disponible: evita formularios comprimidos.
      return SizedBox(width: double.infinity, child: child);
    }

    if (!centerOnWide) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      );
    }

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// Cuadrícula de tarjetas que decide el número de columnas por ancho real.
///
/// Sustituye a filas de métricas fijas que se desbordan en pantallas
/// pequeñas. En móvil siempre usa una columna legible.
class ResponsiveCardGrid extends StatelessWidget {
  const ResponsiveCardGrid({
    super.key,
    required this.children,
    this.mobileColumns = 1,
    this.tabletColumns = 2,
    this.desktopColumns = 3,
    this.spacing = 12,
    this.minItemWidth = 220,
  });

  final List<Widget> children;
  final int mobileColumns;
  final int tabletColumns;
  final int desktopColumns;
  final double spacing;
  final double minItemWidth;

  int _columnsFor(BuildContext context, double width) {
    final byBreakpoint = switch (AppBreakpoints.sizeFor(width)) {
      AppWindowSize.mobileCompact || AppWindowSize.mobile => mobileColumns,
      AppWindowSize.tablet => tabletColumns,
      AppWindowSize.desktop || AppWindowSize.wideDesktop => desktopColumns,
    };

    // Nunca más columnas de las que caben con un ancho mínimo usable.
    final maxByWidth = math.max(1, (width / minItemWidth).floor());

    return math.max(1, math.min(byBreakpoint, maxByWidth));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _columnsFor(context, constraints.maxWidth);

        if (columns <= 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(height: spacing),
                children[i],
              ],
            ],
          );
        }

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children)
              SizedBox(
                width: (constraints.maxWidth - spacing * (columns - 1)) /
                    columns,
                child: child,
              ),
          ],
        );
      },
    );
  }
}
