import 'package:material_ui/material_ui.dart';

import '../settings/mis_lineas.dart';
import 'models.dart';

/// Una Línea de Subte tal como la conoce la app, sin depender del backend: así se puede
/// mostrar y elegir aunque los datos todavía no hayan llegado. El Recorrido y las estaciones
/// vienen del backend ([SubwayLine]).
@immutable
class LineaDeSubte {
  const LineaDeSubte._(this.id, this.color, [this.textColor = Colors.white]);

  /// Lo que se guarda en Mis líneas: la letra ("A") o "Premetro".
  final String id;
  final Color color;
  final Color textColor;

  /// Las Líneas de Subte, en el orden en que se ofrecen.
  static const todas = [
    LineaDeSubte._('A', Color(0xFF18CCF5)),
    LineaDeSubte._('B', Color(0xFFEB0909)),
    LineaDeSubte._('C', Color(0xFF233AA8)),
    LineaDeSubte._('D', Color(0xFF00A975)),
    LineaDeSubte._('E', Color(0xFF7D2B8B)),
    LineaDeSubte._('H', Color(0xFFFFD600), Colors.black),
    LineaDeSubte._('Premetro', Color(0xFFF59C00)),
  ];

  /// La Línea con ese [id]. Si no se conoce (p. ej. una Línea nueva guardada por otra versión
  /// de la app), una gris con ese nombre.
  static LineaDeSubte porId(String id) =>
      todas.where((l) => l.id == id).firstOrNull ?? LineaDeSubte._(id, Colors.grey);

  /// La Línea de Mis líneas que corresponde a una Línea del backend, o null si no se reconoce.
  static LineaDeSubte? de(SubwayLine line) {
    final name = line.name.trim().toUpperCase();
    final porLetra = todas.where((l) => l.id == name).firstOrNull;
    if (porLetra != null) return porLetra;
    final esPremetro = name == 'P' || name == 'PM' || '$name ${line.id}'.toUpperCase().contains('PREMETRO');
    return esPremetro ? porId('Premetro') : null;
  }

  bool get _esPremetro => id == 'Premetro';

  Linea get linea => Linea(Medio.subte, id);

  /// "Línea D" o "Premetro".
  String get nombre => _esPremetro ? id : 'Línea $id';

  /// "la D" o "el Premetro", para frases como "Eliminaste la D".
  String get conArticulo => _esPremetro ? 'el $id' : 'la $id';

  /// Lo que va dentro del círculo: "D" o "P".
  String get sigla => _esPremetro ? 'P' : id;
}
