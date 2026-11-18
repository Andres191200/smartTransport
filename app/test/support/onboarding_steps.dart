import 'dart:ui' show CheckedState;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'app_harness.dart';
import 'colectivo_steps.dart';
import 'mapa_steps.dart';

// Pasos del Onboarding que usan los tests de la app entera.

/// Abre la app por primera vez en un teléfono nuevo, con el Subte de [subwayLines] y el Colectivo
/// de [busLines]. [responses] reemplaza otras respuestas del backend (ver [AppHarness]).
Future<AppHarness> openPorPrimeraVez(WidgetTester tester, {Map<String, Object> responses = const {}}) async {
  final app = AppHarness(onboardingCompletado: false, responses: {
    '/v1/subway/lines': subwayLines(),
    '/v1/buses/lines': busLines(),
    '/v1/buses/paths': busPaths,
    '/v1/buses': buses(),
    ...responses,
  });
  await app.open(tester);
  return app;
}

/// La pantalla de Medios, la primera del Onboarding.
final pantallaDeMedios = find.text('¿Qué medios usás?');
final pantallaDeLineasDeColectivo = find.text('¿Qué líneas de Colectivo usás?');
final pantallaDeLineasDeSubte = find.text('¿Qué líneas de Subte usás?');
final pantallaDeUbicacion = find.text('Tu ubicación');

/// La card de un Medio ("Colectivo", "Subte" o "Ecobici").
Finder cardDeMedio(String medio) => find.widgetWithText(Card, medio);

Future<void> tocarMedio(WidgetTester tester, String medio) async {
  await tester.tap(cardDeMedio(medio));
  await tester.pumpAndSettle();
}

/// Marca o desmarca una Línea de Subte por su nombre ("Línea D" o "Premetro"; necesita
/// `tester.ensureSemantics()`).
Future<void> tocarLineaDeSubte(WidgetTester tester, String nombre) async {
  await tester.tap(find.bySemanticsLabel(nombre));
  await tester.pumpAndSettle();
}

/// Escribe en el buscador de la pantalla de Líneas de Colectivo.
Future<void> buscarColectivo(WidgetTester tester, String text) async {
  await tester.enterText(find.widgetWithText(TextField, 'Buscar línea de Colectivo'), text);
  await tester.pumpAndSettle();
}

/// Busca una Línea de Colectivo ("60") y marca o desmarca su resultado.
Future<void> tocarLineaDeColectivo(WidgetTester tester, String numero) async {
  await buscarColectivo(tester, numero);
  await tester.tap(resultado('Línea $numero'));
  await tester.pumpAndSettle();
}

/// Si el resultado de esa Línea ("Línea 60") está marcado (necesita `tester.ensureSemantics()`).
bool resultadoMarcado(WidgetTester tester, String nombre) =>
    tester.getSemantics(resultado(nombre)).flagsCollection.isChecked == CheckedState.isTrue;

/// Las Líneas de Colectivo elegidas que se ven arriba del buscador ("Línea 60"), en orden.
List<String> colectivosElegidos(WidgetTester tester) => [
      for (final chip in tester.widgetList<InputChip>(find.byType(InputChip)))
        if (chip.label case Text(:final data?)) data,
    ];

final botonContinuar = find.widgetWithText(FilledButton, 'Continuar');
final botonDespues = find.widgetWithText(OutlinedButton, 'Prefiero hacerlo después');

bool continuarHabilitado(WidgetTester tester) => tester.widget<FilledButton>(botonContinuar).onPressed != null;

Future<void> tocar(WidgetTester tester, Finder boton) async {
  await tester.tap(boton);
  await tester.pumpAndSettle();
}

Future<void> continuar(WidgetTester tester) => tocar(tester, botonContinuar);

Future<void> volver(WidgetTester tester) => tocar(tester, find.byTooltip('Volver'));

Future<void> saltar(WidgetTester tester) => tocar(tester, find.widgetWithText(TextButton, 'Saltar'));

/// Los puntos de progreso (necesita `tester.ensureSemantics()`).
Finder progreso(int paso, int total) => find.bySemanticsLabel('Paso $paso de $total');
