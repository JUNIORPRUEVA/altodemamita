import 'dart:async';
import 'dart:io';

String friendlyErrorMessage(Object? error) {
  if (error is SocketException || error is TimeoutException) {
    return 'La actualización tardó más de lo esperado. Puedes seguir usando la información disponible.';
  }

  if (error is HttpException) {
    return 'La información disponible se mantendrá en pantalla mientras intentamos actualizar.';
  }

  if (error is FormatException || error is TypeError) {
    return 'Estamos ajustando la actualización de datos.';
  }

  return 'No pudimos completar la actualización ahora mismo.';
}
