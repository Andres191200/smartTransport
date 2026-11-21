import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_transport/data/transit_api.dart';

// Los datos fijos de la medición de fluidez: siempre los mismos, para que dos corridas sean
// comparables. Salen de un backend falso, sin red.

/// Una API que responde siempre lo mismo, sin backend: unas 370 estaciones de Ecobici alrededor
/// del centro, las Líneas de Subte B y D y la Línea de Colectivo 60 con sus colectivos.
TransitApi apiConDatosFijos() => TransitApi(baseUrl: 'http://backend.medicion', client: MockClient(_responder));

Future<http.Response> _responder(http.Request request) async {
  final body = switch (request.url.path) {
    '/v1/ecobici/stations' => {'mode': 'live', 'stations': _estacionesDeEcobici},
    '/v1/subway/lines' => {'mode': 'live', 'lines': _lineasDeSubte},
    '/v1/subway/alerts' => {'mode': 'live', 'alerts': <Object>[]},
    '/v1/subway/arrivals' => {'mode': 'live', 'arrivals': <Object>[]},
    '/v1/buses/lines' => {'mode': 'live', 'lines': [_linea60(conRecorrido: false)]},
    '/v1/buses/paths' => {'mode': 'live', 'line': _linea60(conRecorrido: true)},
    '/v1/buses' => {'mode': 'live', 'truncated': false, 'vehicles': _colectivos},
    _ => null,
  };
  if (body == null) return http.Response(jsonEncode({'error': 'Ruta desconocida: ${request.url.path}'}), 404);
  return http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

typedef _Punto = (double lat, double lon);

/// [n] puntos repartidos en línea recta de [desde] a [hasta], con las dos puntas incluidas.
List<_Punto> _entre(_Punto desde, _Punto hasta, int n) => [
      for (var i = 0; i < n; i++)
        (desde.$1 + (hasta.$1 - desde.$1) * i / (n - 1), desde.$2 + (hasta.$2 - desde.$2) * i / (n - 1)),
    ];

/// La cantidad real de estaciones de Ecobici, repartidas al azar (siempre con la misma semilla)
/// alrededor del Obelisco, donde arranca el mapa. Algunas sin bicis y algunas fuera de servicio,
/// como en el feed real.
final List<Map<String, Object>> _estacionesDeEcobici = () {
  final azar = Random(26);
  return [
    for (var i = 0; i < 370; i++)
      {
        'id': '$i',
        'name': 'Estación $i',
        'lat': -34.645 + azar.nextDouble() * 0.08,
        'lon': -58.445 + azar.nextDouble() * 0.09,
        'bikes': azar.nextInt(5) == 0 ? 0 : azar.nextInt(20),
        'docks': azar.nextInt(15),
        'operational': azar.nextInt(20) != 0,
      },
  ];
}();

Map<String, Object> _lineaDeSubte(String nombre, String color, _Punto desde, _Punto hasta, int estaciones) {
  final puntos = _entre(desde, hasta, estaciones);
  return {
    'id': 'Linea$nombre',
    'name': nombre,
    'color': color,
    'textColor': 'FFFFFF',
    'path': [for (final (lat, lon) in puntos) [lat, lon]],
    'stations': [
      for (final (i, (lat, lon)) in puntos.indexed)
        {'id': 'Linea$nombre:$i', 'name': 'Estación $nombre$i', 'lat': lat, 'lon': lon},
    ],
  };
}

/// Las Líneas B y D, con la cantidad real de estaciones entre sus Terminales reales.
final _lineasDeSubte = [
  _lineaDeSubte('B', 'EB0909', (-34.6030, -58.3700), (-34.5743, -58.4867), 17),
  _lineaDeSubte('D', '00A975', (-34.6074, -58.3741), (-34.5553, -58.4630), 16),
];

/// Los Ramales de la Línea 60: de Constitución hacia el norte, pasando cerca del Obelisco.
final _ramalesDel60 = {
  '60A': (terminales: ['Constitución', 'Escobar'], recorrido: _entre((-34.6277, -58.3815), (-34.3484, -58.7957), 60)),
  '60B': (terminales: ['Constitución', 'Tigre'], recorrido: _entre((-34.6277, -58.3815), (-34.4260, -58.5796), 60)),
};

Map<String, Object> _linea60({required bool conRecorrido}) => {
      'id': '60',
      'branches': [
        for (final MapEntry(key: id, value: ramal) in _ramalesDel60.entries)
          {
            'id': id,
            'terminals': ramal.terminales,
            if (conRecorrido) 'path': [for (final (lat, lon) in ramal.recorrido) [lat, lon]],
          },
      ],
    };

/// Colectivos de la 60 cada tanto sobre sus Recorridos, los de dentro de la ciudad.
final _colectivos = [
  for (final MapEntry(key: ramal, value: (:recorrido, terminales: _)) in _ramalesDel60.entries)
    for (final (i, (lat, lon)) in recorrido.take(20).indexed)
      if (i.isEven) {'id': 'bus-$ramal-$i', 'lat': lat, 'lon': lon, 'line': ramal},
];
