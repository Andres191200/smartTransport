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
}
