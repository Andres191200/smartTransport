import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:smart_transport/data/transit_api.dart';
import 'package:smart_transport/main.dart';
import 'package:smart_transport/settings/theme_controller.dart';

/// Respuestas vacías de cada endpoint del backend: la app arranca sin transporte que mostrar.
Map<String, Object> emptyBackendResponses() => {
      '/v1/buses': {'mode': 'live', 'vehicles': <Object>[], 'truncated': false},
      '/v1/subway/lines': {'mode': 'live', 'lines': <Object>[]},
      '/v1/subway/alerts': {'mode': 'live', 'alerts': <Object>[]},
      '/v1/subway/arrivals': {'mode': 'live', 'arrivals': <Object>[]},
      '/v1/ecobici/stations': {'mode': 'live', 'stations': <Object>[]},
    };

/// Monta la app entera como la usa una persona, sin red: el backend es un [MockClient],
/// las preferencias viven en memoria y el mapa base no descarga nada.
///
/// Las preferencias se guardan en [prefs] entre una apertura y otra, así que llamar dos
/// veces a [open] simula cerrar la app y volver a abrirla en el mismo teléfono.
class AppHarness {
  /// [responses] reemplaza las respuestas del backend por ruta (p. ej. `/v1/subway/lines`);
  /// las rutas que no se pasan responden vacías (ver [emptyBackendResponses]).
  AppHarness({Map<String, Object> responses = const {}})
      : responses = {...emptyBackendResponses(), ...responses};

  /// Cuerpo JSON que devuelve el backend falso para cada ruta. Se puede cambiar entre aperturas.
  final Map<String, Object> responses;

  /// Pedidos que la app le hizo al backend, en orden.
  final List<Uri> requests = [];

  /// Preferencias del "teléfono".
  final InMemorySharedPreferencesAsync prefs = InMemorySharedPreferencesAsync.empty();

  late final TransitApi api = TransitApi(baseUrl: 'http://backend.test', client: MockClient(_handle));

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request.url);
    final body = responses[request.url.path];
    if (body == null) {
      return http.Response(jsonEncode({'error': 'Ruta desconocida: ${request.url.path}'}), 404);
    }
    return http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  /// Abre la app (o la vuelve a abrir) y espera a que se dibuje y carguen los datos.
  Future<void> open(WidgetTester tester) async {
    // La fuente de los tests dibuja cada letra como un cuadrado del ancho de la fuente: en una
    // pantalla angosta la atribución del mapa ("flutter_map | © OpenFreeMap © ...") no entra.
    tester.view
      ..physicalSize = const Size(1200, 2000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    SharedPreferencesAsyncPlatform.instance = prefs;
    final theme = await ThemeController.load();
    await tester.pumpWidget(SmartTransportApp(
      key: UniqueKey(), // otra apertura arranca de cero, con estado nuevo
      api: api,
      theme: theme,
      baseMap: const FakeBaseMap(),
    ));
    await tester.pumpAndSettle();
  }
}

/// Reemplazo del mapa base para tests: no dibuja nada y no usa la red.
class FakeBaseMap extends StatelessWidget {
  const FakeBaseMap({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
