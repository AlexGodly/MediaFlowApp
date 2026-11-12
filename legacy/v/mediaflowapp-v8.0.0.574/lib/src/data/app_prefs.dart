// App-only preferences (this device), separate from the account's website
// settings: start tab, theme, sync and storage options, layouts, reminders…
// Stored as a small JSON file next to the account cache.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class AppPrefs extends ChangeNotifier {
  AppPrefs._();
  static final AppPrefs instance = AppPrefs._();

  Map<String, dynamic> _values = {};
  bool _loaded = false;

  bool get loaded => _loaded;

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}mediaflow-app-settings.json');
  }

  Future<void> load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        final v = jsonDecode(await f.readAsString());
        if (v is Map) _values = v.cast<String, dynamic>();
      }
    } catch (_) {
      // Defaults.
    }
    _loaded = true;
    notifyListeners();
  }

  T get<T>(String key, T fallback) {
    final v = _values[key];
    return v is T ? v : fallback;
  }

  Future<void> set(String key, Object? value) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
    notifyListeners();
    try {
      final f = await _file();
      await f.parent.create(recursive: true);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(_values), flush: true);
      await tmp.rename(f.path);
    } catch (_) {}
  }

  /// For tests.
  @visibleForTesting
  void reset([Map<String, dynamic>? values]) {
    _values = {...?values};
    _loaded = true;
  }
}
