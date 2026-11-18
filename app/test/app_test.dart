import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app_harness.dart';

void main() {
  testWidgets('la app abre en el mapa, con la barra superior y el menú lateral', (tester) async {
    final app = AppHarness();
    await app.open(tester);

    expect(find.widgetWithText(TextField, 'Buscar línea de colectivo'), findsOneWidget);
    expect(find.byTooltip('Estado del subte'), findsOneWidget);
    expect(find.byTooltip('Mi ubicación'), findsOneWidget);
    expect(app.requests.map((u) => u.path), contains('/v1/subway/lines'));

    await tester.tap(find.byTooltip('Menú'));
    await tester.pumpAndSettle();
    expect(find.text('Modo oscuro'), findsOneWidget);
  });

  testWidgets('al volver a abrir la app se mantiene lo guardado en el teléfono', (tester) async {
    final app = AppHarness();
    await app.open(tester);
    await tester.tap(find.byTooltip('Menú'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Modo oscuro'));
    await tester.pumpAndSettle();

    await app.open(tester);

    final context = tester.element(find.byType(Scaffold).first);
    expect(Theme.of(context).brightness, Brightness.dark);
  });
}
