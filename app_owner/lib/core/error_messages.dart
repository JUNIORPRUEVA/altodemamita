import 'dart:async';
import 'dart:io';

String friendlyErrorMessage(Object? error) {
  if (error is SocketException || error is TimeoutException) {
    return 'Revisa tu conexión e intenta de nuevo.';
  }

  if (error is HttpException) {
    return 'No pudimos actualizar la información.';
  }

  if (error is FormatException || error is TypeError) {
    return 'Recibimos información inesperada.';
  }

  return 'Algo no salió bien. Intenta de nuevo.';
}
