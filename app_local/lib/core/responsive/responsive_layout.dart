import 'package:flutter/widgets.dart';

import 'app_breakpoints.dart';

/// Selecciona una implementación distinta según el ancho disponible.
///
/// Patrón obligatorio para esta migración:
///
/// ```dart
/// ResponsiveLayout(
///   desktop: (_) => const ExistingDesktopScreen(), // NO se reconstruye
///   mobile: (_) => const MobileOptimizedScreen(),
/// )
/// ```
///
/// La rama [desktop] se usa para [AppWindowSize.desktop] y
/// [AppWindowSize.wideDesktop]. Es decir, en Windows el widget devuelto es
/// exactamente el mismo de siempre.
class ResponsiveLayout extends StatelessWidget {
  const ResponsiveLayout({
    super.key,
    required this.desktop,
    required this.mobile,
    this.tablet,
  });

  /// Implementación de escritorio existente (Windows). No modificar.
  final WidgetBuilder desktop;

  /// Implementación optimizada para teléfono.
  final WidgetBuilder mobile;

  /// Implementación opcional para tableta. Si es `null` se reutiliza
  /// [mobile], que a su vez debe adaptarse por ancho.
  final WidgetBuilder? tablet;

  @override
  Widget build(BuildContext context) {
    final size = AppBreakpoints.of(context);

    switch (size) {
      case AppWindowSize.desktop:
      case AppWindowSize.wideDesktop:
        return desktop(context);
      case AppWindowSize.tablet:
        return (tablet ?? mobile)(context);
      case AppWindowSize.mobile:
      case AppWindowSize.mobileCompact:
        return mobile(context);
    }
  }
}

/// Ejecuta [builder] recibiendo la clasificación actual de la ventana.
///
/// Útil cuando sólo una parte de la pantalla necesita adaptarse.
class ResponsiveBuilder extends StatelessWidget {
  const ResponsiveBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, AppWindowSize size) builder;

  @override
  Widget build(BuildContext context) =>
      builder(context, AppBreakpoints.of(context));
}

/// Limita el ancho del contenido y lo centra cuando hay espacio de sobra.
///
/// En móvil ocupa el 100% del ancho disponible. En escritorio/tableta evita
/// líneas de texto y formularios excesivamente anchos.
class ResponsiveContentBox extends StatelessWidget {
  const ResponsiveContentBox({
    super.key,
    required this.child,
    this.maxWidth = AppBreakpoints.readableContentMax,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final double maxWidth;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
