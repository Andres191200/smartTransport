import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:smart_transport/data/models.dart';
import 'package:smart_transport/ui/map_screen.dart' show joinSpanish;
import 'package:smart_transport/ui/sheets.dart';

void main() {
  group('formatEta', () {
    final now = DateTime(2026, 1, 1, 12);

    test('llegando, minutos y horas', () {
      expect(formatEta(now.add(const Duration(seconds: 20)), now), 'Llegando');
      expect(formatEta(now.subtract(const Duration(seconds: 10)), now), 'Llegando');
      expect(formatEta(now.add(const Duration(minutes: 3, seconds: 10)), now), 'en 3 min');
      expect(formatEta(now.add(const Duration(minutes: 75)), now), 'en 1 h 15 min');
    });
  });

  test('joinSpanish', () {
    expect(joinSpanish(['subte']), 'subte');
    expect(joinSpanish(['colectivos', 'subte']), 'colectivos y subte');
    expect(joinSpanish(['colectivos', 'subte', 'Ecobici']), 'colectivos, subte y Ecobici');
  });

  testWidgets('BikeStationSheet muestra disponibilidad', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: BikeStationSheet(
          station: BikeStation(
            id: '2',
            name: 'Retiro I',
            position: LatLng(-34.59, -58.37),
            bikes: 5,
            ebikes: 2,
            docks: 15,
            operational: true,
            acceptsReturns: true,
            address: 'Av. del Libertador',
          ),
        ),
      ),
    ));

    expect(find.text('Retiro I'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('15'), findsOneWidget);
    expect(find.text('3 mecánicas · 2 eléctricas'), findsOneWidget);
  });

  testWidgets('BikeStationSheet fuera de servicio', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: BikeStationSheet(
          station: BikeStation(
            id: '9', name: 'Cerrada', position: LatLng(-34.6, -58.4),
            bikes: 0, ebikes: 0, docks: 0, operational: false, acceptsReturns: false,
          ),
        ),
      ),
    ));
    expect(find.text('Estación fuera de servicio'), findsOneWidget);
    expect(find.text('No recibe devoluciones por ahora'), findsOneWidget);
  });
}
