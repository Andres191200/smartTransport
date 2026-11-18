import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:smart_transport/ui/fila_de_botones.dart';

/// Una fila de 300 de ancho con [count] botones de 100.
Widget fila(int count) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            child: FilaDeBotones(
              children: [
                for (var i = 0; i < count; i++)
                  SizedBox(width: 100, height: 40, child: TextButton(onPressed: () {}, child: Text('$i'))),
              ],
            ),
          ),
        ),
      ),
    );

final _degradado = find.byKey(FilaDeBotones.degradadoKey);

void main() {
  testWidgets('sin botones fuera de pantalla no hay degradado', (tester) async {
    await tester.pumpWidget(fila(2));
    await tester.pumpAndSettle();
    expect(_degradado, findsNothing);
  });

  testWidgets('el degradado aparece si hay botones a la derecha y se va al llegar al final', (tester) async {
    await tester.pumpWidget(fila(6));
    await tester.pumpAndSettle();
    expect(_degradado, findsOneWidget);

    await tester.drag(find.byType(FilaDeBotones), const Offset(-1000, 0));
    await tester.pumpAndSettle();
    expect(_degradado, findsNothing);
    expect(find.text('5'), findsOneWidget);

    // Volviendo un poco, vuelve a haber botones a la derecha.
    await tester.drag(find.byType(FilaDeBotones), const Offset(150, 0));
    await tester.pumpAndSettle();
    expect(_degradado, findsOneWidget);
  });

  testWidgets('el degradado aparece al sumarse botones, sin deslizar', (tester) async {
    await tester.pumpWidget(fila(2));
    await tester.pumpAndSettle();
    expect(_degradado, findsNothing);

    await tester.pumpWidget(fila(5));
    await tester.pumpAndSettle();
    expect(_degradado, findsOneWidget);

    await tester.pumpWidget(fila(2));
    await tester.pumpAndSettle();
    expect(_degradado, findsNothing);
  });
}
