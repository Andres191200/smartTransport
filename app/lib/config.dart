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

  /// Plantilla de tiles del mapa base. Los tiles de openstreetmap.org sirven para desarrollo,
  /// pero su política no permite apps con mucho tráfico: antes de publicar, usá un proveedor
  /// con plan para apps (MapTiler, Stadia Maps, Thunderforest, etc.) y pasalo por acá.
  static const tileUrlTemplate = String.fromEnvironment(
    'TILE_URL',
    defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  );

  static const tileAttribution = String.fromEnvironment(
    'TILE_ATTRIBUTION',
    defaultValue: '© OpenStreetMap contributors',
  );

  /// Identifica la app ante el servidor de tiles (lo exige la política de OSM).
  static const userAgentPackageName = 'com.smarttransport.smart_transport';
}
