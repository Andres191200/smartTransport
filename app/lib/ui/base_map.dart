import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import '../config.dart';

/// Mapa base vectorial (decisión en docs/adr/0001). Va como primer hijo de FlutterMap.
///
/// Usa el estilo claro u oscuro según el tema. Mientras el estilo carga, o si falla
/// (p. ej. sin conexión), no dibuja nada y reintenta cada [_retryDelay].
class BaseMap extends StatefulWidget {
  const BaseMap({super.key});

  /// Color de fondo de los estilos por defecto, para que el mapa no "parpadee" al cargar.
  static Color backgroundFor(Brightness brightness) =>
      brightness == Brightness.dark ? const Color(0xFF0C0C0C) : const Color(0xFFF2F3F0);

  @override
  State<BaseMap> createState() => _BaseMapState();
}

const _retryDelay = Duration(seconds: 10);

/// Un estilo por URL para toda la app: se descarga una sola vez.
final _styles = <String, Future<Style>>{};

Future<Style> _style(String url) =>
    _styles[url] ??= StyleReader(uri: url).read().then((s) => _conIdPropio(s, url)).catchError((
      Object e,
      StackTrace st,
    ) {
      _styles.remove(url); // que el próximo intento vuelva a descargarlo
      Error.throwWithStackTrace(e, st);
    });

/// Los estilos de OpenFreeMap no traen "id", y vector_map_tiles guarda en disco las tiles ya
/// dibujadas usando el id del tema como clave: sin un id propio por estilo, el claro y el oscuro
/// compartirían las tiles. El id va pegado al estilo (y no al tema actual de la app) porque al
/// cambiar de tema el mapa sigue mostrando el estilo anterior mientras llega el nuevo.
/// (El prefijo "v2" descarta las tiles que una versión anterior guardó con el id equivocado.)
Style _conIdPropio(Style style, String url) => Style(
      name: style.name,
      theme: style.theme.copyWith(id: 'v2-$url'),
      providers: style.providers,
      sprites: style.sprites,
      center: style.center,
      zoom: style.zoom,
    );

class _BaseMapState extends State<BaseMap> {
  Timer? _retry;

  @override
  void dispose() {
    _retry?.cancel();
    super.dispose();
  }

  void _scheduleRetry(Object error) {
    if (_retry?.isActive ?? false) return;
    debugPrint('No se pudo cargar el estilo del mapa: $error');
    _retry = Timer(_retryDelay, () {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return FutureBuilder(
      future: _style(dark ? AppConfig.mapStyleDark : AppConfig.mapStyleLight),
      builder: (context, snap) {
        if (snap.error case final error?) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleRetry(error));
          return const SizedBox.shrink();
        }
        final style = snap.data;
        if (style == null) return const SizedBox.shrink();
        return VectorTileLayer(
          key: ValueKey(style),
          theme: style.theme,
          sprites: style.sprites,
          tileProviders: style.providers,
          maximumZoom: 19,
        );
      },
    );
  }
}
