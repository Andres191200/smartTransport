import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:smart_transport/ui/lineas_comun.dart' show azulColectivo;

import 'app_harness.dart';
import 'mapa_steps.dart';

// Datos y pasos de Colectivo que usan los tests de la app entera.

typedef _Ramal = ({String id, (String, String)? terminales, List<(double, double)> path});

const _constitucion = (-34.6277, -58.3815);

/// Las Líneas de Colectivo del backend falso. La 60 tiene dos Ramales que comparten la Terminal
/// Constitución; la 29 tiene un Ramal sin Terminales ni Recorrido, como puede mandar el backend.
final Map<String, List<_Ramal>> _lineas = {
  '29': [(id: '29', terminales: null, path: [])],
  '60': [
    (
      id: '60A',
      terminales: ('Constitución', 'Escobar'),
      path: [_constitucion, (-34.6045, -58.3925), (-34.5813, -58.4207), (-34.3484, -58.7957)],
    ),
    (
      id: '60B',
      terminales: ('Constitución', 'Tigre'),
      path: [_constitucion, (-34.6045, -58.3925), (-34.5813, -58.4207), (-34.426, -58.5796)],
    ),
  ],
  '152': [
    (id: '152', terminales: ('La Boca', 'Olivos'), path: [(-34.6345, -58.3631), (-34.6083, -58.3712), (-34.51, -58.489)]),
  ],
};

Map<String, Object> _ramal(_Ramal r, {required bool conRecorrido}) => {
      'id': r.id,
      if (r.terminales case (final desde, final hasta)) 'terminals': [desde, hasta],
      if (conRecorrido) 'path': [for (final (lat, lon) in r.path) [lat, lon]],
    };

/// `/v1/buses/lines`: el catálogo, sin Recorridos.
Map<String, Object> busLines() => {
      'mode': 'live',
      'lines': [
        for (final MapEntry(key: id, value: ramales) in _lineas.entries)
          {'id': id, 'branches': [for (final r in ramales) _ramal(r, conRecorrido: false)]},
      ],
    };

/// `/v1/buses/paths?line=60`: los Recorridos de una Línea; 404 si no existe.
Map<String, Object>? busPaths(Uri request) => switch (_lineas[request.queryParameters['line']]) {
      final ramales? => {
          'mode': 'live',
          'line': {
            'id': request.queryParameters['line']!,
            'branches': [for (final r in ramales) _ramal(r, conRecorrido: true)],
          },
        },
      null => null,
    };

/// `/v1/buses`: un colectivo de cada Ramal junto al Obelisco. Responde todos, pida lo que pida la
/// app: así se ve que el mapa no dibuja los de Líneas que no están en Mis líneas.
Map<String, Object> buses() => {
      'mode': 'live',
      'truncated': false,
      'vehicles': [
        for (final (i, ramal) in ['60A', '60B', '152', '29'].indexed)
          {'id': 'bus-$ramal', 'lat': -34.6040 + i * 0.001, 'lon': -58.3820, 'line': ramal},
      ],
    };

/// Abre la app con el Subte de [subwayLines] y el Colectivo de arriba.
Future<AppHarness> openWithColectivos(WidgetTester tester) async {
  final app = AppHarness(responses: {
    '/v1/subway/lines': subwayLines(),
    '/v1/buses/lines': busLines(),
    '/v1/buses/paths': busPaths,
    '/v1/buses': buses(),
  });
  await app.open(tester);
  return app;
}

/// Agrega una Línea de Colectivo desde la pantalla Mis líneas, con su buscador.
Future<void> addColectivoLine(WidgetTester tester, String line) async {
  await tester.tap(find.byTooltip('Agregar línea de Colectivo'));
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextField, 'Buscar línea de Colectivo'), line);
  await tester.pumpAndSettle();
  await tester.tap(resultado('Línea $line'));
  await tester.pumpAndSettle();
}

/// Cuántos Recorridos de Colectivo dibuja el mapa.
int recorridosDeColectivo(WidgetTester tester) => tester
    .widgetList<PolylineLayer>(find.byType(PolylineLayer))
    .expand((layer) => layer.polylines)
    .where((p) => p.color == azulColectivo && p.points.isNotEmpty)
    .length;

/// El marcador de un colectivo en vivo de ese Ramal (necesita `tester.ensureSemantics()`). Su
/// etiqueta suma el texto del marcador: "Colectivo línea 60A\n60A".
Finder colectivo(String ramal) => find.bySemanticsLabel(RegExp('^Colectivo línea ${RegExp.escape(ramal)}(\$|\n)'));

/// Cualquier colectivo en vivo en el mapa.
final algunColectivo = find.bySemanticsLabel(RegExp('^Colectivo línea'));

/// El marcador de una Terminal de Colectivo (necesita `tester.ensureSemantics()`).
Finder terminal(String name) => find.bySemanticsLabel('Terminal $name');

/// Los pedidos de colectivos en vivo que hizo la app.
Iterable<Uri> pedidosDeColectivos(AppHarness app) => app.requests.where((u) => u.path == '/v1/buses');
