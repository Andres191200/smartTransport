import 'dart:async';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app_harness.dart';
import 'support/mapa_steps.dart';
import 'support/mis_lineas_steps.dart';

const _colorD = Color(0xFF00A975);

/// Si el mapa dibuja algún Recorrido de ese color.
bool recorridoDibujado(WidgetTester tester, Color color) => tester
    .widgetList<PolylineLayer>(find.byType(PolylineLayer))
    .expand((layer) => layer.polylines)
    .any((p) => p.color == color && p.points.isNotEmpty);

/// Los nombres de los resultados del buscador, de arriba hacia abajo.
List<String> resultados(WidgetTester tester) => [
      for (final tile in tester.widgetList<ListTile>(find.descendant(
        of: find.byType(Scaffold).last,
        matching: find.byType(ListTile),
      )))
        if (tile.title case Text(:final data?)) data,
    ];

void main() {
  testWidgets('buscar "D" muestra la Línea D con el ícono de Subte', (tester) async {
    final semantics = tester.ensureSemantics();
    await openWithLines(tester, []);

    await buscar(tester, 'D');
    expect(resultado('Línea D'), findsOneWidget);
    expect(find.descendant(of: resultado('Línea D'), matching: find.byIcon(Icons.subway_outlined)), findsOneWidget);
    expect(resultado('Línea A'), findsNothing);

    // Sin tildes ni mayúsculas, y con "línea" adelante, también.
    await buscar(tester, 'linea d');
    expect(resultado('Línea D'), findsOneWidget);
    await buscar(tester, 'pre');
    expect(resultado('Premetro'), findsOneWidget);

    // Lo que no es una Línea de Subte no muestra resultados.
    await buscar(tester, '60');
    expect(resultado('Línea D'), findsNothing);
    semantics.dispose();
  });

  testWidgets('las Líneas ya agregadas muestran el badge "✓ Ya agregada"', (tester) async {
    final semantics = tester.ensureSemantics();
    await openWithLines(tester, ['A']);

    await buscar(tester, 'subte');
    expect(find.descendant(of: resultado('Línea A'), matching: find.text('Ya agregada')), findsOneWidget);
    expect(find.descendant(of: resultado('Línea A'), matching: find.byIcon(Icons.check)), findsOneWidget);
    expect(find.descendant(of: resultado('Línea D'), matching: find.text('Ya agregada')), findsNothing);
    semantics.dispose();
  });

  testWidgets('la ficha de una Línea no agregada dibuja su Recorrido y Terminales, y al cerrarla desaparecen',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await openWithLines(tester, ['A']);
    expect(recorridoDibujado(tester, _colorD), isFalse);

    await buscar(tester, 'D');
    await tester.tap(resultado('Línea D'));
    await tester.pumpAndSettle();

    expect(resultado('Línea D'), findsNothing, reason: 'la lista de resultados se cierra');
    expect(enFicha(find.text('Línea D')), findsOneWidget);
    expect(enFicha(find.text('Catedral – Congreso de Tucumán')), findsOneWidget);
    expect(enFicha(find.text('Agregar a Mis líneas')), findsOneWidget);
    expect(enFicha(find.text('Eliminar')), findsNothing);

    // Solo el Recorrido y las Terminales, sin las demás estaciones (el Subte no tiene vehículos en vivo).
    expect(recorridoDibujado(tester, _colorD), isTrue);
    expect(station('Catedral'), findsOneWidget);
    expect(station('Congreso de Tucumán'), findsOneWidget);
    expect(station('Tribunales'), findsNothing);
    expect(fila(tester), ['Ecobici', 'A', 'Colectivos'], reason: 'no está en Mis líneas');

    await tester.tap(enFicha(find.byTooltip('Cerrar')));
    await tester.pumpAndSettle();
    expect(ficha, findsNothing);
    expect(recorridoDibujado(tester, _colorD), isFalse);
    expect(station('Catedral'), findsNothing);
    expect(station('Congreso de Tucumán'), findsNothing);
    semantics.dispose();
  });

  testWidgets('"Agregar a Mis líneas" la suma al mapa, a la fila y a la pantalla Mis líneas', (tester) async {
    final semantics = tester.ensureSemantics();
    await openWithLines(tester, []);

    await buscar(tester, 'D');
    await tester.tap(resultado('Línea D'));
    await tester.pumpAndSettle();
    await tester.tap(enFicha(find.text('Agregar a Mis líneas')));
    await tester.pumpAndSettle();

    // La ficha sigue abierta, ahora con "Eliminar", y su botón aparece activo en la fila.
    expect(enFicha(find.text('Línea D')), findsOneWidget);
    expect(enFicha(find.text('Eliminar')), findsOneWidget);
    expect(fila(tester), ['Ecobici', 'D', 'Colectivos']);
    expect(activo(tester, 'D'), isTrue);
    expect(station('Tribunales'), findsOneWidget, reason: 'ya se dibujan todas sus estaciones');

    // Al cerrar la ficha sigue en el mapa.
    await tester.tap(enFicha(find.byTooltip('Cerrar')));
    await tester.pumpAndSettle();
    expect(recorridoDibujado(tester, _colorD), isTrue);
    expect(station('Tribunales'), findsOneWidget);
    expect(activo(tester, 'D'), isFalse);

    await openMisLineas(tester);
    expect(find.widgetWithText(ListTile, 'Línea D'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('buscar una Línea ya agregada abre su ficha con "Eliminar"', (tester) async {
    final semantics = tester.ensureSemantics();
    await openWithLines(tester, ['A', 'D']);

    await buscar(tester, 'D');
    await tester.tap(resultado('Línea D'));
    await tester.pumpAndSettle();
    expect(enFicha(find.text('Línea D')), findsOneWidget);
    expect(enFicha(find.text('Eliminar')), findsOneWidget);
    expect(enFicha(find.text('Agregar a Mis líneas')), findsNothing);
    expect(activo(tester, 'D'), isTrue);

    await tester.tap(enFicha(find.text('Eliminar')));
    await tester.pumpAndSettle();
    expect(ficha, findsNothing);
    expect(find.text('Eliminaste la D'), findsOneWidget);
    expect(fila(tester), ['Ecobici', 'A', 'Colectivos']);
    semantics.dispose();
  });

  testWidgets('enter en el buscador abre la ficha de la primera Línea encontrada', (tester) async {
    final semantics = tester.ensureSemantics();
    await openWithLines(tester, []);

    await buscar(tester, 'h');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(enFicha(find.text('Línea H')), findsOneWidget);
    expect(enFicha(find.text('Hospitales – Facultad de Derecho')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('la ficha abierta antes de que lleguen los datos del Subte se completa al llegar', (tester) async {
    final semantics = tester.ensureSemantics();
    // El backend tarda en mandar las Líneas de Subte.
    final llegan = Completer<void>();
    final app = AppHarness(responses: {'/v1/subway/lines': subwayLines()});
    app.delays['/v1/subway/lines'] = llegan.future;
    await app.open(tester);

    await buscar(tester, 'D');
    await tester.tap(resultado('Línea D'));
    await tester.pumpAndSettle();
    expect(enFicha(find.text('Línea D')), findsOneWidget);
    expect(enFicha(find.text('Catedral – Congreso de Tucumán')), findsNothing);
    expect(station('Congreso de Tucumán'), findsNothing);

    llegan.complete();
    await tester.pumpAndSettle();
    expect(enFicha(find.text('Catedral – Congreso de Tucumán')), findsOneWidget);
    expect(recorridoDibujado(tester, _colorD), isTrue);
    // Y la cámara lo encuadra: la Terminal lejana entra arriba de la ficha.
    expect(station('Congreso de Tucumán'), findsOneWidget);
    expect(tester.getCenter(station('Congreso de Tucumán')).dy, lessThan(tester.getRect(ficha).top));
    semantics.dispose();
  });

  testWidgets('el "+" general de Mis líneas pregunta el Medio y abre el buscador filtrado', (tester) async {
    final semantics = tester.ensureSemantics();
    await openWithLines(tester, ['A']);
    await openMisLineas(tester);

    await tester.tap(find.byTooltip('Agregar línea'));
    await tester.pumpAndSettle();
    expect(find.text('¿De qué Medio es la línea?'), findsOneWidget);
    expect(find.descendant(of: find.byType(BottomSheet), matching: find.text('Ecobici')), findsNothing,
        reason: 'Ecobici no tiene Líneas');
    await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('Subte')));
    await tester.pumpAndSettle();

    // El buscador de Subte arranca con todas sus Líneas; la A ya está agregada.
    expect(find.widgetWithText(TextField, 'Buscar línea de Subte'), findsOneWidget);
    expect(resultados(tester), ['Línea A', 'Línea B', 'Línea C', 'Línea D', 'Línea E', 'Línea H', 'Premetro']);
    expect(find.descendant(of: resultado('Línea A'), matching: find.text('Ya agregada')), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'd');
    await tester.pumpAndSettle();
    expect(resultados(tester), ['Línea D']);
    await tester.tap(resultado('Línea D'));
    await tester.pumpAndSettle();

    // De vuelta en Mis líneas, con la D agregada.
    expect(find.text('Mis líneas'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Línea D'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(fila(tester), ['Ecobici', 'A', 'D', 'Colectivos']);
    semantics.dispose();
  });
}
