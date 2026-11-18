import 'dart:async';

import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../config.dart';
import '../data/models.dart';
import '../data/transit_api.dart';
import '../settings/theme_controller.dart';
import 'app_drawer.dart';
import 'base_map.dart';
import 'markers.dart';
import 'sheets.dart';
import 'toggle_text_button.dart';

enum TransitLayer { buses, subway, bikes }

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
  const MapScreen({super.key, required this.api, required this.theme});

  final TransitApi api;
  final ThemeController theme;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  final _map = MapController();
  final _lineSearch = TextEditingController();

  final _layers = {...TransitLayer.values};
  double _zoom = 14;

  List<Bus> _buses = const [];
  bool _busesTruncated = false;
  String? _busLine;
  int _busRequestId = 0;

  List<SubwayLine> _subwayLines = const [];
  List<ServiceAlert> _alerts = const [];
  List<BikeStation> _bikes = const [];
  LatLng? _myLocation;

  String? _error;
  Timer? _debounce;
  final List<Timer> _pollers = [];

  TransitApi get _api => widget.api;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSubway();
    _loadBikes();
    _startPolling();
    // La primera carga de colectivos espera a que el mapa tenga tamaño (ver onMapReady).
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

  void _openSheet(Widget sheet) {
    showModalBottomSheet<void>(context: context, showDragHandle: true, isScrollControlled: true, builder: (_) => sheet);
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final showStations = _layers.contains(TransitLayer.subway) && _zoom >= _minZoomSubwayStations;
    final showBikes = _layers.contains(TransitLayer.bikes) && _zoom >= _minZoomBikes;
    final busesHidden =
        _layers.contains(TransitLayer.buses) && _busLine == null && _zoom < _minZoomBuses;

    return Scaffold(
      drawer: AppDrawer(theme: widget.theme),
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
              const BaseMap(),
              if (_layers.contains(TransitLayer.subway))
                PolylineLayer(
                  polylines: [
                    for (final line in _subwayLines)
                      Polyline(points: line.path, color: line.color, strokeWidth: 5),
                  ],
                ),
              if (showStations)
                MarkerLayer(
                  markers: [
                    for (final line in _subwayLines)
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
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TopBar(
                    controller: _lineSearch,
                    activeLine: _busLine,
                    alertCount: _alerts.length,
                    onSearch: _searchLine,
                    onClear: _clearLine,
                    onAlerts: () => _openSheet(AlertsSheet(alerts: _alerts, lines: _subwayLines)),
                  ),
                  const SizedBox(height: 8),
                  _LayerChips(active: _layers, onToggle: _toggleLayer),
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

class _LayerChips extends StatelessWidget {
  const _LayerChips({required this.active, required this.onToggle});

  final Set<TransitLayer> active;
  final void Function(TransitLayer, bool) onToggle;

  static const _buttons = {
    TransitLayer.buses: ('Colectivos', Icons.directions_bus, ToggleTextButtonCustomization(borderColor: Color(0xFF0B5CAD))),
    TransitLayer.subway: ('Subte', Icons.subway, ToggleTextButtonCustomization(borderColor: Color(0xFF7B1FA2))),
    TransitLayer.bikes: ('Ecobici', Icons.pedal_bike, ToggleTextButtonCustomization(borderColor: Color(0xFF00897B))),
  };

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        for (final MapEntry(key: layer, value: (text, icon, customization)) in _buttons.entries)
          ToggleTextButton(
            text: text,
            icon: icon,
            isActive: active.contains(layer),
            onTap: () => onToggle(layer, !active.contains(layer)),
            customization: customization,
          ),
      ],
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
