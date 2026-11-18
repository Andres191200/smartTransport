import 'package:material_ui/material_ui.dart';

import 'models.dart';
import 'transit_api.dart';

/// El catálogo de Líneas de Colectivo del backend, para el buscador y las fichas. Cambia poco: se
/// pide una sola vez y, si falla, se vuelve a pedir la próxima vez que haga falta.
class CatalogoDeColectivos extends ChangeNotifier {
  CatalogoDeColectivos(this._api);

  final TransitApi _api;

  List<BusLine>? _lineas;
  Future<void>? _cargando;
  String? _error;

  /// Las Líneas de Colectivo, en el orden del backend. Vacío mientras no llegaron.
  List<BusLine> get lineas => _lineas ?? const [];

  /// Si el catálogo ya llegó.
  bool get cargado => _lineas != null;

  /// El motivo por el que falló el último pedido, o null.
  String? get error => _error;

  /// La Línea con ese número, o null si no está en el catálogo (o todavía no llegó).
  BusLine? porId(String id) => lineas.where((l) => l.id == id).firstOrNull;

  /// Pide el catálogo si todavía no llegó. Si falla, lanza la [ApiException].
  Future<void> cargar() {
    if (_lineas != null) return Future.value();
    return _cargando ??= _pedir().whenComplete(() => _cargando = null);
  }

  Future<void> _pedir() async {
    try {
      _lineas = await _api.busLines();
      _error = null;
    } on ApiException catch (e) {
      _error = e.message;
      rethrow;
    } finally {
      // El mapa puede cerrarse antes de que llegue la respuesta.
      if (!_cerrado) notifyListeners();
    }
  }

  bool _cerrado = false;

  @override
  void dispose() {
    _cerrado = true;
    super.dispose();
  }
}
