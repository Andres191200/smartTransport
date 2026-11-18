import 'dart:ui' show Color;

import 'package:latlong2/latlong.dart';

// Modelos del JSON que devuelve NUESTRO backend (no la API del GCBA directamente).

double _d(Object? v) => (v as num).toDouble();
double? _dOrNull(Object? v) => (v as num?)?.toDouble();
DateTime? _epochSeconds(Object? v) =>
    v == null ? null : DateTime.fromMillisecondsSinceEpoch((v as num).toInt() * 1000);

Color _hexColor(String hex) => Color(int.parse('FF$hex', radix: 16));

class Bus {
  const Bus({
    required this.id,
    required this.position,
    required this.line,
    this.headsign,
    this.agency,
    this.speedMps,
    this.timestamp,
  });

  factory Bus.fromJson(Map<String, dynamic> j) => Bus(
        id: j['id'] as String,
        position: LatLng(_d(j['lat']), _d(j['lon'])),
        line: j['line'] as String,
        headsign: j['headsign'] as String?,
        agency: j['agency'] as String?,
        speedMps: _dOrNull(j['speedMps']),
        timestamp: _epochSeconds(j['timestamp']),
      );

  final String id;
  final LatLng position;

  /// El Ramal, p. ej. "60A".
  final String line;
  final String? headsign;
  final String? agency;
  final double? speedMps;
  final DateTime? timestamp;

  /// La Línea de Colectivo del Ramal: su número sin el sufijo de letras ("60A" → "60"), con la
  /// misma regla que el backend.
  String get lineId {
    final name = line.trim().toUpperCase();
    return RegExp(r'^(.*\d)[A-Z]*$').firstMatch(name)?.group(1) ?? name;
  }
}

class BusesResult {
  const BusesResult({required this.vehicles, required this.truncated});

  factory BusesResult.fromJson(Map<String, dynamic> j) => BusesResult(
        vehicles: [for (final v in j['vehicles'] as List) Bus.fromJson(v as Map<String, dynamic>)],
        truncated: j['truncated'] as bool? ?? false,
      );

  final List<Bus> vehicles;

  /// true si había más colectivos en la zona de los que devolvió el servidor.
  final bool truncated;
}

/// Un Ramal de una Línea de Colectivo (p. ej. el 60A), con sus Terminales y su Recorrido.
class BusBranch {
  const BusBranch({required this.id, this.terminales, this.path = const []});

  factory BusBranch.fromJson(Map<String, dynamic> j) => BusBranch(
        id: j['id'] as String,
        terminales: switch (j['terminals']) {
          [final String desde, final String hasta] => (desde, hasta),
          _ => null,
        },
        path: [
          for (final p in j['path'] as List? ?? const []) LatLng(_d((p as List)[0]), _d(p[1])),
        ],
      );

  /// "60A", o "152" si la Línea tiene un solo Ramal.
  final String id;

  /// Las dos Terminales, en el sentido del Recorrido. Null si el backend no las conoce.
  final (String, String)? terminales;

  /// El Recorrido; vacío en el catálogo (se pide aparte) o si el backend no lo tiene.
  final List<LatLng> path;
}

/// Una Línea de Colectivo con sus Ramales.
class BusLine {
  const BusLine({required this.id, required this.branches});

  factory BusLine.fromJson(Map<String, dynamic> j) => BusLine(
        id: j['id'] as String,
        branches: [
          for (final b in j['branches'] as List? ?? const []) BusBranch.fromJson(b as Map<String, dynamic>),
        ],
      );

  /// El número de la Línea, p. ej. "60".
  final String id;
  final List<BusBranch> branches;
}

class SubwayStation {
  const SubwayStation({required this.id, required this.name, required this.position});

  factory SubwayStation.fromJson(Map<String, dynamic> j) => SubwayStation(
        id: j['id'] as String,
        name: j['name'] as String,
        position: LatLng(_d(j['lat']), _d(j['lon'])),
      );

  final String id;
  final String name;
  final LatLng position;
}

class SubwayLine {
  const SubwayLine({
    required this.id,
    required this.name,
    required this.color,
    required this.textColor,
    required this.path,
    required this.stations,
  });

  factory SubwayLine.fromJson(Map<String, dynamic> j) => SubwayLine(
        id: j['id'] as String,
        name: j['name'] as String,
        color: _hexColor(j['color'] as String),
        textColor: _hexColor(j['textColor'] as String),
        path: [
          for (final p in j['path'] as List) LatLng(_d((p as List)[0]), _d(p[1])),
        ],
        stations: [
          for (final s in j['stations'] as List) SubwayStation.fromJson(s as Map<String, dynamic>),
        ],
      );

  final String id;
  final String name;
  final Color color;
  final Color textColor;
  final List<LatLng> path;
  final List<SubwayStation> stations;

  /// Las dos Terminales: la primera y la última estación. Null si la Línea no trae estaciones.
  (String, String)? get terminales =>
      stations.length < 2 ? null : (stations.first.name, stations.last.name);
}

class SubwayArrival {
  const SubwayArrival({
    required this.destination,
    required this.arrivalTime,
    required this.delaySeconds,
  });

  factory SubwayArrival.fromJson(Map<String, dynamic> j) => SubwayArrival(
        destination: j['destination'] as String,
        arrivalTime: _epochSeconds(j['arrivalTime'])!,
        delaySeconds: (j['delaySeconds'] as num?)?.toInt() ?? 0,
      );

  final String destination;
  final DateTime arrivalTime;
  final int delaySeconds;
}

class BikeStation {
  const BikeStation({
    required this.id,
    required this.name,
    required this.position,
    required this.bikes,
    required this.ebikes,
    required this.docks,
    required this.operational,
    required this.acceptsReturns,
    this.address,
    this.capacity,
  });

  factory BikeStation.fromJson(Map<String, dynamic> j) => BikeStation(
        id: j['id'] as String,
        name: j['name'] as String,
        position: LatLng(_d(j['lat']), _d(j['lon'])),
        bikes: (j['bikes'] as num).toInt(),
        ebikes: (j['ebikes'] as num?)?.toInt() ?? 0,
        docks: (j['docks'] as num).toInt(),
        operational: j['operational'] as bool,
        acceptsReturns: j['acceptsReturns'] as bool? ?? true,
        address: j['address'] as String?,
        capacity: (j['capacity'] as num?)?.toInt(),
      );

  final String id;
  final String name;
  final LatLng position;
  final int bikes;
  final int ebikes;
  final int docks;

  /// Instalada y prestando bicis.
  final bool operational;

  /// Se puede devolver una bici acá.
  final bool acceptsReturns;
  final String? address;
  final int? capacity;
}

class ServiceAlert {
  const ServiceAlert({required this.id, required this.title, required this.lineIds, this.description});

  factory ServiceAlert.fromJson(Map<String, dynamic> j) => ServiceAlert(
        id: j['id'] as String,
        title: j['title'] as String,
        description: j['description'] as String?,
        lineIds: [for (final id in j['lineIds'] as List) id as String],
      );

  final String id;
  final String title;
  final String? description;
  final List<String> lineIds;
}
