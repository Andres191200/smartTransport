import 'package:material_ui/material_ui.dart';

import '../data/lineas_de_subte.dart';
import '../settings/mis_lineas.dart';

/// Pantalla Mis líneas: las Líneas del usuario agrupadas por Medio, para agregarlas y sacarlas.
/// Por ahora solo tiene el grupo Subte.
class MisLineasScreen extends StatelessWidget {
  const MisLineasScreen({super.key, required this.misLineas});

  final MisLineas misLineas;

  static Route<void> route(MisLineas misLineas) =>
      MaterialPageRoute(builder: (_) => MisLineasScreen(misLineas: misLineas));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mis líneas')),
      body: ListenableBuilder(
        listenable: misLineas,
        builder: (context, _) => ListView(
          children: [_GrupoSubte(misLineas: misLineas)],
        ),
      ),
    );
  }
}

class _GrupoSubte extends StatelessWidget {
  const _GrupoSubte({required this.misLineas});

  final MisLineas misLineas;

  @override
  Widget build(BuildContext context) {
    final mias = [for (final l in misLineas.lineasDe(Medio.subte)) LineaDeSubte.porId(l.id)];
    final disponibles = [for (final l in LineaDeSubte.todas) if (!misLineas.contiene(l.linea)) l];
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
          child: Row(
            children: [
              const Icon(Icons.subway_outlined),
              const SizedBox(width: 12),
              Expanded(child: Text('Subte', style: text.titleMedium)),
              IconButton(
                tooltip: 'Agregar línea de Subte',
                icon: const Icon(Icons.add),
                onPressed: disponibles.isEmpty ? null : () => _agregar(context, disponibles),
              ),
            ],
          ),
        ),
        if (mias.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Todavía no agregaste líneas de Subte.',
              style: text.bodyMedium?.copyWith(color: Theme.of(context).hintColor),
            ),
          ),
        for (final linea in mias)
          ListTile(
            leading: ExcludeSemantics(child: CirculoDeSubte(linea: linea, size: 36)),
            title: Text(linea.nombre),
            trailing: IconButton(
              tooltip: 'Eliminar ${linea.conArticulo}',
              icon: const Icon(Icons.close),
              onPressed: () => _eliminar(context, linea),
            ),
          ),
      ],
    );
  }

  Future<void> _agregar(BuildContext context, List<LineaDeSubte> disponibles) async {
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

  Future<void> _eliminar(BuildContext context, LineaDeSubte linea) async {
    final messenger = ScaffoldMessenger.of(context);
    final eliminada = await misLineas.eliminar(linea.linea);
    if (eliminada == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Eliminaste ${linea.conArticulo}'),
        // Se va solo, como cualquier aviso: deshacer es una oportunidad, no una pregunta.
        persist: false,
        action: SnackBarAction(label: 'Deshacer', onPressed: () => misLineas.deshacer(eliminada)),
      ));
  }
}

/// Círculo del color de una Línea de Subte con su letra, como en las estaciones.
class CirculoDeSubte extends StatelessWidget {
  const CirculoDeSubte({super.key, required this.linea, this.size = 40});

  final LineaDeSubte linea;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: linea.nombre,
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: linea.color, shape: BoxShape.circle),
        child: Text(
          linea.sigla,
          style: TextStyle(color: linea.textColor, fontWeight: FontWeight.w700, fontSize: size * 0.45),
        ),
      ),
    );
  }
}
