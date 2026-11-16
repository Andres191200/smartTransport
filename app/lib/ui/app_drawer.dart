import 'package:material_ui/material_ui.dart';

import '../settings/theme_controller.dart';

/// Menú lateral de la app. Por ahora solo tiene el modo oscuro; acá van a ir
/// configuración, versión de la app y soporte.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key, required this.theme});

  final ThemeController theme;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Smart Transport', style: Theme.of(context).textTheme.titleLarge),
            ),
            ListenableBuilder(
              listenable: theme,
              builder: (context, _) => SwitchListTile(
                secondary: const Icon(Icons.dark_mode_outlined),
                title: const Text('Modo oscuro'),
                value: theme.isDark(MediaQuery.platformBrightnessOf(context)),
                onChanged: theme.setDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
