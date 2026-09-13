import 'package:flutter/widgets.dart';

/// Clasificación central de tamaños de ventana/pantalla.
///
/// Regla arquitectónica: NO usar números mágicos dispersos por el código.
/// Toda decisión responsive debe pasar por [AppBreakpoints].
enum AppWindowSize {
  /// Teléfonos muy pequeños (p. ej. 320 x 568).
  mobileCompact,

  /// Teléfonos estándar (360, 375, 390, 412, 430).
  mobile,

  /// Tabletas y ventanas estrechas (600 - 1023).
  tablet,

  /// Escritorio estándar: aquí vive el layout Windows actual (1024 - 1439).
  desktop,

  /// Monitores anchos (>= 1440).
  wideDesktop,
}

/// Puntos de corte (breakpoints) centralizados del sistema.
///
/// Los umbrales se eligieron a partir del layout Windows real de `app_local`:
/// el shell de escritorio usa una barra lateral de 96 px colapsada / 288 px
/// expandida, por lo que por debajo de 1024 px el layout de escritorio no
/// dispone de ancho útil suficiente para el contenido.
///
/// IMPORTANTE: ninguna pantalla de escritorio debe cambiar su
/// comportamiento. Estos umbrales sólo clasifican; el layout de escritorio
/// se sigue construyendo exactamente igual cuando la clasificación es
/// [AppWindowSize.desktop] o [AppWindowSize.wideDesktop].
class AppBreakpoints {
  const AppBreakpoints._();

  /// Ancho máximo exclusivo de [AppWindowSize.mobileCompact].
  static const double mobileCompactMax = 360;

  /// Ancho máximo exclusivo de [AppWindowSize.mobile].
  static const double mobileMax = 600;

  /// Ancho máximo exclusivo de [AppWindowSize.tablet].
  static const double tabletMax = 1024;

  /// Ancho máximo exclusivo de [AppWindowSize.desktop].
  static const double desktopMax = 1440;

  /// Ancho máximo cómodo para columnas de lectura/formulario en móvil y
  /// tableta. Evita formularios que ocupen todo el ancho en pantallas grandes.
  static const double readableContentMax = 720;

  /// Ancho máximo de contenido para páginas de escritorio centradas.
  static const double wideContentMax = 1440;

  /// Ancho máximo de un diálogo en escritorio.
  static const double dialogMax = 640;

  /// Alto mínimo recomendado para objetivos táctiles (Material).
  static const double minTouchTarget = 48;

  /// Clasifica un ancho lógico en [AppWindowSize].
  static AppWindowSize sizeFor(double width) {
    if (width < mobileCompactMax) return AppWindowSize.mobileCompact;
    if (width < mobileMax) return AppWindowSize.mobile;
    if (width < tabletMax) return AppWindowSize.tablet;
    if (width < desktopMax) return AppWindowSize.desktop;
    return AppWindowSize.wideDesktop;
  }

  /// Clasificación de la ventana actual.
  static AppWindowSize of(BuildContext context) =>
      sizeFor(MediaQuery.sizeOf(context).width);

  /// `true` para [AppWindowSize.mobileCompact] y [AppWindowSize.mobile].
  static bool isMobileWidth(double width) => width < mobileMax;

  /// `true` para [AppWindowSize.tablet].
  static bool isTabletWidth(double width) =>
      width >= mobileMax && width < tabletMax;

  /// `true` para [AppWindowSize.desktop] y [AppWindowSize.wideDesktop].
  ///
  /// Cuando esto es `true` el sistema debe renderizar el layout de
  /// escritorio existente sin cambios.
  static bool isDesktopWidth(double width) => width >= tabletMax;

  static bool isMobile(BuildContext context) =>
      isMobileWidth(MediaQuery.sizeOf(context).width);

  static bool isTablet(BuildContext context) =>
      isTabletWidth(MediaQuery.sizeOf(context).width);

  static bool isDesktop(BuildContext context) =>
      isDesktopWidth(MediaQuery.sizeOf(context).width);

  /// `true` si la ventana actual debe usar navegación compacta
  /// (barra inferior / drawer) en lugar del shell de escritorio.
  static bool usesCompactNavigation(BuildContext context) =>
      !isDesktop(context);
}
