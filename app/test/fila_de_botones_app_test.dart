import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:smart_transport/ui/toggle_text_button.dart';

import 'support/mapa_steps.dart';
import 'support/mis_lineas_steps.dart';

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
    expect(ficha, findsNothing);

    await tester.tap(boton('D'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: ficha, matching: find.text('Línea D')), findsOneWidget);
    expect(find.descendant(of: ficha, matching: find.text('Catedral – Congreso de Tucumán')), findsOneWidget);
    expect(find.descendant(of: ficha, matching: find.text('Eliminar')), findsOneWidget);
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
    expect(find.descendant(of: ficha, matching: find.text('Línea A')), findsOneWidget);
    expect(find.descendant(of: ficha, matching: find.text('Plaza de Mayo – Lima')), findsOneWidget);
    expect(activo(tester, 'A'), isTrue);
    expect(activo(tester, 'D'), isFalse);

    // Tocar de nuevo el botón activo cierra la ficha.
    await tester.tap(boton('A'));
    await tester.pumpAndSettle();
    expect(ficha, findsNothing);
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
        tester.getRect(filaDeBotones).bottom,
        tester.view.physicalSize.width,
        tester.getRect(ficha).top,
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

    await tester.tap(find.descendant(of: ficha, matching: find.text('Eliminar')));
    await tester.pumpAndSettle();
    expect(ficha, findsNothing);
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
    await tester.tap(find.descendant(of: ficha, matching: find.text('Eliminar')));
    await tester.pumpAndSettle();
    await openMisLineas(tester);
    expect(find.text('Línea A'), findsOneWidget);
    expect(find.text('Línea D'), findsNothing);
    expect(find.text('Línea H'), findsOneWidget);
    semantics.dispose();
  });
}
