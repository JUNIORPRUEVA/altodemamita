import 'dart:async';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app_incident_reporter.dart';
import '../system/system_config_service.dart';

class FriendlyErrorMessage {
  const FriendlyErrorMessage({
    required this.title,
    required this.message,
    required this.details,
    required this.suggestions,
  });

  final String title;
  final String message;
  final String details;
  final List<String> suggestions;

  FriendlyErrorMessage copyWith({
    String? title,
    String? message,
    String? details,
    List<String>? suggestions,
  }) {
    return FriendlyErrorMessage(
      title: title ?? this.title,
      message: message ?? this.message,
      details: details ?? this.details,
      suggestions: suggestions ?? this.suggestions,
    );
  }
}

class FriendlyErrorMessages {
  static FriendlyErrorMessage unexpected([Object? error]) {
    final raw = (error?.toString() ?? '').trim().toLowerCase();

    if (error is DeviceWriteBlockedException) {
      return FriendlyErrorMessage(
        title: 'PC no autorizada para cambios',
        message:
            'La escritura local esta habilitada. Si ves este mensaje, reinicia la app.',
        details: error.message,
        suggestions: const [
          'Abre Configuración y valida el estado de autorización de este equipo.',
          'Reinicia la app y vuelve a intentar.',
        ],
      );
    }

    if (isReadOnlyModeError(error)) {
      return const FriendlyErrorMessage(
        title: 'Sistema en modo solo lectura',
        message: 'Sistema en modo solo lectura',
        details:
            'Las acciones que modifican datos estan deshabilitadas temporalmente para proteger la informacion.',
        suggestions: [
          'Consulte informacion y reportes con normalidad.',
          'Intente nuevamente cuando el modo solo lectura sea desactivado.',
        ],
      );
    }

    if (error is SocketException || _looksLikeInternetIssue(raw)) {
      return const FriendlyErrorMessage(
        title: 'Sin conexion en este momento',
        message:
            'No hay conexion en este momento. Puedes seguir trabajando y la app sincronizara luego.',
        details:
            'La app sigue funcionando con datos locales mientras vuelve la conexion.',
        suggestions: [
          'Continua trabajando con normalidad.',
          'Intenta sincronizar nuevamente cuando regrese internet.',
        ],
      );
    }

    if (_looksLikeServerIssue(raw)) {
      return const FriendlyErrorMessage(
        title: 'No pudimos conectar con el servidor',
        message:
            'No pudimos conectar con el servidor. Revisa tu internet e intenta nuevamente.',
        details:
            'Puedes seguir trabajando localmente; la app intentará sincronizar nuevamente.',
        suggestions: [
          'Verifica tu conexión a internet.',
          'Intenta nuevamente en unos segundos.',
        ],
      );
    }

    if (_looksLikePermissionIssue(raw)) {
      return const FriendlyErrorMessage(
        title: 'Accion no permitida',
        message: 'No tienes permiso para realizar esta accion.',
        details:
            'La accion fue detenida para mantener la seguridad de tu cuenta.',
        suggestions: [
          'Contacta a un administrador si necesitas acceso.',
        ],
      );
    }

    if (_looksLikeValidationIssue(raw)) {
      return const FriendlyErrorMessage(
        title: 'Revisa los datos ingresados',
        message: 'Revisa los datos ingresados e intentalo nuevamente.',
        details:
            'Algunos campos no cumplen el formato esperado y no se pudo completar la accion.',
        suggestions: [
          'Corrige los campos marcados e intenta otra vez.',
        ],
      );
    }

    if (error is DatabaseException) {
      return const FriendlyErrorMessage(
        title: 'No pudimos guardar la informacion local',
        message:
            'Hubo un problema guardando la informacion local. Cierra y abre la app si continua.',
        details:
            'La app detuvo la accion para proteger los datos y evitar cambios incompletos.',
        suggestions: [
          'Intente nuevamente.',
          'Si el problema continua, reinicia la app.',
        ],
      );
    }

    if (error is FileSystemException) {
      return const FriendlyErrorMessage(
        title: 'No se pudo acceder a un archivo necesario',
        message:
            'El sistema no pudo leer o guardar un archivo interno en este momento.',
        details:
            'La operacion se detuvo antes de dejar informacion a medias. Revise el espacio disponible y vuelva a intentarlo.',
        suggestions: [
          'Revise que la computadora tenga espacio disponible.',
          'Intente nuevamente en unos segundos.',
        ],
      );
    }

    if (error is TimeoutException) {
      return const FriendlyErrorMessage(
        title: 'La operacion tomo mas tiempo de lo esperado',
        message:
            'El proceso no se completo a tiempo y fue detenido con seguridad.',
        details:
            'Esto suele ocurrir cuando el equipo esta ocupado o el recurso local tarda en responder.',
        suggestions: [
          'Reintente la accion.',
          'Cierre otras tareas pesadas si la computadora esta lenta.',
        ],
      );
    }

    return const FriendlyErrorMessage(
      title: 'No pudimos completar esta accion',
      message: 'No pudimos completar la acción. Intenta nuevamente o contacta al administrador.',
      details:
          'La app sigue funcionando. Puedes intentarlo otra vez.',
      suggestions: [
        'Si vuelve a pasar, copia el detalle y envialo a soporte.',
      ],
    );
  }

  static bool _looksLikeInternetIssue(String raw) {
    return raw.contains('socket') ||
        raw.contains('network is unreachable') ||
        raw.contains('failed host lookup') ||
        raw.contains('no internet') ||
        raw.contains('sin conexion') ||
        raw.contains('offline');
  }

  static bool _looksLikeServerIssue(String raw) {
    return raw.contains('backend') ||
        raw.contains('server') ||
        raw.contains('servidor') ||
        raw.contains('statuscode') ||
        raw.contains('status code') ||
        raw.contains('http ') ||
        raw.contains('gateway') ||
        raw.contains('503') ||
        raw.contains('502') ||
        raw.contains('500');
  }

  static bool _looksLikePermissionIssue(String raw) {
    return raw.contains('forbidden') ||
        raw.contains('unauthorized') ||
        raw.contains('permission') ||
        raw.contains('permiso') ||
      raw.contains('access denied') ||
      raw.contains('authorized for write') ||
      raw.contains('no esta autorizado para escribir') ||
      raw.contains('no esta registrado para escribir');
  }

  static bool _looksLikeValidationIssue(String raw) {
    return raw.contains('validation') ||
        raw.contains('invalid') ||
        raw.contains('invalido') ||
        raw.contains('required') ||
        raw.contains('campo') ||
        raw.contains('formato');
  }

  static FriendlyErrorMessage operation({
    required String action,
    String? module,
    Object? error,
  }) {
    final location = _locationLabel(module);

    if (error is DeviceWriteBlockedException) {
      return FriendlyErrorMessage(
        title: 'PC no autorizada para cambios',
        message:
            'La escritura local esta habilitada. Si ves este mensaje, reinicia la app.',
        details: error.message,
        suggestions: const [
          'Puedes seguir consultando información y reportes.',
          'Reinicia la app y vuelve a intentar.',
        ],
      );
    }

    if (isReadOnlyModeError(error)) {
      return FriendlyErrorMessage(
        title: 'Sistema en modo solo lectura',
        message: 'Sistema en modo solo lectura',
        details:
            'La accion "$action" no se ejecuto porque el sistema esta bloqueando cambios${location.isEmpty ? '' : ' en $location'}.',
        suggestions: const [
          'Puede seguir consultando informacion.',
          'Reintente cuando el modo solo lectura sea desactivado.',
        ],
      );
    }

    if (error is DatabaseException) {
      return FriendlyErrorMessage(
        title: 'No pudimos completar esta operacion',
        message:
            'La informacion local no pudo actualizarse con seguridad en este momento.',
        details:
            'Detuvimos "$action" antes de comprometer datos${location.isEmpty ? '' : ' en $location'}.',
        suggestions: const [
          'Reintente la accion.',
          'Si vuelve a ocurrir, use Reparar o regrese al inicio.',
        ],
      );
    }

    if (error is FileSystemException) {
      return FriendlyErrorMessage(
        title: 'No pudimos finalizar esta operacion',
        message:
            'El sistema no pudo usar un archivo interno necesario para continuar.',
        details:
            'La accion "$action" se detuvo antes de guardar cambios parciales${location.isEmpty ? '' : ' en $location'}.',
        suggestions: const [
          'Revise el espacio disponible del equipo.',
          'Vuelva a intentarlo en unos segundos.',
        ],
      );
    }

    if (error is TimeoutException) {
      return FriendlyErrorMessage(
        title: 'No pudimos completar esta operacion a tiempo',
        message:
            'El proceso se detuvo porque el equipo tardo mas de lo esperado en responder.',
        details:
            'La accion "$action" no se aplico y puede reintentarse sin comprometer la informacion${location.isEmpty ? '' : ' de $location'}.',
        suggestions: const [
          'Reintente la accion.',
          'Cierre otras tareas pesadas si la computadora esta lenta.',
        ],
      );
    }

    return FriendlyErrorMessage(
      title: 'No pudimos completar esta operacion',
      message: 'La accion solicitada no pudo terminar en este momento.',
      details:
          'El sistema dejo la informacion protegida y detuvo "$action" antes de aplicar cambios incompletos${location.isEmpty ? '' : ' en $location'}.',
      suggestions: const [
        'Reintente la accion.',
        'Si vuelve a ocurrir, regrese al inicio o use una opcion de recuperacion.',
      ],
    );
  }

  static FriendlyErrorMessage moduleLoad(String module, Object error) {
    final moduleLabel = _capitalize(module);

    if (isReadOnlyModeError(error)) {
      return const FriendlyErrorMessage(
        title: 'Sistema en modo solo lectura',
        message: 'Sistema en modo solo lectura',
        details:
            'La pantalla sigue disponible para consulta, pero las acciones de escritura estan deshabilitadas temporalmente.',
        suggestions: [
          'Consulte la informacion disponible.',
          'Espere a que el modo solo lectura sea desactivado para aplicar cambios.',
        ],
      );
    }

    if (error is DatabaseException) {
      return FriendlyErrorMessage(
        title: 'No pudimos abrir $moduleLabel',
        message:
            'Este modulo no pudo cargar la informacion local de forma segura.',
        details:
            'Detuvimos la carga para evitar mostrar datos incompletos o inconsistentes.',
        suggestions: const [
          'Use Reintentar para volver a cargar el modulo.',
          'Si el problema continua, regrese al inicio o use Reparar.',
        ],
      );
    }

    if (error is FileSystemException) {
      return FriendlyErrorMessage(
        title: 'No pudimos abrir $moduleLabel',
        message:
            'La aplicacion no pudo acceder a un recurso local necesario para esta pantalla.',
        details:
            'La carga del modulo se detuvo antes de mostrar una vista incompleta.',
        suggestions: const [
          'Revise el estado del equipo y vuelva a intentarlo.',
          'Si continua, regrese al inicio y pruebe nuevamente.',
        ],
      );
    }

    final resolved = unexpected(error);
    return FriendlyErrorMessage(
      title: 'No pudimos abrir $moduleLabel',
      message: resolved.message,
      details:
          'La vista no termino de cargarse y mostramos una salida segura para que pueda recuperarse sin perder el control.',
      suggestions: const [
        'Use Reintentar para cargar el modulo otra vez.',
        'Si continua, vuelva al inicio y pruebe de nuevo.',
      ],
    );
  }

  static FriendlyErrorMessage recoverable({
    required String action,
    String? module,
    Object? error,
  }) {
    final location = _locationLabel(module);
    final resolved = unexpected(error);

    return FriendlyErrorMessage(
      title: 'Detectamos un inconveniente recuperable',
      message:
          'La accion no se completo, pero puede seguir trabajando con seguridad.',
      details:
          'Interrumpimos "$action"${location.isEmpty ? '' : ' en $location'} para mantener la informacion estable.',
      suggestions: [
        'Reintente la accion cuando este listo.',
        ...resolved.suggestions.take(1),
      ],
    );
  }

  static FriendlyErrorMessage startup([Object? error]) {
    final resolved = unexpected(error);
    return FriendlyErrorMessage(
      title: 'No pudimos completar el inicio del sistema',
      message:
          'La aplicacion encontro un problema mientras preparaba los recursos necesarios.',
      details:
          'Se detuvo el inicio para evitar abrir el sistema en un estado inseguro o incompleto.',
      suggestions: [
        'Use Reintentar inicio para volver a preparar el sistema.',
        ...resolved.suggestions.take(1),
      ],
    );
  }

  static String forOperation(
    String action,
    Object error, {
    String? module,
    bool presentToUser = true,
  }) {
    final resolved = operation(action: action, module: module, error: error);

    unawaited(
      AppIncidentReporter.instance.reportHandledOperation(
        action: action,
        module: module,
        title: resolved.title,
        message: resolved.message,
        details: resolved.details,
        suggestions: resolved.suggestions,
        error: error,
        presentToUser: presentToUser,
      ),
    );

    return resolved.message;
  }

  static String _locationLabel(String? module) {
    if (module == null) {
      return '';
    }

    final trimmed = module.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    return _capitalize(trimmed);
  }

  static String _capitalize(String value) {
    if (value.isEmpty) {
      return value;
    }

    return '${value[0].toUpperCase()}${value.substring(1)}';
  }
}
