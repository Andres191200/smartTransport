import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';

/// Fila de botones de arriba del mapa: se desliza horizontalmente y, mientras quedan botones
/// fuera de pantalla a la derecha, muestra en ese borde un degradado con blur que deja ver con
/// poca opacidad el botón siguiente.
class FilaDeBotones extends StatefulWidget {
  const FilaDeBotones({super.key, required this.children, this.padding = EdgeInsets.zero, this.fadeColor});

  final List<Widget> children;

  /// Margen alrededor de los botones, dentro de la zona que se desliza.
  final EdgeInsets padding;

  /// Color hacia el que se funde el borde derecho: el del fondo que hay detrás de la fila.
  /// Si es null, el de la superficie del tema.
  final Color? fadeColor;

  /// Identifica el degradado del borde derecho (para los tests).
  static const degradadoKey = ValueKey('FilaDeBotones.degradado');

  static const _fadeWidth = 48.0;
  static const _spacing = 8.0;

  @override
  State<FilaDeBotones> createState() => _FilaDeBotonesState();
}

class _FilaDeBotonesState extends State<FilaDeBotones> {
  bool _hayMasALaDerecha = false;

  /// Se llama al deslizar y cada vez que cambia el ancho del contenido (p. ej. al sumar una Línea).
  bool _onScroll(ScrollMetrics metrics) {
    final hayMas = metrics.extentAfter > 0.5;
    if (hayMas != _hayMasALaDerecha) setState(() => _hayMasALaDerecha = hayMas);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.fadeColor ?? Theme.of(context).colorScheme.surface;
    return Stack(
      children: [
        NotificationListener<ScrollMetricsNotification>(
          onNotification: (n) => _onScroll(n.metrics),
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) => _onScroll(n.metrics),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: widget.padding,
              child: Row(
                children: [
                  for (final (i, child) in widget.children.indexed) ...[
                    if (i > 0) const SizedBox(width: FilaDeBotones._spacing),
                    child,
                  ],
                ],
              ),
            ),
          ),
        ),
        if (_hayMasALaDerecha)
          Positioned(
            key: FilaDeBotones.degradadoKey,
            top: 0,
            bottom: 0,
            right: 0,
            width: FilaDeBotones._fadeWidth,
            child: IgnorePointer(
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [color.withValues(alpha: 0), color.withValues(alpha: 0.85)],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
