import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:smart_transport/ui/fila_de_botones.dart';
import 'package:smart_transport/ui/toggle_text_button.dart';

import 'support/app_harness.dart';
import 'support/mis_lineas_steps.dart';

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

final _fila = find.byType(FilaDeBotones);

/// El botón de la fila con ese texto.
Finder boton(String text) => find.descendant(of: _fila, matching: find.widgetWithText(InkWell, text));

/// Los textos de los botones de la fila, de izquierda a derecha.
List<String> fila(WidgetTester tester) => [
      for (final b in tester.widgetList<ToggleTextButton>(find.descendant(of: _fila, matching: find.byType(ToggleTextButton))))
        b.text,
    ];

bool activo(WidgetTester tester, String text) => tester.widget<ToggleTextButton>(
      find.descendant(of: _fila, matching: find.widgetWithText(ToggleTextButton, text)),
    ).isActive;

final _ficha = find.byType(BottomSheet);

Finder station(String name) => find.bySemanticsLabel(RegExp('^Estación $name, línea'));

Future<AppHarness> openWithLines(WidgetTester tester, List<String> lines) async {
  final app = AppHarness(responses: {'/v1/subway/lines': subwayLines()});
  await app.open(tester);
  await openMisLineas(tester);
  for (final l in lines) {
    await addSubwayLine(tester, l);
  }
  await tester.pageBack();
  await tester.pumpAndSettle();
  return app;
}

void main() {
  testWidgets('la fila muestra Ecobici y después Mis líneas en orden de agregado, con su color', (tester) async {
    final semantics = tester.ensureSemantics();
    await openWithLines(tester, ['H', 'A', 'D']);

    // "Colectivos" es el botón de capa que sigue hasta que Colectivo entre en Mis líneas (#12).
    expect(fila(tester), ['Ecobici', 'H', 'A', 'D', 'Colectivos']);
    final d = tester.widget<ToggleTextButton>(find.widgetWithText(ToggleTextButton, 'D'));
    expect(d.customization.borderColor, const Color(0xFF00A975));
    expect(d.isActive, isFalse);

    // Una Línea agregada después va al final de las Líneas.
    await openMisLineas(tester);
    await addSubwayLine(tester, 'Premetro');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(fila(tester), ['Ecobici', 'H', 'A', 'D', 'Premetro', 'Colectivos']);
    semantics.dispose();
  });

  testWidgets('tocar una Línea abre su ficha con las Terminales, sin tapar el mapa', (tester) async {
    final semantics = tester.ensureSemantics();
    await openWithLines(tester, ['A', 'D']);
    expect(_ficha, findsNothing);

    await tester.tap(boton('D'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: _ficha, matching: find.text('Línea D')), findsOneWidget);
    expect(find.descendant(of: _ficha, matching: find.text('Catedral – Congreso de Tucumán')), findsOneWidget);
    expect(find.descendant(of: _ficha, matching: find.text('Eliminar')), findsOneWidget);
    expect(activo(tester, 'D'), isTrue);
    expect(activo(tester, 'A'), isFalse);

    // No es modal: el mapa y la fila siguen respondiendo con la ficha abierta.
    await tester.tap(boton('Ecobici'));
    await tester.pumpAndSettle();
    expect(activo(tester, 'Ecobici'), isTrue);
    expect(activo(tester, 'D'), isTrue);

    // Otra Línea cambia la ficha y el botón activo.
    await tester.tap(boton('A'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: _ficha, matching: find.text('Línea A')), findsOneWidget);
    expect(find.descendant(of: _ficha, matching: find.text('Plaza de Mayo – Lima')), findsOneWidget);
    expect(activo(tester, 'A'), isTrue);
    expect(activo(tester, 'D'), isFalse);

    // Tocar de nuevo el botón activo cierra la ficha.
    await tester.tap(boton('A'));
    await tester.pumpAndSettle();
    expect(_ficha, findsNothing);
    expect(activo(tester, 'A'), isFalse);
    semantics.dispose();
  });

  testWidgets('la cámara encuadra el Recorrido entero por encima de la ficha', (tester) async {
    final semantics = tester.ensureSemantics();
    await openWithLines(tester, ['D', 'H']);
    expect(station('Congreso de Tucumán'), findsNothing, reason: 'arranca fuera de la pantalla');

    for (final (line, stations) in [
      ('D', ['Catedral', 'Tribunales', 'Congreso de Tucumán']),
      ('H', ['Hospitales', 'Corrientes', 'Facultad de Derecho']),
    ]) {
      await tester.tap(boton(line));
      await tester.pumpAndSettle();
      final visible = Rect.fromLTRB(
        0,
        tester.getRect(_fila).bottom,
        tester.view.physicalSize.width,
        tester.getRect(_ficha).top,
      );
      for (final name in stations) {
        expect(station(name), findsOneWidget, reason: name);
        expect(visible.contains(tester.getCenter(station(name))), isTrue, reason: '$name se ve arriba de la ficha');
      }
    }
    semantics.dispose();
  });

  testWidgets('"Eliminar" saca la Línea de todos lados y "Deshacer" la devuelve a su lugar', (tester) async {
    final semantics = tester.ensureSemantics();
    await openWithLines(tester, ['A', 'D', 'H']);
    await tester.tap(boton('D'));
    await tester.pumpAndSettle();
    expect(station('Catedral'), findsOneWidget);

    await tester.tap(find.descendant(of: _ficha, matching: find.text('Eliminar')));
    await tester.pumpAndSettle();
    expect(_ficha, findsNothing);
    expect(find.text('Eliminaste la D'), findsOneWidget);
    expect(fila(tester), ['Ecobici', 'A', 'H', 'Colectivos']);
    expect(station('Catedral'), findsNothing);

    await tester.tap(find.text('Deshacer'));
    await tester.pumpAndSettle();
    expect(fila(tester), ['Ecobici', 'A', 'D', 'H', 'Colectivos']);
    expect(station('Catedral'), findsOneWidget);
    expect(activo(tester, 'D'), isFalse);

    // Eliminada de nuevo, tampoco está en la pantalla Mis líneas.
    await tester.tap(boton('D'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: _ficha, matching: find.text('Eliminar')));
    await tester.pumpAndSettle();
    await openMisLineas(tester);
    expect(find.text('Línea A'), findsOneWidget);
    expect(find.text('Línea D'), findsNothing);
    expect(find.text('Línea H'), findsOneWidget);
    semantics.dispose();
  });
}
