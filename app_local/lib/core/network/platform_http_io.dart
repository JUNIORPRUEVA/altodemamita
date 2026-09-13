// Re-exporta los tipos de red NATIVOS de `dart:io`.
//
// Este archivo sólo se usa en compilaciones nativas (Windows / Android /
// desktop). El comportamiento es exactamente el de `dart:io`: no hay shims ni
// capas intermedias.
export 'dart:io'
    show
        ContentType,
        FileSystemException,
        HttpClient,
        HttpClientRequest,
        HttpClientResponse,
        HttpException,
        HttpHeaders,
        HttpStatus,
        IOException,
        InternetAddress,
        SocketException,
        X509Certificate;
