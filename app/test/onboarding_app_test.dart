import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/mapa_steps.dart';
import 'support/mis_lineas_steps.dart';
import 'support/onboarding_steps.dart';

final _buscadorDelMapa = find.widgetWithText(TextField, 'Buscar línea');

void main() {
  testWidgets('primera apertura: el Onboarding deja las Líneas elegidas en el mapa y no vuelve a aparecer',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final app = await openPorPrimeraVez(tester);
    expect(pantallaDeMedios, findsOneWidget);
    expect(_buscadorDelMapa, findsNothing);

    await tocarMedio(tester, 'Subte');
    await tocarMedio(tester, 'Ecobici');
    expect(progreso(1, 3), findsOneWidget);
    await continuar(tester);

    expect(pantallaDeLineasDeSubte, findsOneWidget);
    expect(progreso(2, 3), findsOneWidget);
    await tocarLineaDeSubte(tester, 'Línea H');
    await tocarLineaDeSubte(tester, 'Línea A');
    await continuar(tester);

    expect(pantallaDeUbicacion, findsOneWidget);
    expect(progreso(3, 3), findsOneWidget);
    await continuar(tester);

    // En el mapa: las Líneas en el orden en que se eligieron y Ecobici prendida.
    expect(_buscadorDelMapa, findsOneWidget);
    expect(fila(tester), ['Ecobici', 'H', 'A']);
    expect(activo(tester, 'Ecobici'), isTrue);
    expect(station('Lima'), findsOneWidget, reason: 'se dibuja la A');

    // Las siguientes aperturas van directo al mapa, con lo elegido.
    await app.open(tester);
    expect(pantallaDeMedios, findsNothing);
    expect(fila(tester), ['Ecobici', 'H', 'A']);
    expect(activo(tester, 'Ecobici'), isTrue);

    // Mis líneas tiene el grupo de los Medios elegidos: Subte (y Ecobici), no Colectivo.
    await openMisLineas(tester);
    expect(find.byTooltip('Agregar línea de Subte'), findsOneWidget);
    expect(find.byTooltip('Agregar línea de Colectivo'), findsNothing);
    semantics.dispose();
  });

  testWidgets('"Continuar" en Medios exige al menos un Medio', (tester) async {
    await openPorPrimeraVez(tester);
    expect(continuarHabilitado(tester), isFalse);

    await tocarMedio(tester, 'Ecobici');
    expect(continuarHabilitado(tester), isTrue);

    await tocarMedio(tester, 'Ecobici');
    expect(continuarHabilitado(tester), isFalse);
    await tester.tap(botonContinuar);
    await tester.pumpAndSettle();
    expect(pantallaDeMedios, findsOneWidget);
  });

  testWidgets('la pantalla de Líneas de Subte aparece solo con Subte y su botón alterna', (tester) async {
    final semantics = tester.ensureSemantics();
    await openPorPrimeraVez(tester);

    // Sin Subte, de Medios se pasa a la ubicación.
    await tocarMedio(tester, 'Ecobici');
    expect(progreso(1, 2), findsOneWidget);
    await continuar(tester);
    expect(pantallaDeUbicacion, findsOneWidget);
    expect(progreso(2, 2), findsOneWidget);

    // Volver conserva lo elegido. El "atrás" del teléfono también vuelve.
    await volver(tester);
    expect(pantallaDeMedios, findsOneWidget);
    expect(continuarHabilitado(tester), isTrue);
    await tocarMedio(tester, 'Subte');
    await continuar(tester);
    expect(pantallaDeLineasDeSubte, findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(pantallaDeMedios, findsOneWidget);
    await continuar(tester);

    expect(botonDespues, findsOneWidget);
    expect(botonContinuar, findsNothing);
    await tocarLineaDeSubte(tester, 'Línea D');
    expect(botonContinuar, findsOneWidget);
    expect(botonDespues, findsNothing);
    await tocarLineaDeSubte(tester, 'Línea D');
    expect(botonDespues, findsOneWidget);
    expect(botonContinuar, findsNothing);

    await tocar(tester, botonDespues);
    expect(pantallaDeUbicacion, findsOneWidget);
    await continuar(tester);

    // Subte quedó elegido sin Líneas: el mapa no tiene Líneas, pero Mis líneas tiene su grupo.
    expect(fila(tester), ['Ecobici']);
    await openMisLineas(tester);
    expect(find.byTooltip('Agregar línea de Subte'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('"Saltar" deja el mapa vacío y Ecobici apagada; las Líneas se agregan desde Mis líneas',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final app = await openPorPrimeraVez(tester);
    await tocarMedio(tester, 'Subte');
    await saltar(tester);

    expect(find.text('Agregar líneas'), findsOneWidget);
    expect(fila(tester), ['Ecobici']);
    expect(activo(tester, 'Ecobici'), isFalse);
    expect(app.pedidosDeUbicacion, 0, reason: 'sin pasar por la pantalla de ubicación no se pide');

    await app.open(tester);
    expect(pantallaDeMedios, findsNothing);
    expect(find.text('Agregar líneas'), findsOneWidget);

    // Sin Medios elegidos, Mis líneas tiene solo el grupo Ecobici; el "+" general agrega igual.
    await tester.tap(find.text('Agregar líneas'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Agregar línea de Subte'), findsNothing);
    expect(find.byTooltip('Agregar línea de Colectivo'), findsNothing);
    expect(find.text('Mostrar estaciones al abrir la app'), findsOneWidget);

    await tester.tap(find.byTooltip('Agregar línea'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Subte'));
    await tester.pumpAndSettle();
    await tester.tap(resultado('Línea D'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Agregar línea de Subte'), findsOneWidget, reason: 'aparece el grupo Subte');
    expect(find.byTooltip('Eliminar la D'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(fila(tester), ['Ecobici', 'D']);
    semantics.dispose();
  });

  testWidgets('volver y desmarcar Subte descarta las Líneas de Subte elegidas', (tester) async {
    final semantics = tester.ensureSemantics();
    await openPorPrimeraVez(tester);
    await tocarMedio(tester, 'Subte');
    await tocarMedio(tester, 'Ecobici');
    await continuar(tester);
    await tocarLineaDeSubte(tester, 'Línea D');
    expect(botonContinuar, findsOneWidget);

    await volver(tester);
    await tocarMedio(tester, 'Subte'); // lo desmarca
    await tocarMedio(tester, 'Subte'); // y lo vuelve a marcar: la D ya no está elegida
    await continuar(tester);
    expect(botonDespues, findsOneWidget);

    await tocarLineaDeSubte(tester, 'Línea D');
    await volver(tester);
    await tocarMedio(tester, 'Subte');
    await continuar(tester);
    expect(pantallaDeUbicacion, findsOneWidget);
    await continuar(tester);

    expect(fila(tester), ['Ecobici']);
    await openMisLineas(tester);
    expect(find.byTooltip('Agregar línea de Subte'), findsNothing);
    semantics.dispose();
  });

  testWidgets('cerrar la app a mitad del Onboarding lo hace empezar de nuevo, sin nada guardado', (tester) async {
    final semantics = tester.ensureSemantics();
    final app = await openPorPrimeraVez(tester);
    await tocarMedio(tester, 'Subte');
    await tocarMedio(tester, 'Ecobici');
    await continuar(tester);
    await tocarLineaDeSubte(tester, 'Línea D');
    await continuar(tester);
    expect(pantallaDeUbicacion, findsOneWidget);

    await app.open(tester);
    expect(pantallaDeMedios, findsOneWidget);
    expect(continuarHabilitado(tester), isFalse, reason: 'ningún Medio marcado');

    // Saltando, se ve que no había quedado nada: ni la D ni Ecobici.
    await saltar(tester);
    expect(fila(tester), ['Ecobici']);
    expect(activo(tester, 'Ecobici'), isFalse);
    semantics.dispose();
  });

  testWidgets('la pantalla de ubicación explica el permiso antes de pedirlo, y rechazarlo no rompe nada',
      (tester) async {
    final app = await openPorPrimeraVez(tester);
    app.concedeLaUbicacion = false;
    await tocarMedio(tester, 'Ecobici');
    await continuar(tester);

    expect(find.textContaining('mostrarte dónde estás en el mapa'), findsOneWidget);
    expect(find.textContaining('Si no lo das, la app funciona igual'), findsOneWidget);
    expect(app.pedidosDeUbicacion, 0, reason: 'primero se explica');

    await continuar(tester);
    expect(app.pedidosDeUbicacion, 1);
    expect(_buscadorDelMapa, findsOneWidget);
    expect(find.byTooltip('Mi ubicación'), findsOneWidget);
    expect(activo(tester, 'Ecobici'), isTrue);

    await app.open(tester);
    expect(_buscadorDelMapa, findsOneWidget);
    expect(app.pedidosDeUbicacion, 1, reason: 'no se vuelve a pedir al abrir la app');
  });
}
