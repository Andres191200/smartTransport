import 'package:material_ui/material_ui.dart';

import '../data/lineas_de_subte.dart';
import '../settings/mis_lineas.dart';
import 'lineas_comun.dart';

// El buscador de Líneas: lo usan el mapa (tocar un resultado abre su ficha) y el "+" de la
// pantalla Mis líneas (tocar un resultado lo agrega).

/// Los Medios en los que se puede buscar. Colectivo se suma con su catálogo (#12).
const mediosBuscables = {Medio.subte};

/// Las Líneas de los [medios] pedidos cuyo nombre empieza como [consulta], en el orden en que se
/// ofrecen. Ignora mayúsculas, tildes y un "Línea" o "Subte" adelante; una consulta vacía devuelve
/// todas.
List<Linea> buscarLineas(String consulta, {Set<Medio> medios = mediosBuscables}) {
  final q = _normalizar(consulta).replaceFirst(RegExp(r'^((linea|subte)\b\s*)*'), '');
  return [
    if (medios.contains(Medio.subte))
      for (final l in LineaDeSubte.todas)
        if (_normalizar(l.id).startsWith(q)) l.linea,
  ];
}

String _normalizar(String text) => text
    .trim()
    .toLowerCase()
    .replaceAll('á', 'a')
    .replaceAll('é', 'e')
    .replaceAll('í', 'i')
    .replaceAll('ó', 'o')
    .replaceAll('ú', 'u')
    .replaceAll(RegExp(r'\s+'), ' ');

/// La lista de resultados: cada Línea con el ícono de su Medio y, si ya está en Mis líneas, el
/// badge "✓ Ya agregada".
class ResultadosDeBusqueda extends StatelessWidget {
  const ResultadosDeBusqueda({
    super.key,
    required this.lineas,
    required this.misLineas,
    required this.onElegir,
    this.agregadasSeEligen = true,
  });

  final List<Linea> lineas;
  final MisLineas misLineas;
  final ValueChanged<Linea> onElegir;

  /// Si se pueden tocar las Líneas que ya están en Mis líneas (en el mapa abren su ficha; para
  /// agregar no tiene sentido elegirlas).
  final bool agregadasSeEligen;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: misLineas,
      builder: (context, _) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [for (final linea in lineas) _resultado(linea)],
      ),
    );
  }

  Widget _resultado(Linea linea) {
    final agregada = misLineas.contiene(linea);
    return ListTile(
      leading: Icon(linea.medio.icono, semanticLabel: linea.medio.nombre),
      title: Text(linea.nombre),
      trailing: agregada ? const YaAgregada() : null,
      onTap: agregada && !agregadasSeEligen ? null : () => onElegir(linea),
    );
  }
}

/// Badge verde "✓ Ya agregada".
class YaAgregada extends StatelessWidget {
  const YaAgregada({super.key});

  static const _verde = Color(0xFF2E7D32);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _verde.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check, size: 16, color: _verde),
          SizedBox(width: 4),
          Text('Ya agregada', style: TextStyle(color: _verde, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Pantalla para buscar una Línea de un Medio y agregarla. Devuelve la Línea elegida, o null si
/// el usuario volvió sin elegir.
class AgregarLineaScreen extends StatefulWidget {
  const AgregarLineaScreen({super.key, required this.misLineas, required this.medio});

  final MisLineas misLineas;
  final Medio medio;

  static Route<Linea> route(MisLineas misLineas, Medio medio) =>
      MaterialPageRoute(builder: (_) => AgregarLineaScreen(misLineas: misLineas, medio: medio));

  @override
  State<AgregarLineaScreen> createState() => _AgregarLineaScreenState();
}

class _AgregarLineaScreenState extends State<AgregarLineaScreen> {
  var _consulta = '';

  @override
  Widget build(BuildContext context) {
    final lineas = buscarLineas(_consulta, medios: {widget.medio});
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          textInputAction: TextInputAction.search,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            hintText: 'Buscar línea de ${widget.medio.nombre}',
            border: InputBorder.none,
          ),
          onChanged: (value) => setState(() => _consulta = value),
        ),
      ),
      body: lineas.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Ninguna línea de ${widget.medio.nombre} coincide con "${_consulta.trim()}".',
                textAlign: TextAlign.center,
              ),
            )
          : ResultadosDeBusqueda(
              lineas: lineas,
              misLineas: widget.misLineas,
              agregadasSeEligen: false,
              onElegir: (linea) => Navigator.pop(context, linea),
            ),
    );
  }
}
