import 'package:material_ui/material_ui.dart';

import '../data/models.dart';
import 'lineas_comun.dart' show azulColectivo;

/// Colores de disponibilidad compartidos entre el marcador y la hoja de Ecobici.
Color bikeAvailabilityColor(BikeStation s) {
  if (!s.operational) return Colors.grey;
  if (s.bikes == 0) return const Color(0xFFD32F2F);
  if (s.bikes < 3) return const Color(0xFFF57C00);
  return const Color(0xFF2E7D32);
}

class BusMarker extends StatelessWidget {
  const BusMarker({super.key, required this.bus, this.highlighted = false});

  final Bus bus;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Colectivo línea ${bus.line}',
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: highlighted ? scheme.tertiary : scheme.primary,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: const [BoxShadow(blurRadius: 2, color: Colors.black26, offset: Offset(0, 1))],
        ),
        child: FittedBox(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              bus.line,
              style: TextStyle(
                color: highlighted ? scheme.onTertiary : scheme.onPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SubwayStationMarker extends StatelessWidget {
  const SubwayStationMarker({super.key, required this.line, required this.station});

  final SubwayLine line;
  final SubwayStation station;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      // Cada estación se anuncia sola, aunque no se pueda tocar (las Terminales de la vista previa).
      container: true,
      label: 'Estación ${station.name}, línea ${line.name}',
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: line.color, width: 3.5),
        ),
      ),
    );
  }
}

/// Una Terminal de un Recorrido de Colectivo en la ficha abierta.
class TerminalDeColectivoMarker extends StatelessWidget {
  const TerminalDeColectivoMarker({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Terminal $name',
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: azulColectivo, width: 3.5),
        ),
      ),
    );
  }
}

/// Una estación de Ecobici: un círculo del color de su disponibilidad, con borde blanco y su número
/// de bicis, o "–" si no presta.
///
/// Se dibujan unas 370 a la vez, así que es barato a propósito: sin sombra difuminada (la reemplaza
/// un contorno fino, para que se distinga sobre el mapa claro) y con el texto de tamaño fijo, sin
/// `FittedBox`. El texto no sigue la escala de texto del sistema: el círculo tiene tamaño fijo, y
/// el lector de pantalla anuncia las bicis igual.
class BikeStationMarker extends StatelessWidget {
  const BikeStationMarker({super.key, required this.station});

  final BikeStation station;

  static const _contorno = BoxDecoration(
    shape: BoxShape.circle,
    border: Border.fromBorderSide(
      BorderSide(color: Colors.black38, width: 0.75, strokeAlign: BorderSide.strokeAlignOutside),
    ),
  );

  static const _texto = TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12, height: 1);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Ecobici ${station.name}: ${station.bikes} bicis',
      child: DecoratedBox(
        decoration: _contorno,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bikeAvailabilityColor(station),
            shape: BoxShape.circle,
            border: const Border.fromBorderSide(BorderSide(color: Colors.white, width: 1.5)),
          ),
          child: Text(
            station.operational ? '${station.bikes}' : '–',
            style: _texto,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            textAlign: TextAlign.center,
            textScaler: TextScaler.noScaling,
          ),
        ),
      ),
    );
  }
}

class UserLocationMarker extends StatelessWidget {
  const UserLocationMarker({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.blue,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [BoxShadow(blurRadius: 8, color: Colors.blue.withValues(alpha: 0.4))],
      ),
    );
  }
}
