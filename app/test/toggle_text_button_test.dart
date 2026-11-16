import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:smart_transport/ui/toggle_text_button.dart';

void main() {
  BorderSide borderOf(WidgetTester tester) {
    final material = tester.widget<Material>(
      find.descendant(of: find.byType(ToggleTextButton), matching: find.byType(Material)).first,
    );
    return (material.shape! as StadiumBorder).side;
  }

  Future<void> pump(WidgetTester tester, ToggleTextButton button, {ThemeData? theme}) =>
      tester.pumpWidget(MaterialApp(theme: theme, home: Scaffold(body: Center(child: button))));

  testWidgets('activo: borde gris oscuro por defecto', (tester) async {
    final theme = ThemeData();
    await pump(tester, ToggleTextButton(text: 'Subte', isActive: true, onTap: () {}), theme: theme);

    expect(find.text('Subte'), findsOneWidget);
    expect(borderOf(tester).color, ToggleTextButton.defaultBorderColor(theme.colorScheme));
    expect(borderOf(tester).width, ToggleTextButton.borderWidth);
  });

  testWidgets('inactivo: sin borde visible y mismo tamaño que activo', (tester) async {
    await pump(tester, ToggleTextButton(text: 'Subte', isActive: true, onTap: () {}));
    final activeSize = tester.getSize(find.byType(ToggleTextButton));

    await pump(tester, ToggleTextButton(text: 'Subte', isActive: false, onTap: () {}));
    expect(borderOf(tester).color, Colors.transparent);
    expect(tester.getSize(find.byType(ToggleTextButton)), activeSize);
  });

  testWidgets('customization cambia el color del borde activo', (tester) async {
    const red = Color(0xFFFF0000);
    await pump(
      tester,
      ToggleTextButton(
        text: 'Ecobici',
        isActive: true,
        onTap: () {},
        customization: const ToggleTextButtonCustomization(borderColor: red),
      ),
    );
    expect(borderOf(tester).color, red);
  });

  testWidgets('ícono opcional y tipografía de chip (labelLarge)', (tester) async {
    final theme = ThemeData();
    await pump(tester, ToggleTextButton(text: 'Subte', isActive: false, onTap: () {}), theme: theme);
    expect(find.byType(Icon), findsNothing);

    await pump(
      tester,
      ToggleTextButton(text: 'Subte', icon: Icons.subway, isActive: false, onTap: () {}),
      theme: theme,
    );
    expect(find.byIcon(Icons.subway), findsOneWidget);
    final style = tester.widget<Text>(find.text('Subte')).style!;
    final labelLarge = Theme.of(tester.element(find.text('Subte'))).textTheme.labelLarge!;
    expect(style.fontSize, labelLarge.fontSize);
    expect(style.fontWeight, labelLarge.fontWeight);
  });

  testWidgets('onTap se llama al tocar', (tester) async {
    var taps = 0;
    await pump(tester, ToggleTextButton(text: 'Colectivos', isActive: false, onTap: () => taps++));
    await tester.tap(find.text('Colectivos'));
    expect(taps, 1);
  });
}
