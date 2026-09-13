import 'package:flutter/material.dart';

import 'app_breakpoints.dart';

/// Presentación concreta usada por [showResponsiveDialog].
enum ResponsiveDialogMode {
  /// Diálogo centrado y limitado en ancho (comportamiento de escritorio).
  dialog,

  /// Hoja inferior desplazable (cómoda en móvil para listas/acciones).
  sheet,

  /// Pantalla completa respetando safe areas y el teclado (formularios).
  fullScreen,
}

/// Abre un diálogo adaptado al tamaño de pantalla.
///
/// - Escritorio (`>= 1024`): diálogo centrado limitado a
///   [AppBreakpoints.dialogMax]. Es el comportamiento actual de Windows.
/// - Móvil (`< 600`): pantalla completa o hoja inferior, respetando
///   `SafeArea` y el área del teclado (`viewInsets`).
/// - Tableta (600 - 1023): diálogo centrado más ancho.
///
/// Nunca permite que el contenido exceda el ancho, el alto, el safe area ni
/// el área del teclado de la ventana.
Future<T?> showResponsiveDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
  bool useRootNavigator = true,
  bool desktopScrollable = true,
  ResponsiveDialogMode? mobileMode,
  ResponsiveDialogMode? desktopMode,
}) {
  final width = MediaQuery.sizeOf(context).width;
  final isMobile = AppBreakpoints.isMobileWidth(width);

  final mode = isMobile
      ? (mobileMode ?? ResponsiveDialogMode.fullScreen)
      : (desktopMode ?? ResponsiveDialogMode.dialog);

  switch (mode) {
    case ResponsiveDialogMode.sheet:
      return showResponsiveSheet<T>(
        context: context,
        builder: builder,
        isDismissible: isDismissible,
        useRootNavigator: useRootNavigator,
      );
    case ResponsiveDialogMode.fullScreen:
    case ResponsiveDialogMode.dialog:
      return showDialog<T>(
        context: context,
        barrierDismissible: isDismissible,
        useRootNavigator: useRootNavigator,
        useSafeArea: false,
        builder: (dialogContext) => ResponsiveDialogFrame(
          mode: mode,
          scrollable: mode == ResponsiveDialogMode.dialog && desktopScrollable,
          child: builder,
        ),
      );
  }
}

/// Hoja inferior adaptada a safe areas y al teclado móvil.
Future<T?> showResponsiveSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
  bool useRootNavigator = true,
  bool expand = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isDismissible: isDismissible,
    enableDrag: isDismissible,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: useRootNavigator,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final viewInsets = MediaQuery.viewInsetsOf(sheetContext);
      final media = MediaQuery.of(sheetContext);
      final maxHeight = media.size.height - media.padding.top;

      return Padding(
        padding: EdgeInsets.only(bottom: viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: expand ? maxHeight : maxHeight * 0.85,
          ),
          child: Material(
            color: theme.colorScheme.surface,
            clipBehavior: Clip.antiAlias,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(20),
            ),
            child: SafeArea(top: false, child: builder(sheetContext)),
          ),
        ),
      );
    },
  );
}

/// Marco que garantiza que cualquier contenido de diálogo respeta los límites
/// de la ventana, el safe area y el teclado en todas las plataformas.
class ResponsiveDialogFrame extends StatelessWidget {
  const ResponsiveDialogFrame({
    super.key,
    required this.child,
    this.mode = ResponsiveDialogMode.dialog,
    this.scrollable = true,
    this.maxWidth = AppBreakpoints.dialogMax,
  });

  final WidgetBuilder child;
  final ResponsiveDialogMode mode;
  final bool scrollable;
  final double maxWidth;

  /// Clave de la caja real del diálogo centrado.
  ///
  /// El widget raíz de [ResponsiveDialogFrame] ocupa toda la ventana (para
  /// poder centrar), por lo que las pruebas y los diagnósticos deben medir
  /// esta clave para obtener el rectángulo efectivo del diálogo.
  static const Key surfaceKey = ValueKey<String>('responsive_dialog_surface');

  /// Clave del contenedor de pantalla completa.
  static const Key fullScreenKey =
      ValueKey<String>('responsive_dialog_fullscreen');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final viewInsets = media.viewInsets;

    final surface = Material(
      color: theme.colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      child: mode == ResponsiveDialogMode.fullScreen
          ? child(context)
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: scrollable
                      ? SingleChildScrollView(child: child(context))
                      : child(context),
                ),
              ],
            ),
    );

    if (mode == ResponsiveDialogMode.fullScreen) {
      return SizedBox.expand(
        key: fullScreenKey,
        child: Padding(
          // Deja visible el campo enfocado por encima del teclado.
          padding: EdgeInsets.only(bottom: viewInsets.bottom),
          child: SafeArea(
            child: Theme(
              data: theme.copyWith(
                dialogTheme: theme.dialogTheme,
                visualDensity: VisualDensity.standard,
              ),
              child: surface,
            ),
          ),
        ),
      );
    }

    // Diálogo centrado: nunca excede el ancho útil, el alto útil ni el teclado.
    final availableHeight =
        media.size.height - media.padding.vertical - viewInsets.vertical;
    final availableWidth = media.size.width - media.padding.horizontal;

    const double outerGap = 32;
    final double usableWidth = availableWidth - outerGap;
    final double usableHeight = availableHeight - outerGap;

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: media.padding.horizontal + 16,
          vertical: media.padding.vertical + 16,
        ),
        child: ConstrainedBox(
          key: surfaceKey,
          constraints: BoxConstraints(
            maxWidth: maxWidth < usableWidth ? maxWidth : usableWidth,
            maxHeight: usableHeight > 0 ? usableHeight : 0,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1F000000),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: surface,
          ),
        ),
      ),
    );
  }
}

/// Variante simple y reutilizable para confirmaciones de una sola acción.
///
/// Sustituye a los `AlertDialog` de escritorio cuando se invoca desde una
/// pantalla móvil.
Future<bool> showResponsiveConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = 'Confirmar',
  String cancelLabel = 'Cancelar',
  bool destructive = false,
}) async {
  final result = await showResponsiveDialog<bool>(
    context: context,
    desktopMode: ResponsiveDialogMode.dialog,
    mobileMode: ResponsiveDialogMode.sheet,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(cancelLabel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: destructive
                      ? FilledButton.styleFrom(
                          backgroundColor: theme.colorScheme.error,
                          foregroundColor: theme.colorScheme.onError,
                        )
                      : null,
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(confirmLabel),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );

  return result ?? false;
}
