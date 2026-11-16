import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:smart_transport/settings/theme_controller.dart';
import 'package:smart_transport/ui/app_drawer.dart';

void main() {
  setUp(() => SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty());

  group('ThemeController', () {
    test('sin elección previa sigue al sistema', () async {
      final theme = await ThemeController.load();
      expect(theme.mode, ThemeMode.system);
      expect(theme.isDark(Brightness.dark), isTrue);
      expect(theme.isDark(Brightness.light), isFalse);
    });

    test('la elección se guarda y se recupera al volver a abrir la app', () async {
      final theme = await ThemeController.load();
      await theme.setDark(true);
      expect(theme.isDark(Brightness.light), isTrue);

      final reopened = await ThemeController.load();
      expect(reopened.mode, ThemeMode.dark);
    });
  });

  testWidgets('el switch del drawer cambia el modo', (tester) async {
    final theme = await ThemeController.load();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AppDrawer(theme: theme))));

    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isFalse);
    await tester.tap(find.text('Modo oscuro'));
    await tester.pump();

    expect(theme.mode, ThemeMode.dark);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);

    await tester.tap(find.text('Modo oscuro'));
    await tester.pump();
    expect(theme.mode, ThemeMode.light);
  });
}
