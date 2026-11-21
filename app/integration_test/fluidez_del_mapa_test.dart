// Medición de la fluidez del mapa en un teléfono real. No es un test que pase o falle por los
// números: los reporta. Se corre con `tool/fluidez.sh`, en modo profile (ver el README).

import 'package:flutter/gestures.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:smart_transport/data/lineas_de_subte.dart';
import 'package:smart_transport/main.dart';
import 'package:smart_transport/settings/mis_lineas.dart';
import 'package:smart_transport/settings/theme_controller.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import 'datos_fijos.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('arrastrar el mapa y hacer zoom con dos dedos, con Ecobici prendida', (tester) async {
    // Los cuadros se dibujan cuando los pide la app, como fuera de la prueba.
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive;
    await abrirElMapa(tester);
    await esperarElMapaBase(tester);

    await binding.watchPerformance(() => gestos(tester), reportKey: 'mapa');
  });
}

/// Abre la app directo en el mapa, con el mapa base real y la API de [apiConDatosFijos]. En Mis
/// líneas están las Líneas de Subte B y D y la Línea de Colectivo 60, con Ecobici prendida y el
/// tema claro.
Future<void> abrirElMapa(WidgetTester tester) async {
  SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  final misLineas = await MisLineas.load();
  await misLineas.completarOnboarding(
    medios: Medio.values.toSet(),
    lineas: [LineaDeSubte.porId('B').linea, LineaDeSubte.porId('D').linea, const Linea(Medio.colectivo, '60')],
  );
  final theme = await ThemeController.load();
  await theme.setDark(false);
  await tester.pumpWidget(SmartTransportApp(
    api: apiConDatosFijos(),
    theme: theme,
    misLineas: misLineas,
    pedirPermisoDeUbicacion: () async => false,
  ));
}

/// Espera a que llegue el estilo del mapa base y a que se dibujen las primeras tiles.
Future<void> esperarElMapaBase(WidgetTester tester) async {
  final limite = DateTime.now().add(const Duration(seconds: 30));
  while (find.byType(VectorTileLayer).evaluate().isEmpty) {
    if (DateTime.now().isAfter(limite)) {
      fail('No llegó el estilo del mapa base en 30 s: ¿el teléfono tiene internet?');
    }
    await tester.pump(const Duration(milliseconds: 500));
  }
  await tester.pump(const Duration(seconds: 8));
}

/// El zoom actual del mapa.
double zoom(WidgetTester tester) => MapCamera.of(tester.element(find.byType(PolylineLayer))).zoom;

/// La secuencia fija de gestos: arrastres en varias direcciones y zoom con dos dedos que cruza los
/// zooms en que aparecen las estaciones de Ecobici (13.5) y las de Subte (12.5).
Future<void> gestos(WidgetTester tester) async {
  final mapa = tester.getRect(find.byType(FlutterMap));
  // Un poco más abajo del centro: arriba están el buscador y la fila de botones.
  final centro = Offset(mapa.center.dx, mapa.top + mapa.height * 0.55);
  final dedos = _Dedos(tester);

  // Con zoom 14: se ven las estaciones de Ecobici y las de Subte.
  expect(zoom(tester), 14);
  for (final direccion in const [
    Offset(-1, 0), Offset(1, 0), Offset(0, -1), Offset(0, 1), Offset(-0.7, -0.7), Offset(0.7, 0.7), //
  ]) {
    await dedos.arrastrar(centro, direccion * 250);
  }

  // Alejarse hasta zoom 12: desaparecen las estaciones de Ecobici y después las de Subte.
  await dedos.pellizcar(centro, desde: 300, hasta: 75);
  expect(zoom(tester), lessThan(12.5), reason: 'el pellizco no alejó el mapa');
  await dedos.arrastrar(centro, const Offset(-200, 120));
  await dedos.arrastrar(centro, const Offset(200, -120));

  // Acercarse hasta zoom 14 y un poco más: vuelven las de Subte y después las de Ecobici.
  await dedos.pellizcar(centro, desde: 75, hasta: 300);
  expect(zoom(tester), greaterThan(13.5), reason: 'el pellizco no acercó el mapa');
  await dedos.pellizcar(centro, desde: 150, hasta: 300);
  await dedos.arrastrar(centro, const Offset(0, -250));
  await dedos.arrastrar(centro, const Offset(250, 0));

  // Y de nuevo hacia afuera, hasta debajo de 13.5.
  await dedos.pellizcar(centro, desde: 300, hasta: 85);
  expect(zoom(tester), lessThan(13.5), reason: 'el pellizco no alejó el mapa');
  await dedos.arrastrar(centro, const Offset(-250, 0));
}

/// Gestos con uno o dos dedos, a la velocidad de una persona: los eventos se mandan cada 8 ms
/// (la frecuencia típica de una pantalla táctil), en tiempo real.
class _Dedos {
  _Dedos(this.tester);

  final WidgetTester tester;
  var _puntero = 1;

  static const _paso = Duration(milliseconds: 8);

  /// Un dedo que arrastra el mapa [desplazamiento], centrado en [centro], y lo suelta.
  Future<void> arrastrar(Offset centro, Offset desplazamiento) =>
      _gesto([(centro - desplazamiento / 2, centro + desplazamiento / 2)], const Duration(milliseconds: 400));

  /// Dos dedos, uno arriba y otro abajo de [centro], que pasan de estar a [desde] píxeles de
  /// distancia a estar a [hasta]: el zoom cambia en log2(hasta / desde).
  Future<void> pellizcar(Offset centro, {required double desde, required double hasta}) => _gesto([
        (centro.translate(0, -desde / 2), centro.translate(0, -hasta / 2)),
        (centro.translate(0, desde / 2), centro.translate(0, hasta / 2)),
      ], const Duration(milliseconds: 700));

  /// Los dedos van en línea recta de su inicio a su fin en [duracion]. Después se deja terminar
  /// la animación del mapa (la inercia del arrastre).
  Future<void> _gesto(List<(Offset, Offset)> recorridos, Duration duracion) async {
    final punteros = [for (final _ in recorridos) TestPointer(_puntero++, PointerDeviceKind.touch)];
    final pasos = duracion.inMicroseconds ~/ _paso.inMicroseconds;
    Offset en((Offset, Offset) r, int paso) => Offset.lerp(r.$1, r.$2, paso / pasos)!;

    await tester.handlePointerEventRecord([
      PointerEventRecord(Duration.zero, [
        for (final (i, p) in punteros.indexed) p.down(recorridos[i].$1),
      ]),
      for (var paso = 1; paso <= pasos; paso++)
        PointerEventRecord(_paso * paso, [
          for (final (i, p) in punteros.indexed) p.move(en(recorridos[i], paso), timeStamp: _paso * paso),
        ]),
      PointerEventRecord(_paso * (pasos + 1), [
        for (final p in punteros) p.up(timeStamp: _paso * (pasos + 1)),
      ]),
    ]);
    await tester.pump(const Duration(milliseconds: 800));
  }
}
