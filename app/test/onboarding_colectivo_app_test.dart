import 'package:flutter_test/flutter_test.dart';
import 'package:smart_transport/settings/mis_lineas.dart';

import 'support/colectivo_steps.dart';
import 'support/mapa_steps.dart';
import 'support/mis_lineas_steps.dart';
import 'support/onboarding_steps.dart';

void main() {
  testWidgets('con Colectivo y Subte: Medios → Colectivo → Subte → ubicación, y en el mapa los colectivos de '
      'todos los Ramales de las Líneas elegidas', (tester) async {
    final semantics = tester.ensureSemantics();
    await openPorPrimeraVez(tester);
    await tocarMedio(tester, 'Colectivo');
    await tocarMedio(tester, 'Subte');
    expect(progreso(1, 4), findsOneWidget);
    await continuar(tester);

    expect(pantallaDeLineasDeColectivo, findsOneWidget);
    expect(progreso(2, 4), findsOneWidget);
    expect(botonDespues, findsOneWidget);

    // Se busca en el catálogo y se marcan varias Líneas, que quedan a la vista aunque cambie la búsqueda.
    await buscarColectivo(tester, '60');
    expect(resultado('Línea 60'), findsOneWidget);
    expect(resultado('Línea 152'), findsNothing);
    expect(resultadoMarcado(tester, 'Línea 60'), isFalse);
    await tocarLineaDeColectivo(tester, '60');
    expect(resultadoMarcado(tester, 'Línea 60'), isTrue);
    await tocarLineaDeColectivo(tester, '152');
    expect(resultado('Línea 60'), findsNothing);
    expect(colectivosElegidos(tester), ['Línea 60', 'Línea 152']);
    await continuar(tester);

    expect(pantallaDeLineasDeSubte, findsOneWidget);
    expect(progreso(3, 4), findsOneWidget);
    await tocarLineaDeSubte(tester, 'Línea D');
    await continuar(tester);

    expect(pantallaDeUbicacion, findsOneWidget);
    expect(progreso(4, 4), findsOneWidget);
    await continuar(tester);

    // En el mapa: las Líneas en Mis líneas, y los colectivos en vivo de todos sus Ramales.
    expect(fila(tester), ['Ecobici', '60', '152', 'D']);
    expect(colectivo('60A'), findsOneWidget);
    expect(colectivo('60B'), findsOneWidget);
    expect(colectivo('152'), findsOneWidget);
    expect(colectivo('29'), findsNothing);
    expect((await MisLineas.load()).lineas, [
      const Linea(Medio.colectivo, '60'),
      const Linea(Medio.colectivo, '152'),
      const Linea(Medio.subte, 'D'),
    ]);
    semantics.dispose();
  });

  testWidgets('el botón alterna entre "Prefiero hacerlo después" y "Continuar" al marcar y desmarcar',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await openPorPrimeraVez(tester);
    await tocarMedio(tester, 'Colectivo');
    expect(progreso(1, 3), findsOneWidget);
    await continuar(tester);
    expect(pantallaDeLineasDeColectivo, findsOneWidget);
    expect(botonDespues, findsOneWidget);
    expect(botonContinuar, findsNothing);

    await tocarLineaDeColectivo(tester, '60');
    expect(botonContinuar, findsOneWidget);
    expect(botonDespues, findsNothing);
    await tocarLineaDeColectivo(tester, '60'); // desde el resultado
    expect(botonDespues, findsOneWidget);
    expect(colectivosElegidos(tester), isEmpty);

    await tocarLineaDeColectivo(tester, '60');
    await tocar(tester, find.byTooltip('Quitar Línea 60')); // desde las elegidas
    expect(botonDespues, findsOneWidget);
    expect(resultadoMarcado(tester, 'Línea 60'), isFalse);

    await tocar(tester, botonDespues);
    expect(pantallaDeUbicacion, findsOneWidget);
    await continuar(tester);

    // Colectivo quedó elegido sin Líneas: el mapa no tiene Líneas, pero Mis líneas tiene su grupo.
    expect(find.text('Agregar líneas'), findsOneWidget);
    await openMisLineas(tester);
    expect(find.byTooltip('Agregar línea de Colectivo'), findsOneWidget);
    expect(find.byTooltip('Agregar línea de Subte'), findsNothing);
    semantics.dispose();
  });

  testWidgets('volver y desmarcar Colectivo descarta las Líneas de Colectivo elegidas', (tester) async {
    final semantics = tester.ensureSemantics();
    await openPorPrimeraVez(tester);
    await tocarMedio(tester, 'Colectivo');
    await tocarMedio(tester, 'Subte');
    await continuar(tester);
    await tocarLineaDeColectivo(tester, '60');
    await continuar(tester);
    expect(pantallaDeLineasDeSubte, findsOneWidget);

    await volver(tester);
    expect(colectivosElegidos(tester), ['Línea 60'], reason: 'volver conserva lo elegido');
    await volver(tester);
    await tocarMedio(tester, 'Colectivo'); // lo desmarca
    await tocarMedio(tester, 'Colectivo'); // y lo vuelve a marcar: el 60 ya no está elegido
    await continuar(tester);
    expect(colectivosElegidos(tester), isEmpty);
    expect(botonDespues, findsOneWidget);

    await tocarLineaDeColectivo(tester, '152');
    await volver(tester);
    await tocarMedio(tester, 'Colectivo');
    await continuar(tester);
    expect(pantallaDeLineasDeSubte, findsOneWidget);
    expect(progreso(2, 3), findsOneWidget);
    await tocar(tester, botonDespues);
    await continuar(tester);

    expect(fila(tester), ['Ecobici']);
    expect(algunColectivo, findsNothing);
    final guardado = await MisLineas.load();
    expect(guardado.lineas, isEmpty);
    expect(guardado.medios, {Medio.subte});
    semantics.dispose();
  });

  testWidgets('si el catálogo no llega, se puede reintentar o seguir con "Prefiero hacerlo después"',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final app = await openPorPrimeraVez(tester, responses: {'/v1/buses/lines': (Uri _) => null});
    await tocarMedio(tester, 'Colectivo');
    await continuar(tester);

    expect(find.text('Reintentar'), findsOneWidget);
    expect(resultado('Línea 60'), findsNothing);
    expect(botonDespues, findsOneWidget);

    // Vuelve a fallar: sigue el error.
    await tocar(tester, find.text('Reintentar'));
    expect(find.text('Reintentar'), findsOneWidget);

    // Ahora llega.
    app.responses['/v1/buses/lines'] = busLines();
    await tocar(tester, find.text('Reintentar'));
    expect(find.text('Reintentar'), findsNothing);
    await tocarLineaDeColectivo(tester, '60');
    await continuar(tester);
    await continuar(tester);
    expect(fila(tester), ['Ecobici', '60']);
    semantics.dispose();
  });

  testWidgets('sin catálogo, "Prefiero hacerlo después" sigue hasta el mapa', (tester) async {
    await openPorPrimeraVez(tester, responses: {'/v1/buses/lines': (Uri _) => null});
    await tocarMedio(tester, 'Colectivo');
    await continuar(tester);
    expect(find.text('Reintentar'), findsOneWidget);

    await tocar(tester, botonDespues);
    expect(pantallaDeUbicacion, findsOneWidget);
    await continuar(tester);
    expect(find.text('Agregar líneas'), findsOneWidget);
    expect((await MisLineas.load()).medios, {Medio.colectivo});
  });

  testWidgets('cerrar la app con Líneas de Colectivo elegidas no guarda nada', (tester) async {
    final semantics = tester.ensureSemantics();
    final app = await openPorPrimeraVez(tester);
    await tocarMedio(tester, 'Colectivo');
    await continuar(tester);
    await tocarLineaDeColectivo(tester, '60');
    await continuar(tester);
    expect(pantallaDeUbicacion, findsOneWidget);

    await app.open(tester);
    expect(pantallaDeMedios, findsOneWidget);
    final guardado = await MisLineas.load();
    expect(guardado.onboardingCompletado, isFalse);
    expect(guardado.lineas, isEmpty);
    expect(guardado.medios, isEmpty);
    semantics.dispose();
  });
}
