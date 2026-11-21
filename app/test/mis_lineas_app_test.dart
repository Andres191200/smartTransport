import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app_harness.dart';
import 'support/mis_lineas_steps.dart';

/// Líneas A y D del backend, con pocas estaciones cerca del Obelisco (donde arranca el mapa).
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
      line('A', '18CCF5', [('Perú', -34.6086, -58.3742), ('Lima', -34.6091, -58.3826)]),
      line('D', '00A975', [('Catedral', -34.6074, -58.3741), ('Tribunales', -34.6018, -58.3846)]),
    ],
  };
}

Finder station(String line) => find.bySemanticsLabel(RegExp('^Estación .*, línea $line\$'));

/// Nombres de las Líneas de la pantalla Mis líneas, de arriba hacia abajo.
List<String> listedLines(WidgetTester tester) {
  final rows = find.byWidgetPredicate((w) => w is ListTile && w.title is Text);
  final texts = [
    for (final e in rows.evaluate())
      ((e.widget as ListTile).title as Text).data!,
  ];
  return texts.where((t) => t.startsWith('Línea ') || t == 'Premetro').toList();
}

void main() {
  testWidgets('agregar una Línea de Subte desde Mis líneas la dibuja en el mapa', (tester) async {
    final semantics = tester.ensureSemantics();
    final app = AppHarness(responses: {'/v1/subway/lines': subwayLines()});
    await app.open(tester);

    expect(find.widgetWithText(InkWell, 'Subte'), findsNothing, reason: 'ya no hay botón de capa Subte');
    expect(station('A'), findsNothing);
    expect(station('D'), findsNothing);

    await openMisLineas(tester);
    expect(find.text('Subte'), findsOneWidget);
    await addSubwayLine(tester, 'D');
    expect(listedLines(tester), ['Línea D']);

    // La D ya agregada no se ofrece de nuevo.
    await tester.tap(find.byTooltip('Agregar línea de Subte'));
    await tester.pumpAndSettle();
    final sheet = find.byType(BottomSheet);
    expect(find.descendant(of: sheet, matching: find.bySemanticsLabel('Línea A')), findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.bySemanticsLabel('Línea D')), findsNothing);
    await tester.tapAt(const Offset(600, 100)); // cierra la hoja
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(station('D'), findsWidgets);
    expect(station('A'), findsNothing);

    // Mis líneas se conserva al cerrar y reabrir la app.
    await app.open(tester);
    expect(station('D'), findsWidgets);
    expect(station('A'), findsNothing);
    semantics.dispose();
  });

  testWidgets('quitar una Línea con la ✕ y deshacer la devuelve a su lugar', (tester) async {
    final semantics = tester.ensureSemantics();
    final app = AppHarness(responses: {'/v1/subway/lines': subwayLines()});
    await app.open(tester);
    await openMisLineas(tester);
    for (final l in ['A', 'D', 'H']) {
      await addSubwayLine(tester, l);
    }
    expect(listedLines(tester), ['Línea A', 'Línea D', 'Línea H']);

    await tester.tap(find.byTooltip('Eliminar la D'));
    await tester.pumpAndSettle();
    expect(listedLines(tester), ['Línea A', 'Línea H']);
    expect(find.text('Eliminaste la D'), findsOneWidget);

    await tester.tap(find.text('Deshacer'));
    await tester.pumpAndSettle();
    expect(listedLines(tester), ['Línea A', 'Línea D', 'Línea H']);

    // Quitada, desaparece del mapa; deshacer desde el mapa la vuelve a dibujar.
    await tester.tap(find.byTooltip('Eliminar la D'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(station('D'), findsNothing);
    expect(station('A'), findsWidgets);

    await tester.tap(find.text('Deshacer'));
    await tester.pumpAndSettle();
    expect(station('D'), findsWidgets);
    semantics.dispose();
  });

  testWidgets('el grupo Subte sigue visible al quedarse sin Líneas', (tester) async {
    final semantics = tester.ensureSemantics();
    final app = AppHarness();
    await app.open(tester);
    await openMisLineas(tester);
    await addSubwayLine(tester, 'Premetro');
    expect(listedLines(tester), ['Premetro']);

    await tester.tap(find.byTooltip('Eliminar el Premetro'));
    await tester.pumpAndSettle();
    expect(find.text('Eliminaste el Premetro'), findsOneWidget);
    expect(listedLines(tester), isEmpty);
    expect(find.text('Subte'), findsOneWidget);
    expect(find.byTooltip('Agregar línea de Subte'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('sin Líneas y con Ecobici apagada, el mapa invita a agregar líneas', (tester) async {
    final app = AppHarness(responses: {'/v1/subway/lines': subwayLines()});
    await app.open(tester);
    expect(find.text('Agregar líneas'), findsOneWidget);

    // Con Ecobici prendida el mapa ya muestra algo.
    await tester.tap(find.widgetWithText(InkWell, 'Ecobici'));
    await tester.pumpAndSettle();
    expect(find.text('Agregar líneas'), findsNothing);
    await tester.tap(find.widgetWithText(InkWell, 'Ecobici'));
    await tester.pumpAndSettle();
    expect(find.text('Agregar líneas'), findsOneWidget);

    await tester.tap(find.text('Agregar líneas'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Agregar línea de Subte'), findsOneWidget);

    final semantics = tester.ensureSemantics();
    await addSubwayLine(tester, 'A');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Agregar líneas'), findsNothing);
    semantics.dispose();
  });

  testWidgets('los Medios son los títulos de la pantalla, por encima de sus Líneas', (tester) async {
    final semantics = tester.ensureSemantics();
    final app = AppHarness(responses: {'/v1/subway/lines': subwayLines()});
    await app.open(tester);
    await openMisLineas(tester);
    await addSubwayLine(tester, 'D');

    final linea = tester.widget<Text>(find.text('Línea D')).style ?? const TextStyle();
    final lineaSize = linea.fontSize ?? DefaultTextStyle.of(tester.element(find.text('Línea D'))).style.fontSize!;
    for (final medio in ['Colectivo', 'Subte', 'Ecobici']) {
      expect(
        tester.getSemantics(find.text(medio)),
        matchesSemantics(label: medio, isHeader: true),
        reason: '$medio se anuncia como título',
      );
      final titulo = tester.widget<Text>(find.text(medio)).style!;
      expect(titulo.fontSize, greaterThan(lineaSize), reason: '$medio se ve más grande que sus Líneas');
    }
    semantics.dispose();
  });
}
