import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app_harness.dart';
import 'support/mapa_steps.dart';

/// `/v1/subway/alerts`: los avisos nombran las Líneas con los ids del backend ("LineaD"). Hay
/// uno de una Línea ajena (la A), uno general sin Líneas y dos que tocan la D y la H.
Map<String, Object> subwayAlerts() {
  Map<String, Object> alert(String title, List<String> lines) =>
      {'id': title, 'title': title, 'lineIds': [for (final l in lines) 'Linea$l']};
  return {
    'mode': 'live',
    'alerts': [
      alert('Demoras en la A', ['A']),
      alert('Aviso general', []),
      alert('Obras en la D', ['D']),
      alert('Frecuencia reducida en la H y la A', ['H', 'A']),
    ],
  };
}

final _iconoDeAvisos = find.byTooltip('Estado del subte');

/// El número del ícono de avisos de la barra superior, o null si no muestra ninguno.
String? contadorDeAvisos(WidgetTester tester) =>
    tester.widgetList<Text>(find.descendant(of: _iconoDeAvisos, matching: find.byType(Text))).firstOrNull?.data;

/// Los títulos de los avisos de la lista, de arriba hacia abajo.
List<String> avisosListados(WidgetTester tester) {
  final titulos = [
    for (final tile in tester.widgetList<ListTile>(find.byType(ListTile)))
      if (tile.title case Text(:final data?)) data,
  ];
  return titulos..sort((a, b) => tester.getTopLeft(find.text(a)).dy.compareTo(tester.getTopLeft(find.text(b)).dy));
}

Future<void> abrirAvisos(WidgetTester tester) async {
  await tester.tap(_iconoDeAvisos);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sin Líneas de Subte en Mis líneas, el ícono de avisos no muestra número', (tester) async {
    final app = AppHarness(responses: {'/v1/subway/lines': subwayLines(), '/v1/subway/alerts': subwayAlerts()});
    await app.open(tester);
    expect(contadorDeAvisos(tester), isNull);

    // La lista igual muestra todos los avisos.
    await abrirAvisos(tester);
    expect(avisosListados(tester), [
      'Demoras en la A',
      'Aviso general',
      'Obras en la D',
      'Frecuencia reducida en la H y la A',
    ]);
  });

  testWidgets('el contador cuenta solo los avisos de Mis líneas y la lista los muestra primero', (tester) async {
    final semantics = tester.ensureSemantics();
    await openWithLines(tester, ['D', 'H'], responses: {'/v1/subway/alerts': subwayAlerts()});

    // La A no está en Mis líneas y el aviso general no es de ninguna Línea: no cuentan.
    expect(contadorDeAvisos(tester), '2');

    await abrirAvisos(tester);
    expect(avisosListados(tester), [
      'Obras en la D',
      'Frecuencia reducida en la H y la A',
      'Demoras en la A',
      'Aviso general',
    ]);
    await tester.tapAt(const Offset(600, 100)); // cierra la lista tocando el mapa
    await tester.pumpAndSettle();

    // Al eliminar la H, su aviso deja de contar y pasa con el resto.
    await tester.tap(boton('H'));
    await tester.pumpAndSettle();
    await tester.tap(enFicha(find.text('Eliminar')));
    await tester.pumpAndSettle();
    expect(contadorDeAvisos(tester), '1');

    await abrirAvisos(tester);
    expect(avisosListados(tester), [
      'Obras en la D',
      'Demoras en la A',
      'Aviso general',
      'Frecuencia reducida en la H y la A',
    ]);
    semantics.dispose();
  });
}
