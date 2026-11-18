import 'package:geolocator/geolocator.dart';

/// Pide el permiso de ubicación del teléfono y dice si quedó concedido. Los tests lo reemplazan
/// al construir la app, porque `geolocator` necesita el teléfono.
typedef PedirPermisoDeUbicacion = Future<bool> Function();

/// Pide el permiso con `geolocator`. Si ya estaba concedido o rechazado para siempre, no vuelve a
/// preguntar. Un error del plugin cuenta como rechazo: la app funciona igual sin ubicación.
Future<bool> pedirPermisoDeUbicacionConGeolocator() async {
  try {
    var permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) permiso = await Geolocator.requestPermission();
    return permiso == LocationPermission.whileInUse || permiso == LocationPermission.always;
  } on Exception {
    // Sin plugin, sin los permisos declarados en el manifiesto o con un pedido ya en curso.
    return false;
  }
}
