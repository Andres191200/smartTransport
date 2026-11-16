/// Configuración de compilación. Se cambia sin tocar el código con --dart-define, p. ej.:
///
///   flutter run --dart-define=API_BASE_URL=http://192.168.0.10:8080
///
/// La app NUNCA lleva las credenciales de la API Transporte: esas viven solo en el backend.
class AppConfig {
  /// URL del backend (carpeta /backend del repo).
  /// Por defecto 10.0.2.2, que en el emulador de Android apunta al localhost de tu PC.
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8080',
  );

  /// Estilos del mapa base (formato Mapbox/MapLibre GL, tiles vectoriales). Por defecto
  /// OpenFreeMap: gratis, sin clave y con uso comercial permitido (ver docs/adr/0001).
  /// Positron en tema claro, Dark en tema oscuro.
  static const mapStyleLight = String.fromEnvironment(
    'MAP_STYLE_LIGHT',
    defaultValue: 'https://tiles.openfreemap.org/styles/positron',
  );

  static const mapStyleDark = String.fromEnvironment(
    'MAP_STYLE_DARK',
    defaultValue: 'https://tiles.openfreemap.org/styles/dark',
  );

  static const mapAttribution = String.fromEnvironment(
    'MAP_ATTRIBUTION',
    defaultValue: 'OpenFreeMap © OpenMapTiles © OpenStreetMap contributors',
  );
}
