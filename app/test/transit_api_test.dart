import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:smart_transport/data/transit_api.dart';

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  group('TransitApi', () {
    test('buses: pide todas las Líneas en un solo pedido y parsea vehículos', () async {
      late Uri requested;
      final api = TransitApi(
        baseUrl: 'http://server/',
        client: MockClient((req) async {
          requested = req.url;
          return _json({
            'mode': 'live',
            'truncated': false,
            'vehicles': [
              {'id': '1', 'lat': -34.6, 'lon': -58.4, 'line': '60A', 'headsign': 'Escobar', 'speedMps': 10, 'timestamp': 1700000000},
              {'id': '2', 'lat': -34.61, 'lon': -58.41, 'line': '152'},
            ],
          });
        }),
      );

      final result = await api.buses(lines: ['60', '152']);

      expect(requested.path, '/v1/buses');
      expect(requested.queryParameters, {'line': '60,152'}, reason: 'sin bbox: toda la ciudad');
      expect(result.vehicles.map((b) => b.line), ['60A', '152']);
      expect(result.vehicles.map((b) => b.lineId), ['60', '152']);
      expect(result.vehicles.first.speedMps, 10.0);
      expect(result.vehicles.first.timestamp, DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000));
      expect(result.vehicles.last.headsign, isNull);
      expect(api.demoLayers, isEmpty);
    });

    test('busLines: el catálogo, con Terminales que pueden faltar', () async {
      late Uri requested;
      final api = TransitApi(
        baseUrl: 'http://server',
        client: MockClient((req) async {
          requested = req.url;
          return _json({
            'mode': 'demo',
            'lines': [
              {
                'id': '60',
                'branches': [
                  {'id': '60A', 'terminals': ['Constitución', 'Escobar']},
                  {'id': '60B'},
                ],
              },
            ],
          });
        }),
      );

      final [line] = await api.busLines();
      expect(requested.path, '/v1/buses/lines');
      expect(line.id, '60');
      expect(line.branches.map((b) => (b.id, b.terminales)), [('60A', ('Constitución', 'Escobar')), ('60B', null)]);
      expect(line.branches.map((b) => b.path), everyElement(isEmpty), reason: 'el catálogo no trae Recorridos');
      expect(api.demoLayers, ['colectivos']);
    });

    test('busPaths: los Recorridos de los Ramales de una Línea, aunque alguno venga vacío', () async {
      late Uri requested;
      final api = TransitApi(
        baseUrl: 'http://server',
        client: MockClient((req) async {
          requested = req.url;
          return _json({
            'mode': 'live',
            'line': {
              'id': '60',
              'branches': [
                {'id': '60A', 'terminals': ['Constitución', 'Escobar'], 'path': [[-34.62, -58.38], [-34.35, -58.79]]},
                {'id': '60B', 'path': <Object>[]},
              ],
            },
          });
        }),
      );

      final line = await api.busPaths('60');
      expect(requested.path, '/v1/buses/paths');
      expect(requested.queryParameters['line'], '60');
      expect(line.branches.first.path, [const LatLng(-34.62, -58.38), const LatLng(-34.35, -58.79)]);
      expect(line.branches.last.path, isEmpty);
    });

    test('subwayLines: colores y recorrido; detecta qué capa es demo', () async {
      final api = TransitApi(
        baseUrl: 'http://server',
        client: MockClient((_) async => _json({
              'mode': 'demo',
              'lines': [
                {
                  'id': 'LineaA', 'name': 'A', 'color': '18CCF5', 'textColor': 'FFFFFF',
                  'path': [[-34.60, -58.37], [-34.61, -58.38]],
                  'stations': [{'id': 'LineaA:peru', 'name': 'Perú', 'lat': -34.6, 'lon': -58.37}],
                },
              ],
            })),
      );

      final [line] = await api.subwayLines();
      expect(line.color.toARGB32(), 0xFF18CCF5);
      expect(line.path, hasLength(2));
      expect(line.stations.single.name, 'Perú');
      expect(api.demoLayers, ['subte']);
    });

    test('subwayArrivals codifica el id de estación', () async {
      late Uri requested;
      final api = TransitApi(
        baseUrl: 'http://server',
        client: MockClient((req) async {
          requested = req.url;
          return _json({
            'arrivals': [
              {'destination': 'San Pedrito', 'arrivalTime': 1700000100, 'delaySeconds': 30},
            ],
          });
        }),
      );
      final [arrival] = await api.subwayArrivals('LineaA:saenz-pena');
      expect(requested.queryParameters['station'], 'LineaA:saenz-pena');
      expect(arrival.destination, 'San Pedrito');
      expect(arrival.delaySeconds, 30);
    });

    test('bikeStations', () async {
      final api = TransitApi(
        baseUrl: 'http://server',
        client: MockClient((_) async => _json({
              'stations': [
                {'id': '2', 'name': 'Retiro I', 'lat': -34.59, 'lon': -58.37, 'bikes': 5, 'ebikes': 2, 'docks': 15, 'operational': true, 'acceptsReturns': false, 'capacity': 20},
              ],
            })),
      );
      final [s] = await api.bikeStations();
      expect((s.bikes, s.ebikes, s.docks, s.capacity, s.operational, s.acceptsReturns), (5, 2, 15, 20, true, false));
    });

    test('demoLayers sigue el modo de cada endpoint por separado', () async {
      var busesMode = 'demo';
      final api = TransitApi(
        baseUrl: 'http://server',
        client: MockClient((req) async => req.url.path == '/v1/buses'
            ? _json({'mode': busesMode, 'vehicles': [], 'truncated': false})
            : _json({'mode': 'live', 'stations': []})),
      );
      await api.bikeStations();
      expect(api.demoLayers, isEmpty);
      await api.buses(lines: ['60']);
      expect(api.demoLayers, ['colectivos']);
      busesMode = 'live';
      await api.buses(lines: ['60']);
      expect(api.demoLayers, isEmpty);
    });

    test('errores del servidor se convierten en ApiException con su mensaje', () async {
      final api = TransitApi(
        baseUrl: 'http://server',
        client: MockClient((_) async => _json({'error': 'La API Transporte no respondió'}, 502)),
      );
      expect(
        api.bikeStations(),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'La API Transporte no respondió')),
      );
    });

    test('sin conexión', () async {
      final api = TransitApi(
        baseUrl: 'http://server',
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      expect(api.subwayAlerts(), throwsA(isA<ApiException>()));
    });
  });
}
