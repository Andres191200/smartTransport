import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../data/lineas_de_subte.dart';
import '../data/models.dart';
import '../data/transit_api.dart';
import 'markers.dart';
import 'lineas_comun.dart' show CirculoDeSubte;

/// "en 3 min", "llegando", "hace un momento"...
String formatEta(DateTime when, DateTime now) {
  final seconds = when.difference(now).inSeconds;
  if (seconds <= 30) return 'Llegando';
  final minutes = (seconds / 60).round();
  return minutes < 60 ? 'en $minutes min' : 'en ${minutes ~/ 60} h ${minutes % 60} min';
}

String formatAgo(DateTime when, DateTime now) {
  final seconds = now.difference(when).inSeconds;
  if (seconds < 60) return 'hace ${seconds < 5 ? 'un momento' : '$seconds s'}';
  return 'hace ${seconds ~/ 60} min';
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.children,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                leading,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: text.titleLarge),
                      if (subtitle != null)
                        Text(subtitle!, style: text.bodyMedium?.copyWith(color: Theme.of(context).hintColor)),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

class BusSheet extends StatelessWidget {
  const BusSheet({super.key, required this.bus});

  final Bus bus;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return _SheetFrame(
      leading: SizedBox(width: 56, height: 32, child: BusMarker(bus: bus)),
      title: 'Línea ${bus.line}',
      subtitle: bus.headsign,
      children: [
        if (bus.agency != null) _InfoRow(icon: Icons.business, text: bus.agency!),
        if (bus.speedMps != null)
          _InfoRow(icon: Icons.speed, text: '${(bus.speedMps! * 3.6).round()} km/h'),
        if (bus.timestamp != null)
          _InfoRow(icon: Icons.schedule, text: 'Posición actualizada ${formatAgo(bus.timestamp!, now)}'),
      ],
    );
  }
}

class BikeStationSheet extends StatelessWidget {
  const BikeStationSheet({super.key, required this.station});

  final BikeStation station;

  @override
  Widget build(BuildContext context) {
    final mechanical = station.bikes - station.ebikes;
    return _SheetFrame(
      leading: CircleAvatar(
        backgroundColor: bikeAvailabilityColor(station),
        foregroundColor: Colors.white,
        child: const Icon(Icons.pedal_bike),
      ),
      title: station.name,
      subtitle: station.address,
      children: [
        if (!station.operational)
          const _InfoRow(icon: Icons.block, text: 'Estación fuera de servicio')
        else ...[
          Row(
            children: [
              Expanded(child: _Stat(value: station.bikes, label: 'bicis disponibles')),
              Expanded(child: _Stat(value: station.docks, label: 'anclajes libres')),
            ],
          ),
          const SizedBox(height: 12),
          if (station.ebikes > 0)
            _InfoRow(icon: Icons.electric_bike, text: '$mechanical mecánicas · ${station.ebikes} eléctricas'),
        ],
        if (!station.acceptsReturns)
          const _InfoRow(icon: Icons.do_not_disturb_on_outlined, text: 'No recibe devoluciones por ahora'),
      ],
    );
  }
}

/// Hoja de una estación de subte: pide los próximos trenes y los refresca cada 20 s mientras está abierta.
class SubwayStationSheet extends StatefulWidget {
  const SubwayStationSheet({super.key, required this.api, required this.line, required this.station});

  final TransitApi api;
  final SubwayLine line;
  final SubwayStation station;

  @override
  State<SubwayStationSheet> createState() => _SubwayStationSheetState();
}

class _SubwayStationSheetState extends State<SubwayStationSheet> {
  List<SubwayArrival>? _arrivals;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final arrivals = await widget.api.subwayArrivals(widget.station.id);
      if (mounted) {
        setState(() {
          _arrivals = arrivals;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    final now = DateTime.now();
    final arrivals = _arrivals;

    // Agrupar por destino ("hacia Plaza de Mayo", "hacia San Pedrito").
    final byDestination = <String, List<SubwayArrival>>{};
    for (final a in arrivals ?? const <SubwayArrival>[]) {
      byDestination.putIfAbsent(a.destination, () => []).add(a);
    }

    return _SheetFrame(
      leading: CircleAvatar(
        backgroundColor: line.color,
        foregroundColor: line.textColor,
        child: Text(line.name, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      title: widget.station.name,
      subtitle: 'Línea ${line.name}',
      children: [
        if (arrivals == null && _error == null)
          const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
        else if (_error != null && arrivals == null)
          _InfoRow(icon: Icons.error_outline, text: _error!)
        else if (byDestination.isEmpty)
          const _InfoRow(icon: Icons.info_outline, text: 'Sin información de próximos trenes')
        else
          for (final MapEntry(key: destination, value: list) in byDestination.entries) ...[
            Text('Hacia $destination', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                for (final a in list)
                  Chip(
                    avatar: a.delaySeconds > 60 ? const Icon(Icons.warning_amber, size: 18) : null,
                    label: Text(formatEta(a.arrivalTime, now)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

/// Ficha de una Línea de Subte: la Línea, sus Terminales y el botón "Agregar a Mis líneas" o
/// "Eliminar", según si ya está en Mis líneas.
class FichaDeLineaDeSubte extends StatelessWidget {
  const FichaDeLineaDeSubte({
    super.key,
    required this.linea,
    required this.subwayLine,
    required this.agregada,
    required this.onAgregar,
    required this.onEliminar,
    required this.onCerrar,
  });

  final LineaDeSubte linea;

  /// La Línea según el backend, de donde salen las Terminales. Null si todavía no llegó.
  final SubwayLine? subwayLine;

  /// Si la Línea está en Mis líneas.
  final bool agregada;
  final VoidCallback onAgregar;
  final VoidCallback onEliminar;
  final VoidCallback onCerrar;

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      leading: ExcludeSemantics(child: CirculoDeSubte(linea: linea)),
      title: linea.nombre,
      trailing: IconButton(tooltip: 'Cerrar', icon: const Icon(Icons.close), onPressed: onCerrar),
      children: [
        if (subwayLine?.terminales case (final desde, final hasta)) _InfoRow(icon: Icons.route, text: '$desde – $hasta'),
        const SizedBox(height: 12),
        if (agregada)
          OutlinedButton.icon(onPressed: onEliminar, icon: const Icon(Icons.delete_outline), label: const Text('Eliminar'))
        else
          FilledButton.icon(onPressed: onAgregar, icon: const Icon(Icons.add), label: const Text('Agregar a Mis líneas')),
      ],
    );
  }
}

class AlertsSheet extends StatelessWidget {
  const AlertsSheet({super.key, required this.alerts, required this.lines});

  final List<ServiceAlert> alerts;
  final List<SubwayLine> lines;

  @override
  Widget build(BuildContext context) {
    final lineById = {for (final l in lines) l.id: l};
    return _SheetFrame(
      leading: const CircleAvatar(child: Icon(Icons.campaign_outlined)),
      title: 'Estado del subte',
      subtitle: alerts.isEmpty ? 'Todas las líneas funcionan con normalidad' : '${alerts.length} aviso(s)',
      children: [
        for (final alert in alerts)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Wrap(
              spacing: 4,
              children: [
                for (final id in alert.lineIds)
                  if (lineById[id] case final line?)
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: line.color,
                      foregroundColor: line.textColor,
                      child: Text(line.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                    ),
              ],
            ),
            title: Text(alert.title),
            subtitle: alert.description == null ? null : Text(alert.description!),
          ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Theme.of(context).hintColor),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$value', style: Theme.of(context).textTheme.displaySmall),
          Text(label),
        ],
      );
}
