import 'package:flutter_test/flutter_test.dart';

// Pasos de la pantalla Mis líneas que usan varios tests de la app entera.

Future<void> openMisLineas(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Menú'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Mis líneas'));
  await tester.pumpAndSettle();
}

/// Agrega una Línea de Subte desde la pantalla Mis líneas (necesita `tester.ensureSemantics()`).
Future<void> addSubwayLine(WidgetTester tester, String name) async {
  await tester.tap(find.byTooltip('Agregar línea de Subte'));
  await tester.pumpAndSettle();
  await tester.tap(find.bySemanticsLabel(name == 'Premetro' ? name : 'Línea $name'));
  await tester.pumpAndSettle();
}
