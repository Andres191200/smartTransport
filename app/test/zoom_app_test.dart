import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';
import 'support/mapa_steps.dart';

// Las estaciones de Subte y de Ecobici se dibujan solo desde cierto zoom; los colectivos, con
// cualquiera. El mapa arranca en zoom 14, donde se ven las dos.

/// Una estación de Ecobici junto al Obelisco, donde arranca el mapa.
Map<String, Object> _bikeStations() => {
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

final _bikeStation = find.bySemanticsLabel(RegExp(r'^Ecobici Obelisco'));

void main() {
  testWidgets('las estaciones de las Líneas de Subte de Mis líneas se ven desde zoom 12.5', (tester) async {
    final semantics = tester.ensureSemantics();
    await openWithLines(tester, ['A']);
    expect(station('Lima'), findsOneWidget);
    expect(station('Plaza de Mayo'), findsOneWidget);

    await zoomA(tester, 13);
    expect(station('Lima'), findsOneWidget);

    await zoomA(tester, 12.49);
    expect(station('Lima'), findsNothing);
    expect(station('Plaza de Mayo'), findsNothing);

    await zoomA(tester, 11);
    expect(station('Lima'), findsNothing);

    await zoomA(tester, 12.5);
    expect(station('Lima'), findsOneWidget);
    expect(station('Plaza de Mayo'), findsOneWidget);

    // Al volver a alejarse, desaparecen otra vez.
    await zoomA(tester, 12.4);
    expect(station('Lima'), findsNothing);
    expect(station('Plaza de Mayo'), findsNothing);
    semantics.dispose();
  });

  testWidgets('con Ecobici prendida, sus estaciones se ven desde zoom 13.5', (tester) async {
    final semantics = tester.ensureSemantics();
    final app = AppHarness(responses: {'/v1/ecobici/stations': _bikeStations()});
    await app.open(tester);
    await tester.tap(boton('Ecobici'));
    await tester.pumpAndSettle();
    expect(_bikeStation, findsOneWidget);

    await zoomA(tester, 15);
    expect(_bikeStation, findsOneWidget);

    await zoomA(tester, 13.49);
    expect(_bikeStation, findsNothing);

    await zoomA(tester, 12);
    expect(_bikeStation, findsNothing);

    await zoomA(tester, 13.5);
    expect(_bikeStation, findsOneWidget);

    // Al volver a alejarse, desaparecen otra vez.
    await zoomA(tester, 13.4);
    expect(_bikeStation, findsNothing);
    semantics.dispose();
  });

  testWidgets('entre zoom 12.5 y 13.5 se ven las estaciones de Subte pero no las de Ecobici', (tester) async {
    final semantics = tester.ensureSemantics();
    await openWithLines(tester, ['A'], responses: {'/v1/ecobici/stations': _bikeStations()});
    await tester.tap(boton('Ecobici'));
    await tester.pumpAndSettle();
    expect(station('Lima'), findsOneWidget);
    expect(_bikeStation, findsOneWidget);

    await zoomA(tester, 13);
    expect(station('Lima'), findsOneWidget);
    expect(_bikeStation, findsNothing);

    await zoomA(tester, 14);
    expect(station('Lima'), findsOneWidget);
    expect(_bikeStation, findsOneWidget);
    semantics.dispose();
  });
}
