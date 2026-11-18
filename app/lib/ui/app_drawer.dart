import 'package:material_ui/material_ui.dart';

import '../data/catalogo_de_colectivos.dart';
import '../settings/mis_lineas.dart';
import '../settings/theme_controller.dart';
import 'mis_lineas_screen.dart';

/// Menú lateral de la app: Mis líneas y el modo oscuro. Acá van a ir configuración,
/// versión de la app y soporte.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key, required this.theme, required this.misLineas, required this.catalogo});

  final ThemeController theme;
  final MisLineas misLineas;
  final CatalogoDeColectivos catalogo;

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
            ListTile(
              leading: const Icon(Icons.bookmarks_outlined),
              title: const Text('Mis líneas'),
              onTap: () {
                final navigator = Navigator.of(context);
                navigator.pop(); // cierra el menú
                navigator.push(MisLineasScreen.route(misLineas, catalogo));
              },
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
