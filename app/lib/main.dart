import 'package:material_ui/material_ui.dart';

import 'config.dart';
import 'data/transit_api.dart';
import 'settings/mis_lineas.dart';
import 'settings/theme_controller.dart';
import 'ui/base_map.dart';
import 'ui/map_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Se lee antes de arrancar para no mostrar un instante el tema equivocado.
  final (theme, misLineas) = await (ThemeController.load(), MisLineas.load()).wait;
  runApp(SmartTransportApp(api: TransitApi(baseUrl: AppConfig.apiBaseUrl), theme: theme, misLineas: misLineas));
}

class SmartTransportApp extends StatelessWidget {
  const SmartTransportApp({
    super.key,
    required this.api,
    required this.theme,
    required this.misLineas,
    this.baseMap = const BaseMap(),
  });

  final TransitApi api;
  final ThemeController theme;
  final MisLineas misLineas;

  /// Capa del mapa base, debajo del transporte. Los tests la reemplazan por una que no usa la red.
  final Widget baseMap;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF0B5CAD);
    return ListenableBuilder(
      listenable: theme,
      builder: (context, _) => MaterialApp(
        title: 'Smart Transport',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: seed)),
        darkTheme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark)),
        themeMode: theme.mode,
        home: MapScreen(api: api, theme: theme, misLineas: misLineas, baseMap: baseMap),
      ),
    );
  }
}
