import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app_harness.dart';

/// Una estación de Ecobici junto al Obelisco, donde arranca el mapa.
Map<String, Object> bikeStations() => {
      'mode': 'live',
      'stations': [
        {
          'id': '1',
          'name': 'Obelisco',
          'lat': -34.6035,
          'lon': -58.3815,
          'bikes': 7,
          'docks': 5,
          'operational': true,
        },
      ],
    };

/// Estaciones de Ecobici junto al Obelisco, cada una con sus bicis y si presta o no.
Map<String, Object> estaciones(List<(String nombre, int bicis, bool presta)> datos) => {
      'mode': 'live',
      'stations': [
        for (final (i, (nombre, bicis, presta)) in datos.indexed)
          {
            'id': '$i',
            'name': nombre,
            'lat': -34.6035 + i * 0.002,
            'lon': -58.3815,
            'bikes': bicis,
            'docks': 5,
            'operational': presta,
          },
      ],
    };

/// La estación que el lector de pantalla anuncia así.
Finder estacion(String anuncio) => find.bySemanticsLabel(RegExp('^${RegExp.escape(anuncio)}'));

/// El número (o "–") que muestra el marcador de la estación con ese anuncio.
Finder textoDelMarcador(String anuncio, String texto) =>
    find.descendant(of: estacion(anuncio), matching: find.text(texto));

final _station = find.bySemanticsLabel(RegExp(r'^Ecobici Obelisco'));
final _ecobiciButton = find.widgetWithText(InkWell, 'Ecobici');
const _switchText = 'Mostrar estaciones al abrir la app';

/// Si el botón Ecobici de la fila del mapa está prendido.
bool ecobiciOn(WidgetTester tester) => tester.getSemantics(_ecobiciButton).flagsCollection.isToggled.toBoolOrNull()!;

Future<void> openMisLineas(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Menú'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Mis líneas'));
  await tester.pumpAndSettle();
}

Future<void> setShowStationsOnOpen(WidgetTester tester, bool on) async {
  await openMisLineas(tester);
  final tile = find.widgetWithText(SwitchListTile, _switchText);
  if (tester.widget<SwitchListTile>(tile).value != on) {
    await tester.tap(tile);
    await tester.pumpAndSettle();
  }
  expect(tester.widget<SwitchListTile>(tile).value, on);
  await tester.pageBack();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Mis líneas tiene el grupo Ecobici con su interruptor, sin Líneas ni "+"', (tester) async {
    final app = AppHarness();
    await app.open(tester);
    await openMisLineas(tester);

    expect(find.text('Ecobici'), findsOneWidget);
    expect(find.widgetWithText(SwitchListTile, _switchText), findsOneWidget);
    final header = find.ancestor(of: find.text('Ecobici'), matching: find.byType(Row)).first;
    expect(find.descendant(of: header, matching: find.byType(IconButton)), findsNothing, reason: 'sin "+"');
    expect(find.byTooltip(RegExp('Ecobici')), findsNothing);
  });

  testWidgets('sin preferencia guardada, Ecobici arranca apagada', (tester) async {
    final semantics = tester.ensureSemantics();
    final app = AppHarness(responses: {'/v1/ecobici/stations': bikeStations()});
    await app.open(tester);

    expect(ecobiciOn(tester), isFalse);
    expect(_station, findsNothing);
    expect(app.requests.map((u) => u.path), isNot(contains('/v1/ecobici/stations')));
    semantics.dispose();
  });

  testWidgets('con el interruptor prendido, Ecobici arranca prendida', (tester) async {
    final semantics = tester.ensureSemantics();
    final app = AppHarness(responses: {'/v1/ecobici/stations': bikeStations()});
    await app.open(tester);
    await setShowStationsOnOpen(tester, true);

    await app.open(tester);
    expect(ecobiciOn(tester), isTrue);
    expect(_station, findsOneWidget);

    // Y sigue así en las aperturas siguientes.
    await app.open(tester);
    expect(ecobiciOn(tester), isTrue);
    semantics.dispose();
  });

  testWidgets('con el interruptor apagado, Ecobici arranca apagada', (tester) async {
    final semantics = tester.ensureSemantics();
    final app = AppHarness(responses: {'/v1/ecobici/stations': bikeStations()});
    await app.open(tester);
    await setShowStationsOnOpen(tester, true);
    await app.open(tester);
    await setShowStationsOnOpen(tester, false);

    await app.open(tester);
    expect(ecobiciOn(tester), isFalse);
    expect(_station, findsNothing);
    semantics.dispose();
  });

  testWidgets('prender Ecobici desde el mapa no cambia cómo arranca la próxima vez', (tester) async {
    final semantics = tester.ensureSemantics();
    final app = AppHarness(responses: {'/v1/ecobici/stations': bikeStations()});
    await app.open(tester);

    await tester.tap(_ecobiciButton);
    await tester.pumpAndSettle();
    expect(ecobiciOn(tester), isTrue);
    expect(_station, findsOneWidget);

    await app.open(tester);
    expect(ecobiciOn(tester), isFalse);
    expect(_station, findsNothing);
    semantics.dispose();
  });

  testWidgets('apagar Ecobici desde el mapa no cambia cómo arranca la próxima vez', (tester) async {
    final semantics = tester.ensureSemantics();
    final app = AppHarness(responses: {'/v1/ecobici/stations': bikeStations()});
    await app.open(tester);
    await setShowStationsOnOpen(tester, true);
    await app.open(tester);

    await tester.tap(_ecobiciButton);
    await tester.pumpAndSettle();
    expect(ecobiciOn(tester), isFalse);
    expect(_station, findsNothing);

    await app.open(tester);
    expect(ecobiciOn(tester), isTrue);
    expect(_station, findsOneWidget);
    await openMisLineas(tester);
    expect(tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, _switchText)).value, isTrue);
    semantics.dispose();
  });

  testWidgets('cerrar la ficha de una estación no abre el teclado del buscador', (tester) async {
    final semantics = tester.ensureSemantics();
    final app = AppHarness(responses: {'/v1/ecobici/stations': bikeStations()});
    await app.open(tester);
    await tester.tap(_ecobiciButton);
    await tester.pumpAndSettle();

    // El usuario usó el buscador y cerró el teclado con "atrás": el buscador sigue con el foco.
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);

    await tester.tap(_station);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);

    // Tocar el mapa fuera de la ficha la cierra.
    await tester.tapAt(const Offset(600, 300));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.testTextInput.isVisible, isFalse, reason: 'el teclado no se abre solo');
    expect(tester.testTextInput.hasAnyClients, isFalse, reason: 'el buscador no recupera el foco');
    semantics.dispose();
  });

  testWidgets('una estación sin bicis muestra "0" y una que no presta muestra "–"', (tester) async {
    final semantics = tester.ensureSemantics();
    final app = AppHarness(responses: {
      '/v1/ecobici/stations': estaciones([('Vacía', 0, true), ('Cerrada', 4, false), ('Llena', 7, true)]),
    });
    await app.open(tester);
    await tester.tap(_ecobiciButton);
    await tester.pumpAndSettle();

    expect(textoDelMarcador('Ecobici Vacía: 0 bicis', '0'), findsOneWidget);
    expect(textoDelMarcador('Ecobici Cerrada: 4 bicis', '–'), findsOneWidget);
    expect(textoDelMarcador('Ecobici Cerrada: 4 bicis', '4'), findsNothing);
    expect(textoDelMarcador('Ecobici Llena: 7 bicis', '7'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('el número de bicis de dos dígitos entra en el círculo de la estación', (tester) async {
    final semantics = tester.ensureSemantics();
    final app = AppHarness(responses: {
      '/v1/ecobici/stations': estaciones([('Grande', 88, true)]),
    });
    await app.open(tester);
    await tester.tap(_ecobiciButton);
    await tester.pumpAndSettle();

    final marcador = tester.getRect(estacion('Ecobici Grande: 88 bicis'));
    final numero = tester.getRect(textoDelMarcador('Ecobici Grande: 88 bicis', '88'));
    // Adentro del borde blanco del círculo, centrado y en una sola línea.
    const bordeBlanco = 1.5;
    expect(numero.width, lessThanOrEqualTo(marcador.width - 2 * bordeBlanco));
    expect(numero.center.dx, moreOrLessEquals(marcador.center.dx, epsilon: 0.5));
    expect(numero.center.dy, moreOrLessEquals(marcador.center.dy, epsilon: 0.5));
    expect(numero.height, lessThan(marcador.height / 2), reason: 'no se parte en dos líneas');
    semantics.dispose();
  });
}
