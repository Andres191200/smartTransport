import 'package:material_ui/material_ui.dart';

import '../data/models.dart';

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

class BikeStationMarker extends StatelessWidget {
  const BikeStationMarker({super.key, required this.station});

  final BikeStation station;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Ecobici ${station.name}: ${station.bikes} bicis',
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bikeAvailabilityColor(station),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: const [BoxShadow(blurRadius: 2, color: Colors.black26, offset: Offset(0, 1))],
        ),
        child: FittedBox(
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Text(
              station.operational ? '${station.bikes}' : '–',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
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
