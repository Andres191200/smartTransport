import 'package:material_ui/material_ui.dart';

import 'config.dart';
import 'data/transit_api.dart';
import 'ui/map_screen.dart';

void main() {
  runApp(SmartTransportApp(api: TransitApi(baseUrl: AppConfig.apiBaseUrl)));
}

class SmartTransportApp extends StatelessWidget {
  const SmartTransportApp({super.key, required this.api});

  final TransitApi api;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF0B5CAD);
    return MaterialApp(
      title: 'Smart Transport',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: seed)),
      darkTheme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark)),
      home: MapScreen(api: api),
    );
  }
}
