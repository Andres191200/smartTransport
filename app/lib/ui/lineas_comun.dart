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

/// Azul de las Líneas de Colectivo: el borde de sus botones y sus Recorridos.
const azulColectivo = Color(0xFF0B5CAD);

extension LineaUI on Linea {
  /// La Línea de Subte, o null si es de otro Medio.
  LineaDeSubte? get deSubte => medio == Medio.subte ? LineaDeSubte.porId(id) : null;

  /// "Línea D", "Premetro" o "Línea 60".
  String get nombre => deSubte?.nombre ?? 'Línea $id';

  /// "la D", "el Premetro" o "el 60", para frases como "Eliminaste la D".
  String get conArticulo => deSubte?.conArticulo ?? 'el $id';

  /// El color de la Línea en Subte; azul en Colectivo.
  Color get color => deSubte?.color ?? azulColectivo;
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

/// Cómo se reconoce una Línea en listas y fichas: el círculo de su color en Subte y el ícono de
/// Colectivo sobre azul en Colectivo.
class IconoDeLinea extends StatelessWidget {
  const IconoDeLinea({super.key, required this.linea, this.size = 40});

  final Linea linea;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (linea.deSubte case final subte?) return CirculoDeSubte(linea: subte, size: size);
    return Semantics(
      label: linea.nombre,
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: azulColectivo, shape: BoxShape.circle),
        child: Icon(linea.medio.icono, color: Colors.white, size: size * 0.55),
      ),
    );
  }
}
