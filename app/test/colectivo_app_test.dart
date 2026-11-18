import 'dart:async';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:smart_transport/ui/lineas_comun.dart' show azulColectivo;
import 'package:smart_transport/ui/toggle_text_button.dart';

import 'support/colectivo_steps.dart';
import 'support/mapa_steps.dart';
import 'support/mis_lineas_steps.dart';

/// Nombres de las Líneas de la pantalla Mis líneas, de arriba hacia abajo.
List<String> listadas(WidgetTester tester) => [
      for (final tile in tester.widgetList<ListTile>(find.byType(ListTile)))
        if (tile.title case Text(:final data?) when data.startsWith('Línea ')) data,
    ];

/// Abre la ficha de una Línea desde el buscador del mapa.
Future<void> abrirDesdeElBuscador(WidgetTester tester, String nombre) async {
  await buscar(tester, nombre.replaceFirst('Línea ', ''));
  await tester.tap(resultado(nombre));
  await tester.pumpAndSettle();
}

/// Agrega Líneas de Colectivo desde la pantalla Mis líneas y vuelve al mapa.
Future<void> agregarColectivos(WidgetTester tester, List<String> lines) async {
  await openMisLineas(tester);
  for (final l in lines) {
    await addColectivoLine(tester, l);
  }
  await tester.pageBack();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('buscar "60" muestra la Línea 60 de Colectivo y su ficha lista sus Ramales con sus Terminales',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final app = await openWithColectivos(tester);

    await buscar(tester, '60');
    expect(resultado('Línea 60'), findsOneWidget);
    expect(find.descendant(of: resultado('Línea 60'), matching: find.byIcon(Icons.directions_bus)), findsOneWidget);
    expect(resultado('Línea 152'), findsNothing);
    await buscar(tester, 'colectivo 15');
    expect(resultado('Línea 152'), findsOneWidget);

    // Los Recorridos tardan en llegar: la ficha muestra igual los Ramales del catálogo.
    final llegan = Completer<void>();
    app.delays['/v1/buses/paths'] = llegan.future;
    await abrirDesdeElBuscador(tester, 'Línea 60');
    expect(enFicha(find.text('Línea 60')), findsOneWidget);
    expect(enFicha(find.text('60A · Constitución – Escobar')), findsOneWidget);
    expect(enFicha(find.text('60B · Constitución – Tigre')), findsOneWidget);
    expect(enFicha(find.text('Agregar a Mis líneas')), findsOneWidget);
    expect(recorridosDeColectivo(tester), 0);
    expect(app.requests.where((u) => u.path == '/v1/buses/paths').map((u) => u.queryParameters['line']), ['60']);

    llegan.complete();
    await tester.pumpAndSettle();
    expect(recorridosDeColectivo(tester), 2, reason: 'un Recorrido por Ramal');
    expect(terminal('Constitución'), findsOneWidget);
    expect(terminal('Escobar'), findsOneWidget);
    expect(terminal('Tigre'), findsOneWidget);

    // Es una vista previa: ningún colectivo en vivo y la Línea no está en la fila.
    expect(algunColectivo, findsNothing);
    expect(pedidosDeColectivos(app), isEmpty);
    expect(fila(tester), ['Ecobici']);

    await tester.tap(enFicha(find.byTooltip('Cerrar')));
    await tester.pumpAndSettle();
    expect(recorridosDeColectivo(tester), 0);
    expect(terminal('Escobar'), findsNothing);
    semantics.dispose();
  });

  testWidgets('enter en el buscador abre la ficha de la Línea de Colectivo', (tester) async {
    await openWithColectivos(tester);
    await buscar(tester, '152');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(enFicha(find.text('Línea 152')), findsOneWidget);
    expect(enFicha(find.text('152 · La Boca – Olivos')), findsOneWidget);
  });

  testWidgets('al agregarla aparecen sus colectivos de todos los Ramales, sin importar el zoom, y su botón azul',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final app = await openWithColectivos(tester);
    await abrirDesdeElBuscador(tester, 'Línea 60');
    await tester.tap(enFicha(find.text('Agregar a Mis líneas')));
    await tester.pumpAndSettle();

    expect(enFicha(find.text('Eliminar')), findsOneWidget);
    expect(fila(tester), ['Ecobici', '60']);
    expect(activo(tester, '60'), isTrue);
    final boton60 = tester.widget<ToggleTextButton>(find.widgetWithText(ToggleTextButton, '60'));
    expect(boton60.customization.borderColor, azulColectivo);

    expect(pedidosDeColectivos(app).last.queryParameters, {'line': '60'}, reason: 'toda la ciudad, sin bbox');
    expect(colectivo('60A'), findsOneWidget);
    expect(colectivo('60B'), findsOneWidget);
    expect(colectivo('152'), findsNothing);
    // La cámara se alejó para encuadrar el Recorrido hasta Escobar, y los colectivos siguen.
    expect(MapCamera.of(tester.element(find.byType(PolylineLayer))).zoom, lessThan(13));

    // Con la ficha cerrada no se dibujan sus Recorridos, pero sí sus colectivos.
    await tester.tap(enFicha(find.byTooltip('Cerrar')));
    await tester.pumpAndSettle();
    expect(recorridosDeColectivo(tester), 0);
    expect(colectivo('60A'), findsOneWidget);
    expect(colectivo('60B'), findsOneWidget);
    expect(activo(tester, '60'), isFalse);
    semantics.dispose();
  });

  testWidgets('el mapa muestra solo los colectivos de mis Líneas, pedidos todos juntos', (tester) async {
    final semantics = tester.ensureSemantics();
    final app = await openWithColectivos(tester);

    // Ya no hay capa de colectivos por zona: sin Líneas de Colectivo no se pide ninguno.
    expect(fila(tester), ['Ecobici']);
    expect(find.text('Colectivos'), findsNothing);
    expect(pedidosDeColectivos(app), isEmpty);
    expect(find.text('Tu mapa está vacío'), findsOneWidget);

    await agregarColectivos(tester, ['60', '152']);
    expect(find.text('Tu mapa está vacío'), findsNothing);
    expect(fila(tester), ['Ecobici', '60', '152']);
    expect(pedidosDeColectivos(app).last.queryParameters, {'line': '60,152'});
    expect(colectivo('60A'), findsOneWidget);
    expect(colectivo('60B'), findsOneWidget);
    expect(colectivo('152'), findsOneWidget);
    expect(colectivo('29'), findsNothing, reason: 'la 29 no está en Mis líneas');
    expect(recorridosDeColectivo(tester), 0);

    // Una Línea eliminada deja de verse enseguida, y el próximo pedido ya no la incluye.
    await openMisLineas(tester);
    await tester.tap(find.byTooltip('Eliminar el 60'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(colectivo('60A'), findsNothing);
    expect(colectivo('152'), findsOneWidget);
    expect(pedidosDeColectivos(app).last.queryParameters, {'line': '152'});
    semantics.dispose();
  });

  testWidgets('la pantalla Mis líneas muestra el grupo Colectivo con su "+" y su ✕ con deshacer', (tester) async {
    final semantics = tester.ensureSemantics();
    await openWithColectivos(tester);
    await openMisLineas(tester);
    expect(find.text('Colectivo'), findsOneWidget);
    expect(find.text('Todavía no agregaste líneas de Colectivo.'), findsOneWidget);

    // El "+" del grupo abre el buscador de Colectivo con todo el catálogo.
    await tester.tap(find.byTooltip('Agregar línea de Colectivo'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Buscar línea de Colectivo'), findsOneWidget);
    expect(listadas(tester), ['Línea 29', 'Línea 60', 'Línea 152']);
    expect(resultado('Línea D'), findsNothing, reason: 'filtrado por Colectivo');
    await tester.pageBack();
    await tester.pumpAndSettle();

    for (final l in ['60', '152']) {
      await addColectivoLine(tester, l);
    }
    expect(listadas(tester), ['Línea 60', 'Línea 152']);

    await tester.tap(find.byTooltip('Eliminar el 60'));
    await tester.pumpAndSettle();
    expect(find.text('Eliminaste el 60'), findsOneWidget);
    expect(listadas(tester), ['Línea 152']);
    await tester.tap(find.text('Deshacer'));
    await tester.pumpAndSettle();
    expect(listadas(tester), ['Línea 60', 'Línea 152']);

    // Sin Líneas, el grupo sigue con su "+".
    await tester.tap(find.byTooltip('Eliminar el 60'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Eliminar el 152'));
    await tester.pumpAndSettle();
    expect(listadas(tester), isEmpty);
    expect(find.text('Colectivo'), findsOneWidget);
    expect(find.byTooltip('Agregar línea de Colectivo'), findsOneWidget);

    // El "+" general también ofrece Colectivo.
    await tester.tap(find.byTooltip('Agregar línea'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('Colectivo')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Buscar línea de Colectivo'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('"Eliminar" en la ficha deja de dibujar el Recorrido en el acto, y "Deshacer" la devuelve',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await openWithColectivos(tester);
    await agregarColectivos(tester, ['152', '60']);
    await tester.tap(boton('60'));
    await tester.pumpAndSettle();
    expect(recorridosDeColectivo(tester), 2);

    await tester.tap(enFicha(find.text('Eliminar')));
    await tester.pump();
    expect(ficha, findsOneWidget, reason: 'la ficha todavía está bajando');
    expect(recorridosDeColectivo(tester), 0);
    expect(terminal('Escobar'), findsNothing);

    await tester.pumpAndSettle();
    expect(ficha, findsNothing);
    expect(find.text('Eliminaste el 60'), findsOneWidget);
    expect(fila(tester), ['Ecobici', '152']);
    expect(colectivo('60A'), findsNothing);

    await tester.tap(find.text('Deshacer'));
    await tester.pumpAndSettle();
    expect(fila(tester), ['Ecobici', '152', '60']);
    expect(colectivo('60A'), findsOneWidget);
    expect(recorridosDeColectivo(tester), 0);
    semantics.dispose();
  });

  testWidgets('un Ramal sin Terminales ni Recorrido no rompe la ficha', (tester) async {
    await openWithColectivos(tester);
    await abrirDesdeElBuscador(tester, 'Línea 29');
    expect(enFicha(find.text('Línea 29')), findsOneWidget);
    expect(enFicha(find.text('29')), findsOneWidget);
    expect(recorridosDeColectivo(tester), 0);
    expect(tester.takeException(), isNull);

    await tester.tap(enFicha(find.text('Agregar a Mis líneas')));
    await tester.pumpAndSettle();
    expect(fila(tester), ['Ecobici', '29']);
  });
}
