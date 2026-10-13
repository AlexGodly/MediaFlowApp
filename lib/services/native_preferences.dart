// ignore_for_file: prefer_interpolation_to_compose_strings
import 'package:shared_preferences/shared_preferences.dart';
import '../design_system/mediaflow_theme.dart';

/// Device-local presentation preference, isolated per signed-in account.
/// Never modifies the original MediaFlow cloud settings or data.
class NativePreferences {
  NativePreferences({SharedPreferencesAsync? storage})
      : _storage = storage ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _storage;

  String _appearanceKey(String? userId) =>
      'mediaflow_app.native.appearance.' + (userId ?? 'preview');

  Future<MediaFlowAppearance?> loadAppearance(String? userId) async {
    final saved = await _storage.getString(_appearanceKey(userId));
    for (final mode in MediaFlowAppearance.values) {
      if (mode.name == saved) return mode;
    }
    return null;
  }

  Future<void> saveAppearance(
      String? userId, MediaFlowAppearance appearance) async {
    await _storage.setString(_appearanceKey(userId), appearance.name);
  }
}
