import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'app_harness.dart';
import 'mapa_steps.dart';

// Pasos del Onboarding que usan los tests de la app entera.

/// Abre la app por primera vez en un teléfono nuevo, con el Subte de [subwayLines].
Future<AppHarness> openPorPrimeraVez(WidgetTester tester) async {
  final app = AppHarness(onboardingCompletado: false, responses: {'/v1/subway/lines': subwayLines()});
  await app.open(tester);
  return app;
}

/// La pantalla de Medios, la primera del Onboarding.
final pantallaDeMedios = find.text('¿Qué medios usás?');
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
