import 'package:material_ui/material_ui.dart';

import '../data/lineas_de_subte.dart';
import '../settings/mis_lineas.dart';

// Piezas de Mis líneas que usan varias pantallas: el mapa, la pantalla Mis líneas y el buscador.

extension MedioUI on Medio {
  /// "Colectivo", "Subte" o "Ecobici".
  String get nombre => switch (this) {
        Medio.colectivo => 'Colectivo',
        Medio.subte => 'Subte',
        Medio.ecobici => 'Ecobici',
      };

  IconData get icono => switch (this) {
        Medio.colectivo => Icons.directions_bus,
        Medio.subte => Icons.subway_outlined,
        Medio.ecobici => Icons.pedal_bike,
      };
}

extension LineaUI on Linea {
  /// "Línea D", "Premetro" o "Línea 60".
  String get nombre => switch (medio) {
        Medio.subte => LineaDeSubte.porId(id).nombre,
        _ => 'Línea $id',
      };

  /// "la D", "el Premetro" o "el 60", para frases como "Eliminaste la D".
  String get conArticulo => switch (medio) {
        Medio.subte => LineaDeSubte.porId(id).conArticulo,
        _ => 'el $id',
      };
}

/// Saca la Línea de Mis líneas y muestra "Eliminaste la D · Deshacer".
Future<void> eliminarConDeshacer(ScaffoldMessengerState messenger, MisLineas misLineas, Linea linea) async {
  final eliminada = await misLineas.eliminar(linea);
  if (eliminada == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text('Eliminaste ${linea.conArticulo}'),
      // Se va solo, como cualquier aviso: deshacer es una oportunidad, no una pregunta.
      persist: false,
      action: SnackBarAction(label: 'Deshacer', onPressed: () => misLineas.deshacer(eliminada)),
    ));
}

/// Círculo del color de una Línea de Subte con su letra, como en las estaciones.
class CirculoDeSubte extends StatelessWidget {
  const CirculoDeSubte({super.key, required this.linea, this.size = 40});

  final LineaDeSubte linea;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: linea.nombre,
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: linea.color, shape: BoxShape.circle),
        child: Text(
          linea.sigla,
          style: TextStyle(color: linea.textColor, fontWeight: FontWeight.w700, fontSize: size * 0.45),
        ),
      ),
    );
  }
}
