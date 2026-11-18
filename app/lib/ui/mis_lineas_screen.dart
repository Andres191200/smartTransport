import 'package:material_ui/material_ui.dart';

import '../data/catalogo_de_colectivos.dart';
import '../data/lineas_de_subte.dart';
import '../settings/mis_lineas.dart';
import 'buscador_de_lineas.dart';
import 'lineas_comun.dart';

/// Pantalla Mis líneas: las Líneas del usuario agrupadas por Medio, para agregarlas y sacarlas.
/// Tiene los grupos Colectivo, Subte y Ecobici. El "+" de la barra pregunta el Medio y abre el
/// buscador de ese Medio.
class MisLineasScreen extends StatelessWidget {
  const MisLineasScreen({super.key, required this.misLineas, required this.catalogo});

  final MisLineas misLineas;
  final CatalogoDeColectivos catalogo;

  static Route<void> route(MisLineas misLineas, CatalogoDeColectivos catalogo) =>
      MaterialPageRoute(builder: (_) => MisLineasScreen(misLineas: misLineas, catalogo: catalogo));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis líneas'),
        actions: [
          IconButton(tooltip: 'Agregar línea', icon: const Icon(Icons.add), onPressed: () => _agregar(context)),
        ],
      ),
      body: ListenableBuilder(
        listenable: misLineas,
        builder: (context, _) => ListView(
          children: [
            _GrupoDeLineas(
              misLineas: misLineas,
              medio: Medio.colectivo,
              onAgregar: (context) => _buscarYAgregar(context, Medio.colectivo),
            ),
            _GrupoDeLineas(
              misLineas: misLineas,
              medio: Medio.subte,
              onAgregar: _subteDisponibles.isEmpty ? null : _agregarSubte,
            ),
            _GrupoEcobici(misLineas: misLineas),
          ],
        ),
      ),
    );
  }

  /// Pregunta de qué Medio es la Línea y abre el buscador filtrado por ese Medio.
  Future<void> _agregar(BuildContext context) async {
    final medio = await showModalBottomSheet<Medio>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('¿De qué Medio es la línea?', style: Theme.of(context).textTheme.titleLarge),
            ),
            for (final medio in mediosBuscables)
              ListTile(
                leading: Icon(medio.icono),
                title: Text(medio.nombre),
                onTap: () => Navigator.pop(context, medio),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (medio != null && context.mounted) await _buscarYAgregar(context, medio);
  }

  /// Abre el buscador de Líneas de ese Medio y agrega la elegida.
  Future<void> _buscarYAgregar(BuildContext context, Medio medio) async {
    final linea = await Navigator.of(context).push(AgregarLineaScreen.route(misLineas, catalogo, medio));
    if (linea != null) await misLineas.agregar(linea);
  }

  List<LineaDeSubte> get _subteDisponibles =>
      [for (final l in LineaDeSubte.todas) if (!misLineas.contiene(l.linea)) l];

  /// El "+" de Subte ofrece las Líneas que faltan como círculos de su color.
  Future<void> _agregarSubte(BuildContext context) async {
    final disponibles = _subteDisponibles;
    final elegida = await showModalBottomSheet<LineaDeSubte>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Agregar línea de Subte', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final linea in disponibles)
                    Semantics(
                      button: true,
                      label: linea.nombre,
                      excludeSemantics: true,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => Navigator.pop(context, linea),
                        child: CirculoDeSubte(linea: linea, size: 56),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (elegida != null) await misLineas.agregar(elegida.linea);
  }
}

/// Encabezado de un grupo de la pantalla: el ícono y el nombre del Medio y, si se pasa, su "+".
class _EncabezadoDeGrupo extends StatelessWidget {
  const _EncabezadoDeGrupo({required this.medio, this.agregar});

  final Medio medio;

  /// El botón "+" del grupo. Null en Ecobici, que no tiene Líneas.
  final Widget? agregar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, agregar == null ? 16 : 8, 4),
      child: Row(
        children: [
          Icon(medio.icono),
          const SizedBox(width: 12),
          Expanded(child: Text(medio.nombre, style: Theme.of(context).textTheme.titleMedium)),
          ?agregar,
        ],
      ),
    );
  }
}

/// El grupo de un Medio con Líneas: sus Líneas en orden de agregado, cada una con su ✕, y el
/// "+" para agregar más. El grupo se ve aunque se quede sin Líneas.
class _GrupoDeLineas extends StatelessWidget {
  const _GrupoDeLineas({required this.misLineas, required this.medio, required this.onAgregar});

  final MisLineas misLineas;
  final Medio medio;

  /// Lo que hace el "+". Null lo deshabilita (p. ej. si ya están todas las Líneas de Subte).
  final Future<void> Function(BuildContext context)? onAgregar;

  @override
  Widget build(BuildContext context) {
    final mias = misLineas.lineasDe(medio);
    final onAgregar = this.onAgregar;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _EncabezadoDeGrupo(
          medio: medio,
          agregar: IconButton(
            tooltip: 'Agregar línea de ${medio.nombre}',
            icon: const Icon(Icons.add),
            onPressed: onAgregar == null ? null : () => onAgregar(context),
          ),
        ),
        if (mias.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Todavía no agregaste líneas de ${medio.nombre}.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).hintColor),
            ),
          ),
        for (final linea in mias)
          ListTile(
            leading: ExcludeSemantics(child: IconoDeLinea(linea: linea, size: 36)),
            title: Text(linea.nombre),
            trailing: IconButton(
              tooltip: 'Eliminar ${linea.conArticulo}',
              icon: const Icon(Icons.close),
              onPressed: () => eliminarConDeshacer(ScaffoldMessenger.of(context), misLineas, linea),
            ),
          ),
      ],
    );
  }
}

/// Ecobici no tiene Líneas: su grupo solo decide si las estaciones se muestran al abrir la app,
/// que es lo mismo que tener Ecobici entre los Medios elegidos.
class _GrupoEcobici extends StatelessWidget {
  const _GrupoEcobici({required this.misLineas});

  final MisLineas misLineas;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _EncabezadoDeGrupo(medio: Medio.ecobici),
        SwitchListTile(
          title: const Text('Mostrar estaciones al abrir la app'),
          value: misLineas.medios.contains(Medio.ecobici),
          onChanged: (on) => on ? misLineas.elegir(Medio.ecobici) : misLineas.quitar(Medio.ecobici),
        ),
      ],
    );
  }
}
