import 'dart:async';

import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../config.dart';
import '../data/lineas_de_subte.dart';
import '../data/models.dart';
import '../data/transit_api.dart';
import '../settings/mis_lineas.dart';
import '../settings/theme_controller.dart';
import 'app_drawer.dart';
import 'base_map.dart';
import 'fila_de_botones.dart';
import 'markers.dart';
import 'mis_lineas_screen.dart';
import 'sheets.dart';
import 'toggle_text_button.dart';

/// Capas que se prenden y apagan desde la fila de botones. Del Subte se dibujan siempre las
/// Líneas de Mis líneas.
enum TransitLayer { buses, bikes }

/// Debajo de estos zooms no se dibuja la capa (serían demasiados marcadores).
const _minZoomBuses = 14.0;
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

  /// Ecobici arranca según la preferencia de Mis líneas; lo que se prende o apaga después en el
  /// mapa no se guarda.
  late final _layers = {
    TransitLayer.buses,
    if (widget.misLineas.medios.contains(Medio.ecobici)) TransitLayer.bikes,
  };
  double _zoom = 14;

  List<Bus> _buses = const [];
  bool _busesTruncated = false;
  String? _busLine;
  int _busRequestId = 0;

  List<SubwayLine> _subwayLines = const [];
  List<ServiceAlert> _alerts = const [];
  List<BikeStation> _bikes = const [];
  LatLng? _myLocation;

  /// La Línea con la ficha abierta, si hay una. Su botón de la fila queda activo.
  Linea? _fichaAbierta;
  PersistentBottomSheetController? _ficha;

  /// El contenido de la ficha abierta, para medirla. Cada ficha tiene su llave: la anterior
  /// puede seguir en pantalla mientras se cierra.
  GlobalKey _fichaKey = GlobalKey();

  String? _error;
  Timer? _debounce;
  final List<Timer> _pollers = [];

  TransitApi get _api => widget.api;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.misLineas.addListener(_onMisLineasChanged);
    _loadSubway();
    _loadBikes();
    _startPolling();
    // La primera carga de colectivos espera a que el mapa tenga tamaño (ver onMapReady).
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.misLineas.removeListener(_onMisLineasChanged);
    _stopPolling();
    _debounce?.cancel();
    _lineSearch.dispose();
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

  Future<void> _loadSubway() => _guard(() async {
        final lines = await _api.subwayLines();
        if (mounted) setState(() => _subwayLines = lines);
        await _loadAlerts();
      });

  Future<void> _loadAlerts() => _guard(() async {
        final alerts = await _api.subwayAlerts();
        if (mounted) setState(() => _alerts = alerts);
      });

  Future<void> _loadBikes() async {
    if (!_layers.contains(TransitLayer.bikes)) return;
    await _guard(() async {
      final bikes = await _api.bikeStations();
      if (mounted) setState(() => _bikes = bikes);
    });
  }

  Future<void> _loadBuses() async {
    final line = _busLine;
    final camera = _cameraOrNull();
    final visible = _layers.contains(TransitLayer.buses) && (line != null || _zoom >= _minZoomBuses);
    if (!visible || camera == null) {
      if (_buses.isNotEmpty) setState(() => _buses = const []);
      return;
    }

    // Si se buscó una línea, se muestra toda la línea; si no, solo lo que se ve en pantalla.
    final bounds = camera.visibleBounds;
    final requestId = ++_busRequestId;
    await _guard(() async {
      final result = await _api.buses(
        line: line,
        bounds: line != null ? null : (southWest: bounds.southWest, northEast: bounds.northEast),
      );
      // Si mientras tanto salió otro pedido (el usuario movió el mapa), descartar este.
      if (!mounted || requestId != _busRequestId) return;
      setState(() {
        _buses = result.vehicles;
        _busesTruncated = result.truncated;
      });
    });
  }

  MapCamera? _cameraOrNull() {
    try {
      return _map.camera;
    } on Object {
      return null; // El mapa todavía no se dibujó.
    }
  }

  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    if (camera.zoom != _zoom) setState(() => _zoom = camera.zoom);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), _loadBuses);
  }

  // ---------------------------------------------------------------- acciones

  void _toggleLayer(TransitLayer layer, bool on) {
    setState(() => on ? _layers.add(layer) : _layers.remove(layer));
    if (on && layer == TransitLayer.bikes) _loadBikes();
    if (layer == TransitLayer.buses) _loadBuses();
  }

  void _searchLine(String value) {
    final line = value.trim().toUpperCase();
    setState(() {
      _busLine = line.isEmpty ? null : line;
      _buses = const [];
      _layers.add(TransitLayer.buses);
    });
    FocusScope.of(context).unfocus();
    _loadBuses();
  }

  void _clearLine() {
    _lineSearch.clear();
    _searchLine('');
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

  /// Si la Línea de la ficha se eliminó (p. ej. desde la pantalla Mis líneas), la ficha se cierra.
  void _onMisLineasChanged() {
    if (_fichaAbierta case final linea? when !widget.misLineas.contiene(linea)) _ficha?.close();
  }

  /// La Línea según el backend, o null si todavía no llegó.
  SubwayLine? _subwayLineDe(LineaDeSubte linea) =>
      _subwayLines.where((l) => LineaDeSubte.de(l)?.id == linea.id).firstOrNull;

  /// Abre la ficha de la Línea sin tapar el mapa; si ya estaba abierta, la cierra.
  void _toggleFicha(LineaDeSubte linea) {
    if (_fichaAbierta == linea.linea) {
      _ficha?.close();
      return;
    }
    final recorrido = _subwayLineDe(linea);
    final key = _fichaKey = GlobalKey();
    final controller = _scaffold.currentState!.showBottomSheet(
      (context) => FichaDeLineaDeSubte(
        key: key,
        linea: linea,
        recorrido: recorrido,
        onEliminar: () => _eliminar(linea),
      ),
      showDragHandle: true,
      elevation: 8,
    );
    setState(() {
      _fichaAbierta = linea.linea;
      _ficha = controller;
    });
    controller.closed.then((_) {
      // Si se abrió otra ficha mientras tanto, la Línea abierta ya es otra.
      if (mounted && _ficha == controller) {
        setState(() {
          _fichaAbierta = null;
          _ficha = null;
        });
      }
    });
    if (recorrido != null && recorrido.path.isNotEmpty) {
      // Cuando la ficha ya tiene tamaño, se sabe cuánto mapa queda a la vista.
      WidgetsBinding.instance.addPostFrameCallback((_) => _encuadrar(recorrido.path, key));
    }
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

  Future<void> _eliminar(LineaDeSubte linea) async {
    final messenger = ScaffoldMessenger.of(context);
    _ficha?.close();
    await eliminarConDeshacer(messenger, widget.misLineas, linea);
  }

  void _openSheet(Widget sheet) {
    showModalBottomSheet<void>(context: context, showDragHandle: true, isScrollControlled: true, builder: (_) => sheet);
  }

  // ---------------------------------------------------------------- UI

  /// Las Líneas de Subte de Mis líneas, con su Recorrido y sus estaciones.
  List<SubwayLine> get _mySubwayLines => [
        for (final line in _subwayLines)
          if (LineaDeSubte.de(line) case final linea? when widget.misLineas.contiene(linea.linea)) line,
      ];

  static const _layerButtons = {
    TransitLayer.buses: ('Colectivos', Icons.directions_bus, ToggleTextButtonCustomization(borderColor: Color(0xFF0B5CAD))),
    TransitLayer.bikes: ('Ecobici', Icons.pedal_bike, ToggleTextButtonCustomization(borderColor: Color(0xFF00897B))),
  };

  Widget _layerButton(TransitLayer layer) {
    final (text, icon, customization) = _layerButtons[layer]!;
    final on = _layers.contains(layer);
    return ToggleTextButton(
      text: text,
      icon: icon,
      isActive: on,
      onTap: () => _toggleLayer(layer, !on),
      customization: customization,
    );
  }

  /// El botón de una Línea de Mis líneas: abre su ficha y queda activo mientras está abierta.
  Widget _lineaButton(LineaDeSubte linea) => ToggleTextButton(
        text: linea.id,
        icon: Icons.subway_outlined,
        isActive: _fichaAbierta == linea.linea,
        onTap: () => _toggleFicha(linea),
        customization: ToggleTextButtonCustomization(borderColor: linea.color),
      );

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: widget.misLineas, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final subwayLines = _mySubwayLines;
    final showStations = _zoom >= _minZoomSubwayStations;
    final isEmpty = widget.misLineas.lineas.isEmpty && !_layers.contains(TransitLayer.bikes);
    final showBikes = _layers.contains(TransitLayer.bikes) && _zoom >= _minZoomBikes;
    final busesHidden =
        _layers.contains(TransitLayer.buses) && _busLine == null && _zoom < _minZoomBuses;

    return Scaffold(
      key: _scaffold,
      drawer: AppDrawer(theme: widget.theme, misLineas: widget.misLineas),
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
              onMapReady: _loadBuses,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
              backgroundColor: BaseMap.backgroundFor(Theme.of(context).brightness),
            ),
            children: [
              widget.baseMap,
              PolylineLayer(
                polylines: [
                  for (final line in subwayLines)
                    Polyline(points: line.path, color: line.color, strokeWidth: 5),
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
              if (_layers.contains(TransitLayer.buses))
                MarkerLayer(
                  markers: [
                    for (final bus in _buses)
                      Marker(
                        point: bus.position,
                        width: 40,
                        height: 22,
                        child: GestureDetector(
                          onTap: () => _openSheet(BusSheet(bus: bus)),
                          child: BusMarker(bus: bus, highlighted: _busLine != null),
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
                      activeLine: _busLine,
                      alertCount: _alerts.length,
                      onSearch: _searchLine,
                      onClear: _clearLine,
                      onAlerts: () => _openSheet(AlertsSheet(alerts: _alerts, lines: _subwayLines)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // La fila ocupa todo el ancho para que los botones se deslicen hasta el borde.
                  FilaDeBotones(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    fadeColor: BaseMap.backgroundFor(Theme.of(context).brightness),
                    children: [
                      _layerButton(TransitLayer.bikes),
                      for (final linea in widget.misLineas.lineasDe(Medio.subte)) _lineaButton(LineaDeSubte.porId(linea.id)),
                      // Hasta que Colectivo entre en Mis líneas (#12) queda el botón de capa.
                      _layerButton(TransitLayer.buses),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_api.demoLayers case final demo when demo.isNotEmpty)
                          _Banner(icon: Icons.science_outlined, text: 'Datos simulados: ${joinSpanish(demo)}'),
                        if (_error case final error?)
                          _Banner(icon: Icons.cloud_off, text: error, onTap: () {
                            _loadSubway();
                            _loadBikes();
                            _loadBuses();
                          }),
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
                onAdd: () => Navigator.of(context).push(MisLineasScreen.route(widget.misLineas)),
              ),
            ),
          if (busesHidden || _busesTruncated)
            Positioned(
              left: 0,
              right: 0,
              bottom: 32,
              child: Center(
                child: Chip(
                  avatar: const Icon(Icons.zoom_in, size: 18),
                  label: Text(busesHidden
                      ? 'Acercá el mapa para ver colectivos'
                      : 'Hay más colectivos: acercá el mapa o buscá una línea'),
                ),
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
    required this.activeLine,
    required this.alertCount,
    required this.onSearch,
    required this.onClear,
    required this.onAlerts,
  });

  final TextEditingController controller;
  final String? activeLine;
  final int alertCount;
  final ValueChanged<String> onSearch;
  final VoidCallback onClear;
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
              decoration: const InputDecoration(hintText: 'Buscar línea de colectivo', border: InputBorder.none),
              onSubmitted: onSearch,
            ),
          ),
          if (activeLine != null) IconButton(tooltip: 'Ver todas', icon: const Icon(Icons.close), onPressed: onClear),
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
