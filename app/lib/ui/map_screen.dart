import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../config.dart';
import '../data/catalogo_de_colectivos.dart';
import '../data/lineas_de_subte.dart';
import '../data/models.dart';
import '../data/transit_api.dart';
import '../settings/mis_lineas.dart';
import '../settings/theme_controller.dart';
import 'app_drawer.dart';
import 'base_map.dart';
import 'buscador_de_lineas.dart';
import 'fila_de_botones.dart';
import 'lineas_comun.dart';
import 'markers.dart';
import 'mis_lineas_screen.dart';
import 'sheets.dart';
import 'toggle_text_button.dart';

/// Debajo de estos zooms no se dibuja la capa (serían demasiados marcadores). Los colectivos se
/// ven con cualquier zoom: son solo los de Mis líneas.
const _minZoomSubwayStations = 12.5;
const _minZoomBikes = 13.5;

const _obelisco = LatLng(-34.6037, -58.3816);

/// ["a", "b", "c"] → "a, b y c"
String joinSpanish(List<String> items) => items.length <= 1
    ? items.join()
    : '${items.sublist(0, items.length - 1).join(', ')} y ${items.last}';

class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    required this.api,
    required this.theme,
    required this.misLineas,
    this.baseMap = const BaseMap(),
  });

  final TransitApi api;
  final ThemeController theme;
  final MisLineas misLineas;

  /// Capa del mapa base: el primer hijo de FlutterMap (ver [BaseMap]).
  final Widget baseMap;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  final _map = MapController();
  final _scaffold = GlobalKey<ScaffoldState>();

  /// Lo que tapa el mapa arriba (barra, fila de botones y avisos): la cámara encuadra debajo.
  final _overlay = GlobalKey();
  final _lineSearch = TextEditingController();

  /// Lo escrito en el buscador: mientras no está vacío, se muestran las Líneas que coinciden.
  String _consulta = '';

  late final _catalogo = CatalogoDeColectivos(widget.api);

  /// Ecobici arranca según la preferencia de Mis líneas; lo que se prende o apaga después en el
  /// mapa no se guarda.
  late bool _ecobici = widget.misLineas.medios.contains(Medio.ecobici);
  double _zoom = 14;

  /// Los colectivos en vivo de las Líneas de Colectivo de Mis líneas.
  List<Bus> _buses = const [];
  int _busRequestId = 0;

  /// Las Líneas de Colectivo del último pedido de colectivos: si cambian, se pide de nuevo.
  List<String> _colectivosPedidos = const [];

  /// Los Recorridos de las Líneas de Colectivo cuya ficha se abrió, por número de Línea.
  final _recorridosDeColectivo = <String, BusLine>{};

  List<SubwayLine> _subwayLines = const [];
  List<ServiceAlert> _alerts = const [];
  List<BikeStation> _bikes = const [];
  LatLng? _myLocation;

  /// La Línea con la ficha abierta, si hay una. Su botón de la fila queda activo y el mapa dibuja
  /// su Recorrido (los de todos sus Ramales, en Colectivo).
  Linea? _fichaAbierta;
  PersistentBottomSheetController? _ficha;

  /// Si la Línea de la ficha estaba en Mis líneas la última vez que cambiaron.
  bool _fichaEnMisLineas = false;

  /// Si la cámara ya encuadró el Recorrido de la ficha abierta (puede llegar después de abrirla).
  bool _fichaEncuadrada = false;

  /// El contenido de la ficha abierta, para medirla. Cada ficha tiene su llave: la anterior
  /// puede seguir en pantalla mientras se cierra.
  GlobalKey _fichaKey = GlobalKey();

  String? _error;
  final List<Timer> _pollers = [];

  TransitApi get _api => widget.api;

  /// Los números de las Líneas de Colectivo de Mis líneas, en orden de agregado.
  List<String> get _misColectivos => [for (final l in widget.misLineas.lineasDe(Medio.colectivo)) l.id];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.misLineas.addListener(_onMisLineasChanged);
    _loadCatalogo();
    _loadSubway();
    _loadBikes();
    _loadBuses();
    _startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.misLineas.removeListener(_onMisLineasChanged);
    _stopPolling();
    _lineSearch.dispose();
    _catalogo.dispose();
    super.dispose();
  }

  /// Sin la app en primer plano no hace falta seguir pidiendo datos (batería y cuota de la API).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadBuses();
      _loadBikes();
      _startPolling();
    } else if (state == AppLifecycleState.paused) {
      _stopPolling();
    }
  }

  void _startPolling() {
    _stopPolling();
    _pollers
      ..add(Timer.periodic(const Duration(seconds: 15), (_) => _loadBuses()))
      ..add(Timer.periodic(const Duration(seconds: 60), (_) => _loadBikes()))
      ..add(Timer.periodic(const Duration(minutes: 2), (_) => _loadAlerts()));
  }

  void _stopPolling() {
    for (final t in _pollers) {
      t.cancel();
    }
    _pollers.clear();
  }

  // ---------------------------------------------------------------- carga de datos

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
      if (mounted && _error != null) setState(() => _error = null);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// El catálogo de Colectivo, para el buscador y las fichas.
  Future<void> _loadCatalogo() => _guard(() async {
        await _catalogo.cargar();
        // Si la ficha de una Línea de Colectivo se abrió antes, ahora se completan sus Ramales.
        _ficha?.setState?.call(() {});
      });

  Future<void> _loadSubway() => _guard(() async {
        final lines = await _api.subwayLines();
        if (!mounted) return;
        setState(() => _subwayLines = lines);
        // Si la ficha se abrió antes de que llegaran los datos, ahora se completa.
        _ficha?.setState?.call(() {});
        _encuadrarFicha();
        await _loadAlerts();
      });

  Future<void> _loadAlerts() => _guard(() async {
        final alerts = await _api.subwayAlerts();
        if (mounted) setState(() => _alerts = alerts);
      });

  Future<void> _loadBikes() async {
    if (!_ecobici) return;
    await _guard(() async {
      final bikes = await _api.bikeStations();
      if (mounted) setState(() => _bikes = bikes);
    });
  }

  /// Pide en un solo pedido los colectivos de todas las Líneas de Colectivo de Mis líneas, en toda
  /// la ciudad. Sin Líneas de Colectivo no pide nada.
  Future<void> _loadBuses() async {
    final lines = _colectivosPedidos = _misColectivos;
    final requestId = ++_busRequestId;
    if (lines.isEmpty) {
      if (_buses.isNotEmpty) setState(() => _buses = const []);
      return;
    }
    await _guard(() async {
      final result = await _api.buses(lines: lines);
      // Si mientras tanto salió otro pedido (cambiaron Mis líneas), descartar este.
      if (!mounted || requestId != _busRequestId) return;
      setState(() => _buses = result.vehicles);
    });
  }

  /// Los Recorridos de todos los Ramales de una Línea de Colectivo: se piden al abrir su ficha.
  Future<void> _loadRecorridos(String line) async {
    if (_recorridosDeColectivo.containsKey(line)) return;
    await _guard(() async {
      final busLine = await _api.busPaths(line);
      if (!mounted) return;
      setState(() => _recorridosDeColectivo[line] = busLine);
      _ficha?.setState?.call(() {});
      _encuadrarFicha();
    });
  }

  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    if (camera.zoom != _zoom) setState(() => _zoom = camera.zoom);
  }

  // ---------------------------------------------------------------- acciones

  void _toggleEcobici() {
    setState(() => _ecobici = !_ecobici);
    _loadBikes();
  }

  List<Linea> _buscar(String consulta) => consulta.trim().isEmpty
      ? const []
      : buscarLineas(consulta, colectivos: [for (final l in _catalogo.lineas) l.id]);

  /// Enter en el buscador abre la primera Línea encontrada.
  void _onSearchSubmitted(String value) {
    if (_buscar(value) case [final primera, ...]) _elegirResultado(primera);
  }

  /// Tocar un resultado del buscador abre la ficha de la Línea.
  void _elegirResultado(Linea linea) {
    _lineSearch.clear();
    setState(() => _consulta = '');
    FocusScope.of(context).unfocus();
    _abrirFicha(linea);
  }

  Future<void> _goToMyLocation() async {
    final messenger = ScaffoldMessenger.of(context);
    void say(String text) => messenger.showSnackBar(SnackBar(content: Text(text)));

    if (!await Geolocator.isLocationServiceEnabled()) {
      return say('Activá la ubicación del teléfono');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      return say('Sin permiso de ubicación');
    }
    final pos = await Geolocator.getCurrentPosition();
    if (!mounted) return;
    final here = LatLng(pos.latitude, pos.longitude);
    setState(() => _myLocation = here);
    _map.move(here, 16);
  }

  /// Si cambian las Líneas de Colectivo, se piden sus colectivos. Si la Línea de la ficha se
  /// eliminó (p. ej. desde la pantalla Mis líneas), la ficha se cierra. La ficha de una vista
  /// previa sigue abierta, también cuando la Línea se agrega.
  void _onMisLineasChanged() {
    if (!listEquals(_misColectivos, _colectivosPedidos)) _loadBuses();
    final linea = _fichaAbierta;
    if (linea == null) return;
    final enMisLineas = widget.misLineas.contiene(linea);
    if (_fichaEnMisLineas && !enMisLineas) _cerrarFicha();
    _fichaEnMisLineas = enMisLineas;
  }

  /// La Línea de Subte según el backend, o null si todavía no llegó.
  SubwayLine? _subwayLineDe(LineaDeSubte linea) =>
      _subwayLines.where((l) => LineaDeSubte.de(l)?.id == linea.id).firstOrNull;

  /// Los Recorridos de la Línea que ya llegaron del backend: uno en Subte, uno por Ramal en
  /// Colectivo (los Ramales sin Recorrido no se dibujan).
  List<List<LatLng>> _recorridos(Linea linea) => switch (linea.deSubte) {
        final subte? => [?_subwayLineDe(subte)?.path],
        null => [
            for (final ramal in _recorridosDeColectivo[linea.id]?.branches ?? const <BusBranch>[])
              if (ramal.path.isNotEmpty) ramal.path,
          ],
      };

  /// Las filas de la ficha: las Terminales de la Línea de Subte, o cada Ramal de Colectivo con
  /// las suyas ("60A · Constitución – Escobar"). Los Ramales salen del catálogo hasta que llegan
  /// los Recorridos.
  List<String> _filasDeFicha(Linea linea) {
    if (linea.deSubte case final subte?) {
      return [if (_subwayLineDe(subte)?.terminales case (final desde, final hasta)) '$desde – $hasta'];
    }
    final ramales = (_recorridosDeColectivo[linea.id] ?? _catalogo.porId(linea.id))?.branches ?? const [];
    return [
      for (final ramal in ramales)
        if (ramal.terminales case (final desde, final hasta)) '${ramal.id} · $desde – $hasta' else ramal.id,
    ];
  }

  /// El botón de una Línea de la fila abre su ficha; si ya estaba abierta, la cierra.
  void _toggleFicha(Linea linea) {
    if (_fichaAbierta == linea) {
      _cerrarFicha();
    } else {
      _abrirFicha(linea);
    }
  }

  /// Abre la ficha de la Línea sin tapar el mapa y encuadra su Recorrido.
  void _abrirFicha(Linea linea) {
    if (_fichaAbierta == linea) return _encuadrarFicha(otraVez: true);
    final key = _fichaKey = GlobalKey();
    final controller = _scaffold.currentState!.showBottomSheet(
      (context) => ListenableBuilder(
        listenable: widget.misLineas,
        builder: (context, _) => FichaDeLinea(
          key: key,
          linea: linea,
          recorridos: _filasDeFicha(linea),
          agregada: widget.misLineas.contiene(linea),
          onAgregar: () => widget.misLineas.agregar(linea),
          onEliminar: () => _eliminar(linea),
          onCerrar: _cerrarFicha,
        ),
      ),
      showDragHandle: true,
      elevation: 8,
    );
    setState(() {
      _fichaAbierta = linea;
      _fichaEnMisLineas = widget.misLineas.contiene(linea);
      _fichaEncuadrada = false;
      _ficha = controller;
    });
    controller.closed.then((_) {
      // Si se abrió otra ficha (o se cerró esta) mientras tanto, no hay nada que hacer.
      if (mounted && _ficha == controller) {
        setState(() {
          _fichaAbierta = null;
          _ficha = null;
        });
      }
    });
    if (linea.medio == Medio.colectivo) _loadRecorridos(linea.id);
    _encuadrarFicha();
  }

  /// Cierra la ficha. Su Línea deja de estar abierta en el acto: su Recorrido no se sigue
  /// dibujando mientras la ficha baja.
  void _cerrarFicha() {
    final ficha = _ficha;
    setState(() {
      _fichaAbierta = null;
      _ficha = null;
    });
    ficha?.close();
  }

  /// Encuadra el Recorrido de la ficha abierta, si ya llegó y todavía no se encuadró (o si se
  /// pide [otraVez]).
  void _encuadrarFicha({bool otraVez = false}) {
    if (_fichaEncuadrada && !otraVez) return;
    final linea = _fichaAbierta;
    final recorrido = linea == null ? const <LatLng>[] : [for (final r in _recorridos(linea)) ...r];
    if (recorrido.isEmpty) return;
    _fichaEncuadrada = true;
    // Cuando la ficha ya tiene tamaño, se sabe cuánto mapa queda a la vista.
    final key = _fichaKey;
    WidgetsBinding.instance.addPostFrameCallback((_) => _encuadrar(recorrido, key));
  }

  /// Mueve la cámara para que el Recorrido entre completo entre lo que tapa el mapa arriba y la
  /// ficha abajo.
  void _encuadrar(List<LatLng> recorrido, GlobalKey fichaKey) {
    if (!mounted || fichaKey != _fichaKey) return; // ya se abrió otra ficha
    final map = context.findRenderObject() as RenderBox?;
    final overlay = _overlay.currentContext?.findRenderObject() as RenderBox?;
    RenderBox? ficha;
    fichaKey.currentContext?.visitAncestorElements((e) {
      if (e.widget is! BottomSheet) return true;
      ficha = e.findRenderObject() as RenderBox?;
      return false;
    });
    if (map == null || overlay == null || ficha == null) return;

    const margin = 24.0;
    final top = overlay.localToGlobal(Offset(0, overlay.size.height), ancestor: map).dy;
    _map.fitCamera(CameraFit.coordinates(
      coordinates: recorrido,
      padding: EdgeInsets.fromLTRB(margin, top + margin, margin, ficha!.size.height + margin),
      maxZoom: 16,
    ));
  }

  Future<void> _eliminar(Linea linea) async {
    final messenger = ScaffoldMessenger.of(context);
    _cerrarFicha();
    await eliminarConDeshacer(messenger, widget.misLineas, linea);
  }

  void _openSheet(Widget sheet) {
    showModalBottomSheet<void>(context: context, showDragHandle: true, isScrollControlled: true, builder: (_) => sheet);
  }

  void _reintentar() {
    _loadCatalogo();
    _loadSubway();
    _loadBikes();
    _loadBuses();
    if (_fichaAbierta case Linea(medio: Medio.colectivo, :final id)) _loadRecorridos(id);
  }

  // ---------------------------------------------------------------- UI

  /// Las Líneas de Subte de Mis líneas, con su Recorrido y sus estaciones.
  List<SubwayLine> get _mySubwayLines => [
        for (final line in _subwayLines)
          if (LineaDeSubte.de(line) case final linea? when widget.misLineas.contiene(linea.linea)) line,
      ];

  /// Los avisos del subte: primero los de las Líneas de Subte de Mis líneas y después el resto,
  /// cada grupo en el orden en que llegaron. Los avisos nombran las Líneas con los ids del backend
  /// ("LineaD"), así que se cruzan con las Líneas de Subte del backend que están en Mis líneas.
  ({List<ServiceAlert> mios, List<ServiceAlert> otros}) get _avisos {
    final mias = {for (final line in _mySubwayLines) line.id};
    final mios = [for (final alert in _alerts) if (alert.lineIds.any(mias.contains)) alert];
    return (mios: mios, otros: [for (final alert in _alerts) if (!mios.contains(alert)) alert]);
  }

  /// La Línea de Subte con la ficha abierta que no está en Mis líneas: el mapa dibuja solo su
  /// Recorrido y sus Terminales, sin nada en vivo, hasta que se cierra la ficha (ADR 0002).
  SubwayLine? get _vistaPrevia => switch (_fichaAbierta) {
        final linea? when !widget.misLineas.contiene(linea) => switch (linea.deSubte) {
            final subte? => _subwayLineDe(subte),
            null => null,
          },
        _ => null,
      };

  /// Los Ramales de la Línea de Colectivo con la ficha abierta, con sus Recorridos. Con la ficha
  /// cerrada no se dibuja ningún Recorrido de Colectivo.
  List<BusBranch> get _ramalesAbiertos => switch (_fichaAbierta) {
        Linea(medio: Medio.colectivo, :final id) => _recorridosDeColectivo[id]?.branches ?? const [],
        _ => const [],
      };

  /// Los colectivos de las Líneas de Mis líneas. Se filtra también acá para que una Línea
  /// eliminada desaparezca sin esperar al próximo pedido.
  List<Bus> get _misBuses {
    final mias = _misColectivos.toSet();
    return [for (final bus in _buses) if (mias.contains(bus.lineId)) bus];
  }

  /// El botón de una Línea de Mis líneas: abre su ficha y queda activo mientras está abierta.
  Widget _lineaButton(Linea linea) => ToggleTextButton(
        text: linea.id,
        icon: linea.medio.icono,
        isActive: _fichaAbierta == linea,
        onTap: () => _toggleFicha(linea),
        customization: ToggleTextButtonCustomization(borderColor: linea.color),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([widget.misLineas, _catalogo]),
        builder: (context, _) => _build(context),
      );

  Widget _build(BuildContext context) {
    final subwayLines = _mySubwayLines;
    final vistaPrevia = _vistaPrevia;
    final ramales = _ramalesAbiertos;
    final terminalesDeColectivo = {
      for (final ramal in ramales)
        if ((ramal.terminales, ramal.path) case ((final desde, final hasta), [final inicio, ..., final fin])) ...{
          (desde, inicio),
          (hasta, fin),
        },
    };
    final encontradas = _buscar(_consulta);
    final avisos = _avisos;
    final showStations = _zoom >= _minZoomSubwayStations;
    final isEmpty = widget.misLineas.lineas.isEmpty && !_ecobici;
    final showBikes = _ecobici && _zoom >= _minZoomBikes;

    return Scaffold(
      key: _scaffold,
      drawer: AppDrawer(theme: widget.theme, misLineas: widget.misLineas, catalogo: _catalogo),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _obelisco,
              initialZoom: _zoom,
              minZoom: 10,
              maxZoom: 19,
              onPositionChanged: _onPositionChanged,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
              backgroundColor: BaseMap.backgroundFor(Theme.of(context).brightness),
            ),
            children: [
              widget.baseMap,
              PolylineLayer(
                polylines: [
                  for (final line in [...subwayLines, ?vistaPrevia])
                    Polyline(points: line.path, color: line.color, strokeWidth: 5),
                  for (final ramal in ramales)
                    if (ramal.path.isNotEmpty) Polyline(points: ramal.path, color: azulColectivo, strokeWidth: 4),
                ],
              ),
              if (vistaPrevia != null && vistaPrevia.stations.isNotEmpty)
                MarkerLayer(
                  markers: [
                    for (final terminal in {vistaPrevia.stations.first, vistaPrevia.stations.last})
                      Marker(
                        point: terminal.position,
                        width: 18,
                        height: 18,
                        child: SubwayStationMarker(line: vistaPrevia, station: terminal),
                      ),
                  ],
                ),
              if (terminalesDeColectivo.isNotEmpty)
                MarkerLayer(
                  markers: [
                    for (final (nombre, punto) in terminalesDeColectivo)
                      Marker(point: punto, width: 18, height: 18, child: TerminalDeColectivoMarker(name: nombre)),
                  ],
                ),
              if (showStations)
                MarkerLayer(
                  markers: [
                    for (final line in subwayLines)
                      for (final station in line.stations)
                        Marker(
                          point: station.position,
                          width: 18,
                          height: 18,
                          child: GestureDetector(
                            onTap: () => _openSheet(SubwayStationSheet(api: _api, line: line, station: station)),
                            child: SubwayStationMarker(line: line, station: station),
                          ),
                        ),
                  ],
                ),
              if (showBikes)
                MarkerLayer(
                  markers: [
                    for (final s in _bikes)
                      Marker(
                        point: s.position,
                        width: 28,
                        height: 28,
                        child: GestureDetector(
                          onTap: () => _openSheet(BikeStationSheet(station: s)),
                          child: BikeStationMarker(station: s),
                        ),
                      ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  for (final bus in _misBuses)
                    Marker(
                      point: bus.position,
                      width: 40,
                      height: 22,
                      child: GestureDetector(
                        onTap: () => _openSheet(BusSheet(bus: bus)),
                        child: BusMarker(bus: bus),
                      ),
                    ),
                ],
              ),
              if (_myLocation case final here?)
                MarkerLayer(markers: [Marker(point: here, width: 22, height: 22, child: const UserLocationMarker())]),
              const SimpleAttributionWidget(source: Text(AppConfig.mapAttribution)),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                key: _overlay,
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: _TopBar(
                      controller: _lineSearch,
                      alertCount: avisos.mios.length,
                      onChanged: (value) => setState(() => _consulta = value),
                      onSearch: _onSearchSubmitted,
                      onAlerts: () =>
                          _openSheet(AlertsSheet(alerts: [...avisos.mios, ...avisos.otros], lines: _subwayLines)),
                    ),
                  ),
                  if (encontradas.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                      child: Material(
                        elevation: 3,
                        borderRadius: BorderRadius.circular(16),
                        clipBehavior: Clip.antiAlias,
                        color: Theme.of(context).colorScheme.surface,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 320),
                          child: ResultadosDeBusqueda(
                            lineas: encontradas,
                            misLineas: widget.misLineas,
                            onElegir: _elegirResultado,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 4),
                  // La fila ocupa todo el ancho para que los botones se deslicen hasta el borde.
                  FilaDeBotones(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    fadeColor: BaseMap.backgroundFor(Theme.of(context).brightness),
                    children: [
                      ToggleTextButton(
                        text: 'Ecobici',
                        icon: Medio.ecobici.icono,
                        isActive: _ecobici,
                        onTap: _toggleEcobici,
                        customization: const ToggleTextButtonCustomization(borderColor: Color(0xFF00897B)),
                      ),
                      for (final linea in widget.misLineas.lineas) _lineaButton(linea),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_api.demoLayers case final demo when demo.isNotEmpty)
                          _Banner(icon: Icons.science_outlined, text: 'Datos simulados: ${joinSpanish(demo)}'),
                        if (_error case final error?) _Banner(icon: Icons.cloud_off, text: error, onTap: _reintentar),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isEmpty)
            Center(
              child: _EmptyMessage(
                onAdd: () => Navigator.of(context).push(MisLineasScreen.route(widget.misLineas, _catalogo)),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Mi ubicación',
        onPressed: _goToMyLocation,
        child: const Icon(Icons.my_location),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.controller,
    required this.alertCount,
    required this.onChanged,
    required this.onSearch,
    required this.onAlerts,
  });

  final TextEditingController controller;

  /// Los avisos del subte de las Líneas de Mis líneas: sin ninguno, el ícono no muestra número.
  final int alertCount;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSearch;
  final VoidCallback onAlerts;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(28),
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        children: [
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Menú',
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(hintText: 'Buscar línea', border: InputBorder.none),
              onChanged: onChanged,
              onSubmitted: onSearch,
            ),
          ),
          IconButton(
            tooltip: 'Estado del subte',
            onPressed: onAlerts,
            icon: Badge(
              isLabelVisible: alertCount > 0,
              label: Text('$alertCount'),
              child: const Icon(Icons.subway_outlined),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

/// Lo que muestra el mapa cuando no hay nada propio que dibujar.
class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      elevation: 3,
      margin: const EdgeInsets.all(32),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Tu mapa está vacío', style: text.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Agregá las líneas que usás para verlas en el mapa.',
              textAlign: TextAlign.center,
              style: text.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Agregar líneas')),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, this.onTap});

  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(icon, size: 18, color: scheme.onSecondaryContainer),
                const SizedBox(width: 8),
                Expanded(child: Text(text, style: TextStyle(color: scheme.onSecondaryContainer))),
                if (onTap != null) Text('Reintentar', style: TextStyle(color: scheme.primary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
