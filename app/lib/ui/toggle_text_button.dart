import 'package:material_ui/material_ui.dart';

/// Opciones visuales de [ToggleTextButton]. Para agregar una, sumá el campo acá
/// y leelo en [ToggleTextButton.build].
class ToggleTextButtonCustomization {
  const ToggleTextButtonCustomization({this.borderColor});

  /// Color del borde cuando el botón está activo. Si es null, gris oscuro.
  final Color? borderColor;
}

/// Botón de texto que se prende y apaga. Activo, muestra un borde de color.
class ToggleTextButton extends StatelessWidget {
  const ToggleTextButton({
    super.key,
    required this.text,
    required this.onTap,
    required this.isActive,
    this.customization = const ToggleTextButtonCustomization(),
  });

  final String text;
  final VoidCallback onTap;
  final bool isActive;
  final ToggleTextButtonCustomization customization;

  static const borderWidth = 2.0;

  /// Gris oscuro en tema claro; en tema oscuro, gris claro para que se vea sobre el fondo.
  static Color defaultBorderColor(ColorScheme colors) => colors.onSurfaceVariant;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final borderColor = customization.borderColor ?? defaultBorderColor(colors);
    // Inactivo lleva un borde transparente del mismo ancho, para que el botón no cambie de tamaño.
    final shape = StadiumBorder(
      side: BorderSide(color: isActive ? borderColor : Colors.transparent, width: borderWidth),
    );

    return Semantics(
      button: true,
      toggled: isActive,
      child: Material(
        color: colors.surface,
        elevation: 2,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(text),
          ),
        ),
      ),
    );
  }
}
