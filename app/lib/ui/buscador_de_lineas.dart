import 'package:material_ui/material_ui.dart';

import '../data/catalogo_de_colectivos.dart';
import '../data/lineas_de_subte.dart';
import '../data/transit_api.dart';
import '../settings/mis_lineas.dart';
import 'lineas_comun.dart';

// El buscador de Líneas: lo usan el mapa (tocar un resultado abre su ficha) y el "+" de la
// pantalla Mis líneas (tocar un resultado lo agrega). Busca en las Líneas de Subte y en el catálogo
// de Colectivo.

/// Los Medios en los que se puede buscar (Ecobici no tiene Líneas).
const mediosBuscables = {Medio.colectivo, Medio.subte};

/// Las Líneas de los [medios] pedidos cuyo nombre empieza como [consulta]: primero las de
/// Colectivo, en el orden de [colectivos] (los números del catálogo), y después las de Subte.
/// Ignora mayúsculas, tildes y un "Línea", "Subte" o "Colectivo" adelante; una consulta vacía
/// devuelve todas.
List<Linea> buscarLineas(
  String consulta, {
  Set<Medio> medios = mediosBuscables,
  Iterable<String> colectivos = const [],
}) {
  final q = _normalizar(consulta).replaceFirst(RegExp(r'^((linea|subte|colectivo)\b\s*)*'), '');
  return [
    if (medios.contains(Medio.colectivo))
      for (final id in colectivos)
        if (_normalizar(id).startsWith(q)) Linea(Medio.colectivo, id),
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
      // El catálogo de Colectivo tiene cientos de Líneas: se arman solo las que se ven.
      builder: (context, _) => ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: lineas.length,
        itemBuilder: (context, i) => _resultado(lineas[i]),
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
  const AgregarLineaScreen({super.key, required this.misLineas, required this.catalogo, required this.medio});

  final MisLineas misLineas;
  final CatalogoDeColectivos catalogo;
  final Medio medio;

  static Route<Linea> route(MisLineas misLineas, CatalogoDeColectivos catalogo, Medio medio) => MaterialPageRoute(
        builder: (_) => AgregarLineaScreen(misLineas: misLineas, catalogo: catalogo, medio: medio),
      );

  @override
  State<AgregarLineaScreen> createState() => _AgregarLineaScreenState();
}

class _AgregarLineaScreenState extends State<AgregarLineaScreen> {
  var _consulta = '';

  @override
  void initState() {
    super.initState();
    _cargarCatalogo();
  }

  /// Si el catálogo de Colectivo no llegó (p. ej. sin conexión al abrir el mapa), se pide de nuevo.
  /// El error queda en el catálogo y se muestra en pantalla.
  Future<void> _cargarCatalogo() async {
    if (widget.medio != Medio.colectivo) return;
    try {
      await widget.catalogo.cargar();
    } on ApiException {
      // Se muestra con el botón para reintentar.
    }
  }

  @override
  Widget build(BuildContext context) {
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
      body: ListenableBuilder(listenable: widget.catalogo, builder: (context, _) => _resultados()),
    );
  }

  Widget _resultados() {
    final catalogo = widget.catalogo;
    final lineas = buscarLineas(_consulta, medios: {widget.medio}, colectivos: [for (final l in catalogo.lineas) l.id]);
    if (widget.medio == Medio.colectivo && !catalogo.cargado) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: catalogo.error == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(catalogo.error!, textAlign: TextAlign.center),
                  TextButton(onPressed: _cargarCatalogo, child: const Text('Reintentar')),
                ],
              ),
      );
    }
    if (lineas.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Ninguna línea de ${widget.medio.nombre} coincide con "${_consulta.trim()}".',
          textAlign: TextAlign.center,
        ),
      );
    }
    return ResultadosDeBusqueda(
      lineas: lineas,
      misLineas: widget.misLineas,
      agregadasSeEligen: false,
      onElegir: (linea) => Navigator.pop(context, linea),
    );
  }
}
