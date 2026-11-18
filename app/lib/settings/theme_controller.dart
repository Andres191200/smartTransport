import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tema elegido por el usuario. Sigue al sistema hasta que lo cambia a mano;
/// la elección se guarda en el dispositivo.
class ThemeController extends ChangeNotifier {
  ThemeController._(this._prefs, this._mode);

  static const _key = 'theme_mode';

  final SharedPreferencesAsync _prefs;
  ThemeMode _mode;

  ThemeMode get mode => _mode;

  static Future<ThemeController> load([SharedPreferencesAsync? prefs]) async {
    prefs ??= SharedPreferencesAsync();
    final saved = await prefs.getString(_key);
    final mode = ThemeMode.values.where((m) => m.name == saved).firstOrNull ?? ThemeMode.system;
    return ThemeController._(prefs, mode);
  }

  /// Si el modo oscuro está activo, contando el del sistema cuando no hay elección.
  bool isDark(Brightness platformBrightness) =>
      _mode == ThemeMode.dark || (_mode == ThemeMode.system && platformBrightness == Brightness.dark);

  Future<void> setDark(bool dark) async {
    _mode = dark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    await _prefs.setString(_key, _mode.name);
  }
}
