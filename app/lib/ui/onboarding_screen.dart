import 'package:material_ui/material_ui.dart';

import '../data/catalogo_de_colectivos.dart';
import '../data/lineas_de_subte.dart';
import '../data/permiso_de_ubicacion.dart';
import '../data/transit_api.dart';
import '../settings/mis_lineas.dart';
import 'buscador_de_lineas.dart';
import 'lineas_comun.dart';

/// Las pantallas del Onboarding, en orden. Las de Líneas aparecen solo si se eligió su Medio.
enum _Paso { medios, lineasDeColectivo, lineasDeSubte, ubicacion }

/// El Onboarding: la primera vez que se abre la app, el usuario elige sus Medios y sus Líneas, y
/// se le explica el permiso de ubicación antes de pedirlo.
///
/// Lo elegido vive en esta pantalla y se guarda en [MisLineas] recién al terminar: si se cierra
/// la app a la mitad, la próxima vez empieza de nuevo. Al guardarlo, la app pasa al mapa.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.api,
    required this.misLineas,
    required this.pedirPermisoDeUbicacion,
  });

  /// Para el catálogo de Colectivo de la pantalla de Líneas de Colectivo.
  final TransitApi api;
  final MisLineas misLineas;
  final PedirPermisoDeUbicacion pedirPermisoDeUbicacion;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _medios = <Medio>{};

  /// Las Líneas elegidas, en el orden en que se eligieron.
  final _lineas = <Linea>[];

  var _paso = _Paso.medios;

  /// El catálogo de Colectivo se pide al llegar a la pantalla de Líneas de Colectivo.
  late final _catalogo = CatalogoDeColectivos(widget.api);

  /// Mientras se pide el permiso y se guarda, los botones no hacen nada (evita guardar dos veces).
  var _terminando = false;

  List<_Paso> get _pasos => [
        _Paso.medios,
        if (_medios.contains(Medio.colectivo)) _Paso.lineasDeColectivo,
        if (_medios.contains(Medio.subte)) _Paso.lineasDeSubte,
        _Paso.ubicacion,
      ];

  /// Marca o desmarca un Medio. Desmarcarlo descarta las Líneas que se habían elegido de él.
  void _alternarMedio(Medio medio) => setState(() {
        if (_medios.remove(medio)) {
          _lineas.removeWhere((l) => l.medio == medio);
        } else {
          _medios.add(medio);
        }
      });

  void _alternarLinea(Linea linea) => setState(() {
        if (!_lineas.remove(linea)) _lineas.add(linea);
      });

  @override
  void dispose() {
    _catalogo.dispose();
    super.dispose();
  }

  void _siguiente() {
    final pasos = _pasos;
    setState(() => _paso = pasos[pasos.indexOf(_paso) + 1]);
  }

  void _volver() {
    final pasos = _pasos;
    setState(() => _paso = pasos[pasos.indexOf(_paso) - 1]);
  }

  /// El botón de una pantalla de Líneas: "Prefiero hacerlo después" mientras no se eligió ninguna
  /// Línea de ese Medio, y "Continuar" apenas se elige una.
  Widget _botonDeLineas(Medio medio) => _lineas.any((l) => l.medio == medio)
      ? FilledButton(onPressed: _siguiente, child: const Text('Continuar'))
      : OutlinedButton(onPressed: _siguiente, child: const Text('Prefiero hacerlo después'));

  /// La última pantalla: pide el permiso (el resultado no importa: sin ubicación la app funciona
  /// igual) y guarda lo elegido.
  Future<void> _pedirUbicacionYTerminar() async {
    if (_terminando) return;
    setState(() => _terminando = true);
    await widget.pedirPermisoDeUbicacion();
    await widget.misLineas.completarOnboarding(medios: _medios, lineas: _lineas);
  }

  /// "Saltar": termina el Onboarding sin Medios ni Líneas y sin pedir la ubicación.
  Future<void> _saltar() async {
    if (_terminando) return;
    setState(() => _terminando = true);
    await widget.misLineas.completarOnboarding(medios: const {}, lineas: const []);
  }

  @override
  Widget build(BuildContext context) {
    final pasos = _pasos;
    final (contenido, boton) = switch (_paso) {
      _Paso.medios => (
          _ElegirMedios(elegidos: _medios, onAlternar: _alternarMedio),
          FilledButton(onPressed: _medios.isEmpty ? null : _siguiente, child: const Text('Continuar')),
        ),
      _Paso.lineasDeColectivo => (
          _ElegirLineasDeColectivo(
            catalogo: _catalogo,
            misLineas: widget.misLineas,
            elegidas: _lineas,
            onAlternar: _alternarLinea,
          ),
          _botonDeLineas(Medio.colectivo),
        ),
      _Paso.lineasDeSubte => (
          _ElegirLineasDeSubte(elegidas: _lineas, onAlternar: _alternarLinea),
          _botonDeLineas(Medio.subte),
        ),
      _Paso.ubicacion => (
          const _ExplicarUbicacion(),
          FilledButton(onPressed: _terminando ? null : _pedirUbicacionYTerminar, child: const Text('Continuar')),
        ),
    };
    return PopScope(
      // El "atrás" del teléfono vuelve a la pantalla anterior del Onboarding.
      canPop: _paso == _Paso.medios,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _volver();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: _paso == _Paso.medios
              ? null
              : IconButton(tooltip: 'Volver', icon: const Icon(Icons.arrow_back), onPressed: _volver),
          actions: [
            if (_paso == _Paso.medios)
              TextButton(onPressed: _terminando ? null : _saltar, child: const Text('Saltar')),
          ],
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                // La pantalla de Colectivo tiene su propia lista de resultados, que se desliza sola.
                child: _paso == _Paso.lineasDeColectivo
                    ? Padding(padding: const EdgeInsets.fromLTRB(24, 8, 24, 0), child: contenido)
                    : SingleChildScrollView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 24), child: contenido),
              ),
              _PuntosDeProgreso(paso: pasos.indexOf(_paso), total: pasos.length),
              Padding(padding: const EdgeInsets.fromLTRB(24, 16, 24, 24), child: boton),
            ],
          ),
        ),
      ),
    );
  }
}

/// Título y explicación de cada pantalla.
class _Encabezado extends StatelessWidget {
  const _Encabezado({required this.titulo, required this.texto});

  final String titulo;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(texto, style: textTheme.bodyLarge?.copyWith(color: Theme.of(context).hintColor)),
        ],
      ),
    );
  }
}

class _ElegirMedios extends StatelessWidget {
  const _ElegirMedios({required this.elegidos, required this.onAlternar});

  final Set<Medio> elegidos;
  final ValueChanged<Medio> onAlternar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Encabezado(
          titulo: '¿Qué medios usás?',
          texto: 'El mapa va a mostrar solo lo que elijas. Podés marcar varios y cambiarlos después en Mis líneas.',
        ),
        for (final medio in Medio.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _CardDeMedio(medio: medio, elegido: elegidos.contains(medio), onTap: () => onAlternar(medio)),
          ),
      ],
    );
  }
}

/// Card de un Medio con su ícono (provisorio, hasta que estén las ilustraciones) y un check.
class _CardDeMedio extends StatelessWidget {
  const _CardDeMedio({required this.medio, required this.elegido, required this.onTap});

  final Medio medio;
  final bool elegido;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      checked: elegido,
      label: medio.nombre,
      excludeSemantics: true,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        color: elegido ? colors.primaryContainer : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: elegido ? colors.primary : colors.outlineVariant, width: elegido ? 2 : 1),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(medio.icono, size: 36, color: elegido ? colors.onPrimaryContainer : null),
                const SizedBox(width: 16),
                Expanded(child: Text(medio.nombre, style: Theme.of(context).textTheme.titleLarge)),
                Icon(
                  elegido ? Icons.check_circle : Icons.circle_outlined,
                  color: elegido ? colors.primary : colors.outline,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Buscador de Líneas de Colectivo, en selección múltiple. Arriba quedan las elegidas, en una fila
/// que se desliza, para verlas aunque la búsqueda cambie. Elegir una Línea incluye todos sus Ramales.
class _ElegirLineasDeColectivo extends StatefulWidget {
  const _ElegirLineasDeColectivo({
    required this.catalogo,
    required this.misLineas,
    required this.elegidas,
    required this.onAlternar,
  });

  final CatalogoDeColectivos catalogo;
  final MisLineas misLineas;
  final List<Linea> elegidas;
  final ValueChanged<Linea> onAlternar;

  @override
  State<_ElegirLineasDeColectivo> createState() => _ElegirLineasDeColectivoState();
}

class _ElegirLineasDeColectivoState extends State<_ElegirLineasDeColectivo> {
  var _consulta = '';

  @override
  void initState() {
    super.initState();
    _cargarCatalogo();
  }

  Future<void> _cargarCatalogo() => cargarCatalogo(widget.catalogo);

  @override
  Widget build(BuildContext context) {
    final elegidas = [for (final l in widget.elegidas) if (l.medio == Medio.colectivo) l];
    // Con el teclado abierto, en un teléfono chico no entra todo: el encabezado ya se leyó y deja
    // lugar a los resultados.
    final tecladoAbierto = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!tecladoAbierto)
          const _Encabezado(
            titulo: '¿Qué líneas de Colectivo usás?',
            texto: 'Buscalas por su número y marcá todas las que quieras: el mapa va a mostrar sus colectivos '
                'en vivo, de todos sus ramales.',
          ),
        if (elegidas.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                for (final linea in elegidas)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InputChip(
                      avatar: Icon(linea.medio.icono),
                      label: Text(linea.nombre),
                      deleteButtonTooltipMessage: 'Quitar ${linea.nombre}',
                      onDeleted: () => widget.onAlternar(linea),
                    ),
                  ),
              ],
            ),
          ),
        TextField(
          textInputAction: TextInputAction.search,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            hintText: 'Buscar línea de Colectivo',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => setState(() => _consulta = value),
        ),
        Expanded(child: ListenableBuilder(listenable: widget.catalogo, builder: (context, _) => _resultados())),
      ],
    );
  }

  Widget _resultados() {
    final catalogo = widget.catalogo;
    if (!catalogo.cargado) return CatalogoNoDisponible(catalogo: catalogo, onReintentar: _cargarCatalogo);
    final lineas = buscarLineas(_consulta, medios: {Medio.colectivo}, colectivos: [for (final l in catalogo.lineas) l.id]);
    if (lineas.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Ninguna línea de Colectivo coincide con "${_consulta.trim()}".', textAlign: TextAlign.center),
      );
    }
    return ResultadosDeBusqueda(
      lineas: lineas,
      misLineas: widget.misLineas,
      seleccionadas: widget.elegidas.toSet(),
      onElegir: widget.onAlternar,
    );
  }
}

class _ElegirLineasDeSubte extends StatelessWidget {
  const _ElegirLineasDeSubte({required this.elegidas, required this.onAlternar});

  final List<Linea> elegidas;
  final ValueChanged<Linea> onAlternar;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Encabezado(
          titulo: '¿Qué líneas de Subte usás?',
          texto: 'Elegí todas las que quieras: el mapa va a mostrar sus estaciones y sus avisos.',
        ),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final subte in LineaDeSubte.todas)
              Semantics(
                button: true,
                checked: elegidas.contains(subte.linea),
                label: subte.nombre,
                excludeSemantics: true,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => onAlternar(subte.linea),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: elegidas.contains(subte.linea) ? colors.primary : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        CirculoDeSubte(linea: subte, size: 64),
                        if (elegidas.contains(subte.linea))
                          Positioned(
                            right: -4,
                            bottom: -4,
                            child: CircleAvatar(
                              radius: 12,
                              backgroundColor: colors.primary,
                              child: Icon(Icons.check, size: 16, color: colors.onPrimary),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ExplicarUbicacion extends StatelessWidget {
  const _ExplicarUbicacion();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.my_location, size: 56, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 24),
        const _Encabezado(
          titulo: 'Tu ubicación',
          texto: 'La usamos para mostrarte dónde estás en el mapa y centrarlo ahí con el botón "Mi ubicación", '
              'así ves qué tenés cerca.\n\n'
              'Al tocar "Continuar", el teléfono te va a pedir el permiso. Si no lo das, la app funciona igual.',
        ),
      ],
    );
  }
}

/// Un punto por pantalla del Onboarding; el de la pantalla actual, resaltado.
class _PuntosDeProgreso extends StatelessWidget {
  const _PuntosDeProgreso({required this.paso, required this.total});

  final int paso;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Paso ${paso + 1} de $total',
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < total; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: i == paso ? 24 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: i == paso ? colors.primary : colors.outlineVariant,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
        ],
      ),
    );
  }
}
