import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:smart_transport/ui/buscador_de_lineas.dart';
import 'package:smart_transport/ui/fila_de_botones.dart';
import 'package:smart_transport/ui/toggle_text_button.dart';

import 'app_harness.dart';
import 'mis_lineas_steps.dart';

// Datos y pasos del mapa que usan varios tests de la app entera.

/// Líneas de Subte del backend. La D llega hasta Congreso de Tucumán, lejos del Obelisco (donde
/// arranca el mapa): para verla entera, la cámara tiene que moverse. La H va de norte a sur: en
/// una pantalla vertical, lo que limita el encuadre es el alto que deja libre la ficha.
Map<String, Object> subwayLines() {
  Map<String, Object> line(String name, String color, List<(String, double, double)> stations) => {
        'id': 'Linea$name',
        'name': name,
        'color': color,
        'textColor': 'FFFFFF',
        'path': [for (final (_, lat, lon) in stations) [lat, lon]],
        'stations': [
          for (final (station, lat, lon) in stations)
            {'id': 'Linea$name:$station', 'name': station, 'lat': lat, 'lon': lon},
        ],
      };
  return {
    'mode': 'live',
    'lines': [
      line('A', '18CCF5', [('Plaza de Mayo', -34.6088, -58.3711), ('Lima', -34.6091, -58.3826)]),
      line('D', '00A975', [
        ('Catedral', -34.6074, -58.3741),
        ('Tribunales', -34.6018, -58.3846),
        ('Congreso de Tucumán', -34.5553, -58.4630),
      ]),
      line('H', 'FFD600', [
        ('Hospitales', -34.6413, -58.4126),
        ('Corrientes', -34.6045, -58.4053),
        ('Facultad de Derecho', -34.5833, -58.3911),
      ]),
    ],
  };
}

/// Abre la app con [subwayLines] y agrega [lines] desde la pantalla Mis líneas (necesita
/// `tester.ensureSemantics()`). [responses] suma otras respuestas del backend (ver [AppHarness]).
Future<AppHarness> openWithLines(
  WidgetTester tester,
  List<String> lines, {
  Map<String, Object> responses = const {},
}) async {
  final app = AppHarness(responses: {'/v1/subway/lines': subwayLines(), ...responses});
  await app.open(tester);
  await openMisLineas(tester);
  for (final l in lines) {
    await addSubwayLine(tester, l);
  }
  await tester.pageBack();
  await tester.pumpAndSettle();
  return app;
}

/// La fila de botones de arriba del mapa.
final filaDeBotones = find.byType(FilaDeBotones);

/// El botón de la fila con ese texto.
Finder boton(String text) => find.descendant(of: filaDeBotones, matching: find.widgetWithText(InkWell, text));

/// Los textos de los botones de la fila, de izquierda a derecha.
List<String> fila(WidgetTester tester) => [
      for (final b in tester.widgetList<ToggleTextButton>(find.descendant(of: filaDeBotones, matching: find.byType(ToggleTextButton))))
        b.text,
    ];

bool activo(WidgetTester tester, String text) => tester.widget<ToggleTextButton>(
      find.descendant(of: filaDeBotones, matching: find.widgetWithText(ToggleTextButton, text)),
    ).isActive;

/// La ficha de Línea abierta.
final ficha = find.byType(BottomSheet);

/// Algo dentro de la ficha abierta.
Finder enFicha(Finder finder) => find.descendant(of: ficha, matching: finder);

/// El marcador de una estación de Subte en el mapa (necesita `tester.ensureSemantics()`).
Finder station(String name) => find.bySemanticsLabel(RegExp('^Estación $name, línea'));

/// Escribe en el buscador del mapa.
Future<void> buscar(WidgetTester tester, String text) async {
  await tester.enterText(
    find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'Buscar línea'),
    text,
  );
  await tester.pumpAndSettle();
}

/// El resultado del buscador con ese nombre (p. ej. "Línea D").
Finder resultado(String nombre) =>
    find.descendant(of: find.byType(ResultadosDeBusqueda), matching: find.widgetWithText(ListTile, nombre));
