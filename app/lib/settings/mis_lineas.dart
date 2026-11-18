import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cada tipo de transporte que muestra la app.
enum Medio { colectivo, subte, ecobici }

/// Una Línea de Mis líneas: el número de Colectivo (p. ej. "60") o la Línea de Subte
/// (p. ej. "D" o "Premetro").
@immutable
class Linea {
  const Linea(this.medio, this.id);

  final Medio medio;
  final String id;

  @override
  bool operator ==(Object other) => other is Linea && other.medio == medio && other.id == id;

  @override
  int get hashCode => Object.hash(medio, id);

  @override
  String toString() => '${medio.name}:$id';

  static Linea? _parse(String saved) {
    final [medio, ...id] = saved.split(':');
    final m = Medio.values.where((v) => v.name == medio).firstOrNull;
    return m == null || id.isEmpty ? null : Linea(m, id.join(':'));
  }
}

/// Lo que hace falta para deshacer una eliminación (ver [MisLineas.deshacer]).
@immutable
class LineaEliminada {
  const LineaEliminada._(this.linea, this.posicion);

  final Linea linea;
  final int posicion;
}

/// Mis líneas y los Medios elegidos por el usuario, guardados en el dispositivo.
///
/// Reglas: las Líneas quedan en orden de agregado; agregar una Línea suma su Medio; y el
/// grupo de un Medio no se borra solo cuando se queda sin Líneas.
class MisLineas extends ChangeNotifier {
  MisLineas._(this._prefs, this._medios, this._lineas);

  static const _keyMedios = 'mis_lineas.medios';
  static const _keyLineas = 'mis_lineas.lineas';

  final SharedPreferencesAsync _prefs;
  final Set<Medio> _medios;
  final List<Linea> _lineas;

  static Future<MisLineas> load([SharedPreferencesAsync? prefs]) async {
    prefs ??= SharedPreferencesAsync();
    final medios = await prefs.getStringList(_keyMedios) ?? const [];
    final lineas = await prefs.getStringList(_keyLineas) ?? const [];
    return MisLineas._(
      prefs,
      {for (final m in medios) ...Medio.values.where((v) => v.name == m)},
      [for (final l in lineas) ?Linea._parse(l)],
    );
  }

  /// Medios elegidos. Que Ecobici esté elegido significa "mostrar estaciones al abrir la app".
  Set<Medio> get medios => Set.unmodifiable(_medios);

  /// Todas las Líneas, en orden de agregado.
  List<Linea> get lineas => List.unmodifiable(_lineas);

  List<Linea> lineasDe(Medio medio) => [for (final l in _lineas) if (l.medio == medio) l];

  bool contiene(Linea linea) => _lineas.contains(linea);

  /// Agrega la Línea al final y suma su Medio a los elegidos. Si ya estaba, no hace nada.
  Future<void> agregar(Linea linea) async {
    if (_lineas.contains(linea)) return;
    _lineas.add(linea);
    _medios.add(linea.medio);
    notifyListeners();
    await _guardar();
  }

  /// Saca la Línea (su Medio sigue elegido). Devuelve lo necesario para [deshacer], o null si
  /// la Línea no estaba.
  Future<LineaEliminada?> eliminar(Linea linea) async {
    final posicion = _lineas.indexOf(linea);
    if (posicion < 0) return null;
    _lineas.removeAt(posicion);
    notifyListeners();
    await _guardar();
    return LineaEliminada._(linea, posicion);
  }

  /// Devuelve la Línea eliminada a la posición que tenía.
  Future<void> deshacer(LineaEliminada eliminada) async {
    if (_lineas.contains(eliminada.linea)) return;
    _lineas.insert(eliminada.posicion.clamp(0, _lineas.length), eliminada.linea);
    _medios.add(eliminada.linea.medio);
    notifyListeners();
    await _guardar();
  }

  Future<void> _guardar() async {
    await _prefs.setStringList(_keyMedios, [for (final m in Medio.values) if (_medios.contains(m)) m.name]);
    await _prefs.setStringList(_keyLineas, [for (final l in _lineas) '$l']);
  }
}
