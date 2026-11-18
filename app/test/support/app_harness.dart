import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:smart_transport/data/transit_api.dart';
import 'package:smart_transport/main.dart';
import 'package:smart_transport/settings/mis_lineas.dart';
import 'package:smart_transport/settings/theme_controller.dart';

/// Respuestas vacías de cada endpoint del backend: la app arranca sin transporte que mostrar.
Map<String, Object> emptyBackendResponses() => {
      '/v1/buses': {'mode': 'live', 'vehicles': <Object>[], 'truncated': false},
      '/v1/buses/lines': {'mode': 'live', 'lines': <Object>[]},
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
///
/// Salvo que se pida lo contrario con [onboardingCompletado], el teléfono ya completó el
/// Onboarding eligiendo Colectivo y Subte, sin Líneas y con Ecobici apagada: la app abre directo
/// en el mapa vacío, y la pantalla Mis líneas muestra los grupos Colectivo y Subte con su "+".
class AppHarness {
  /// [responses] reemplaza las respuestas del backend por ruta (p. ej. `/v1/subway/lines`);
  /// las rutas que no se pasan responden vacías (ver [emptyBackendResponses]). Una respuesta
  /// puede ser una función del pedido (p. ej. según `?line=`): si devuelve null, la ruta da 404.
  ///
  /// Con [onboardingCompletado] en false es la primera apertura en un teléfono nuevo: la app
  /// arranca en el Onboarding.
  AppHarness({Map<String, Object> responses = const {}, this.onboardingCompletado = true})
      : responses = {...emptyBackendResponses(), ...responses};

  final bool onboardingCompletado;

  /// Lo que responde el usuario cuando el teléfono le pide el permiso de ubicación.
  bool concedeLaUbicacion = true;

  /// Cuántas veces la app pidió el permiso de ubicación.
  int pedidosDeUbicacion = 0;

  var _abierta = false;

  /// Cuerpo JSON que devuelve el backend falso para cada ruta, o una `Object? Function(Uri)` que
  /// lo arma según el pedido. Se puede cambiar entre aperturas.
  final Map<String, Object> responses;

  /// Rutas que tardan en responder: el backend falso espera a que se complete el Future.
  final Map<String, Future<void>> delays = {};

  /// Pedidos que la app le hizo al backend, en orden.
  final List<Uri> requests = [];

  /// Preferencias del "teléfono".
  final InMemorySharedPreferencesAsync prefs = InMemorySharedPreferencesAsync.empty();

  late final TransitApi api = TransitApi(baseUrl: 'http://backend.test', client: MockClient(_handle));

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request.url);
    await delays[request.url.path];
    final body = switch (responses[request.url.path]) {
      final Object? Function(Uri) responder => responder(request.url),
      final body => body,
    };
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
    if (!_abierta && onboardingCompletado) {
      await (await MisLineas.load()).completarOnboarding(medios: {Medio.colectivo, Medio.subte}, lineas: const []);
    }
    _abierta = true;
    final theme = await ThemeController.load();
    final misLineas = await MisLineas.load();
    await tester.pumpWidget(SmartTransportApp(
      key: UniqueKey(), // otra apertura arranca de cero, con estado nuevo
      api: api,
      theme: theme,
      misLineas: misLineas,
      baseMap: const FakeBaseMap(),
      pedirPermisoDeUbicacion: () async {
        pedidosDeUbicacion++;
        return concedeLaUbicacion;
      },
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
