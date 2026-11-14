// The category editor's writes, ported from the website: save (v283 form +
// v369 HH:MM:SS runtime + v286 save + v74 order), delete (v283, with v171's
// recovery slot), restore the last deleted category / missing defaults
// (v171), clear a category's Library titles (v282), reorder (v74 order) and
// the saved icon / colour palettes (v144). test/category_golden_test.dart
// replays fixtures made by running the website's own code.

import 'dart:convert';
import 'dart:math' as math;

import '../util/js.dart';
import 'category_defaults.g.dart';

export 'category_defaults.g.dart' show kColorChoices, kIconChoices;

List<Map<String, dynamic>> get kDefaultCategories =>
    [for (final c in jsonDecode(kDefaultCategoriesJson) as List) (c as Map).cast<String, dynamic>()];

/// `v144SafeIconUrl` / `v200SafeCategoryCoverUrl`: an http(s) link or ''.
String safeCategoryUrl(Object? raw) {
  final v = jsStr(raw).trim();
  if (v.isEmpty) return '';
  final u = Uri.tryParse(v);
  if (u == null || !u.hasScheme || u.host.isEmpty) return '';
  return u.scheme == 'http' || u.scheme == 'https' ? v : '';
}

/// Website v258: MediaFlow's packaged category artwork (`V258_BUILTIN_CATEGORY_ICONS`).
const kBuiltInCategoryIcons = <(String, String)>[
  ('Seasonal Anime', 'assets/category-icons/seasonal-anime.png'),
  ('Missed Anime', 'assets/category-icons/missed-anime.png'),
  ('Finished Anime', 'assets/category-icons/finished-anime.png'),
  ('Anime Movies', 'assets/category-icons/anime-movies.png'),
  ('Anime Backlog', 'assets/category-icons/anime-backlog.png'),
  ('Anime Movies Backlog', 'assets/category-icons/anime-movies-backlog.png'),
  ('Asian Comics', 'assets/category-icons/asian-comics.png'),
  ('Asian Comics Backlog', 'assets/category-icons/asian-comics-backlog.png'),
  ('Movies', 'assets/category-icons/movies.png'),
  ('Movies Backlog', 'assets/category-icons/movies-backlog.png'),
  ('TV Series', 'assets/category-icons/tv-series.png'),
  ('TV Series Backlog', 'assets/category-icons/tv-series-backlog.png'),
  ('Games', 'assets/category-icons/games.png'),
  ('Music', 'assets/category-icons/music.png'),
  ('Books', 'assets/category-icons/books.png'),
  ('Books Backlog', 'assets/category-icons/books-backlog.png'),
  ('Novels', 'assets/category-icons/novels.png'),
  ('Novels Backlog', 'assets/category-icons/novels-backlog.png'),
  ('Magazines', 'assets/category-icons/magazines.png'),
  ('Magazines Backlog', 'assets/category-icons/magazines-backlog.png'),
  ('Online Media', 'assets/category-icons/online-media.png'),
  ('Online Media Backlog', 'assets/category-icons/online-media-backlog.png'),
  ('Comics', 'assets/category-icons/comics.png'),
  ('Comics Backlog', 'assets/category-icons/comics-backlog.png'),
];

/// `v258NormalizeBuiltInCategoryIcon`: the packaged artwork path, or ''.
String builtInCategoryIcon(Object? raw) {
  final v = jsStr(raw).trim().replaceAll('\\', '/').replaceFirst(RegExp(r'^\./'), '').replaceFirst(RegExp(r'^/'), '');
  return kBuiltInCategoryIcons.any((x) => x.$2 == v) ? v : '';
}

/// `v144SafeIconUrl` as extended by v258: an http(s) link, or one of
/// MediaFlow's packaged category icons; else ''.
String safeCategoryIconUrl(Object? raw) {
  final b = builtInCategoryIcon(raw);
  return b.isNotEmpty ? b : safeCategoryUrl(raw);
}

/// What the category editor's fields hold (the website's m-* inputs, as text).
class CategoryForm {
  CategoryForm({
    this.name = '',
    this.icon = '',
    this.iconUrl = '',
    this.missingCover = '',
    this.type = 'video',
    this.unit = 'episodes',
    this.target = '1',
    this.weight = '3',
    this.hours = '0',
    this.minutes = '20',
    this.seconds = '0',
    this.seasonal = false,
    this.color = '',
    this.enabled = true,
  });

  String name, icon, iconUrl, missingCover, type, unit, target, weight, hours, minutes, seconds, color;
  bool seasonal, enabled;

  /// The form filled from a saved category (`categoryModalHtml` + v369).
  factory CategoryForm.of(Map<String, dynamic>? c) {
    final sps = jsNumOrNull(c?['secondsPerUnit']);
    final sec = c != null && c['secondsPerUnit'] != null && sps != null
        ? math.max(1, sps.round())
        : math.max(1, ((jsNum(c?['minutesPerUnit']) == 0 ? 20 : jsNum(c?['minutesPerUnit'])) * 60).round());
    String n(Object? v, String def) => v == null ? def : fmtJs(jsNum(v));
    return CategoryForm(
      name: jsStr(c?['name']),
      icon: jsStr(c?['iconUrl']).isNotEmpty ? '' : jsStr(c?['icon']),
      iconUrl: jsStr(c?['iconUrl']),
      missingCover: jsStr(c?['missingDefaultCoverUrl']),
      type: jsStr(c?['type']).isEmpty ? 'video' : jsStr(c?['type']),
      unit: jsStr(c?['unit']).isEmpty ? 'episodes' : jsStr(c?['unit']),
      target: n(c?['target'], '1'),
      weight: n(c?['weight'], '3'),
      hours: '${sec ~/ 3600}',
      minutes: '${(sec % 3600) ~/ 60}',
      seconds: '${sec % 60}',
      seasonal: c?['seasonal'] == true,
      color: jsStr(c?['color']).isEmpty ? kColorChoices.first : jsStr(c?['color']),
      enabled: c == null || c['enabled'] != false,
    );
  }

  int get totalSeconds {
    int read(String v, int max) => math.max(0, math.min(max, (jsNumOrNull(v.trim()) ?? 0).floor()));
    return math.max(1, read(hours, 9999) * 3600 + read(minutes, 59) * 60 + read(seconds, 59));
  }
}

String fmtJs(num v) => v == v.roundToDouble() ? v.toInt().toString() : '$v';

double _orDefault(Object? v, double def) {
  final n = jsNumOrNull(v);
  return n == null || n == 0 || !n.isFinite ? def : n;
}

void _persistOrder(Map<String, dynamic> state) {
  final order = [for (final c in asList(state['categories'])) asMap(c)?['id']];
  state['categoryOrder'] = order;
  final settings = (asMap(state['settings']) ?? <String, dynamic>{});
  state['settings'] = settings;
  settings['categoryOrder'] = [...order];
}

/// `App.saveCategoryModal`: returns the saved id, or an error message.
({String? id, String? error}) saveCategory(Map<String, dynamic> state, String? id, CategoryForm f, int now, String Function() uid) {
  // v283ReadCategoryForm
  final iconUrl = safeCategoryIconUrl(f.iconUrl);
  final icon = iconUrl.isNotEmpty ? '🖼️' : (f.icon.trim().isEmpty ? '✨' : f.icon.trim());
  final rawMissing = f.missingCover.trim();
  final missing = safeCategoryUrl(rawMissing);
  if (rawMissing.isNotEmpty && missing.isEmpty) return (id: null, error: 'Use a valid http:// or https:// Missing default cover URL.');
  var color = f.color.trim().toUpperCase();
  if (!RegExp(r'^#[0-9A-F]{6}$').hasMatch(color)) color = kColorChoices.first;
  final sid = id ?? '';
  final cats = [for (final c in asList(state['categories'])) c];
  final idx = cats.indexWhere((c) => jsStr(asMap(c)?['id']) == sid);
  final existing = idx >= 0 ? asMap(cats[idx]) : null;
  final oldMissing = safeCategoryUrl(existing?['missingDefaultCoverUrl']);
  final missingModifiedAt = oldMissing != missing ? now : jsNum(existing?['missingDefaultCoverModifiedAt']).toInt();
  final seconds = f.totalSeconds;
  final data = <String, dynamic>{
    'id': sid.isEmpty ? uid() : sid,
    'name': f.name.trim().isEmpty ? 'Untitled category' : f.name.trim(),
    'icon': icon,
    'iconUrl': iconUrl.isEmpty ? null : iconUrl,
    'missingDefaultCoverUrl': missing.isEmpty ? null : missing,
    'missingDefaultCoverModifiedAt': missingModifiedAt,
    'type': f.type,
    'unit': f.unit,
    'target': jsOut(math.max(1.0, _orDefault(f.target, 1))),
    'weight': jsOut(_orDefault(f.weight, 3).clamp(1, 5).toDouble()),
    // v369 replaces the minutes with the HH:MM:SS runtime (same position).
    'minutesPerUnit': jsOut(seconds / 60),
    'seasonal': f.seasonal,
    'color': color,
    'enabled': f.enabled,
    'custom': true,
  };
  data['secondsPerUnit'] = seconds;
  // v286: immutable replace.
  if (idx >= 0) {
    final previous = existing ?? const <String, dynamic>{};
    final next = <String, dynamic>{...previous, ...data, 'id': previous['id'] ?? data['id'], 'modifiedAt': now};
    cats[idx] = next;
  } else {
    cats.add({...data, 'modifiedAt': now});
  }
  state['categories'] = cats;
  _persistOrder(state);
  return (id: jsStr(data['id']), error: null);
}

/// Deletes a category (website v283) and keeps it in the recovery slot
/// (v171's `categoryRecovery`) so Settings can restore it.
String? deleteCategory(Map<String, dynamic> state, String id, int now) {
  final cats = asList(state['categories']);
  final index = cats.indexWhere((c) => jsStr(asMap(c)?['id']) == id);
  if (index < 0) return 'That category no longer exists.';
  final cat = asMap(cats[index])!;
  state['categoryRecovery'] = {'lastDeletedCategory': jsonClone(cat), 'lastDeletedIndex': index, 'modifiedAt': now};
  state['categories'] = [for (final c in cats) if (jsStr(asMap(c)?['id']) != id) c];
  if (state['categoryOrder'] is List) state['categoryOrder'] = [for (final x in asList(state['categoryOrder'])) if (jsStr(x) != id) x];
  _persistOrder(state);
  return null;
}

/// `v171EnsureCategoryState`.
Map<String, dynamic> _recovery(Map<String, dynamic> state) {
  final settings = asMap(state['settings']) ?? <String, dynamic>{};
  state['settings'] = settings;
  if (settings['highlightDefaultCategories'] is! bool) settings['highlightDefaultCategories'] = true;
  final src = asMap(state['categoryRecovery']) ?? const <String, dynamic>{};
  final cat = asMap(src['lastDeletedCategory']);
  final idx = jsNumOrNull(src['lastDeletedIndex']);
  final rec = <String, dynamic>{
    'lastDeletedCategory': cat == null ? null : jsonClone(cat),
    'lastDeletedIndex': idx != null && idx.isFinite ? math.max(-1, idx.floor()) : -1,
    'modifiedAt': jsOut(math.max(0.0, jsNum(src['modifiedAt']))),
  };
  state['categoryRecovery'] = rec;
  return rec;
}

/// The category the recovery slot holds, when it can be restored.
Map<String, dynamic>? lastDeletedCategory(Map<String, dynamic> state) {
  final cat = asMap(asMap(state['categoryRecovery'])?['lastDeletedCategory']);
  if (cat == null) return null;
  final exists = asList(state['categories']).any((c) => jsStr(asMap(c)?['id']) == jsStr(cat['id']));
  return exists ? null : cat;
}

/// `v171RestoreLastDeletedCategory`.
String restoreDeletedCategory(Map<String, dynamic> state, int now) {
  final rec = _recovery(state);
  final cat = asMap(rec['lastDeletedCategory']);
  if (cat == null) return 'There is no deleted category to restore.';
  final cats = [for (final c in asList(state['categories'])) c];
  if (cats.any((c) => jsStr(asMap(c)?['id']) == jsStr(cat['id']))) return 'That category ID already exists.';
  final restored = jsonClone(cat) as Map<String, dynamic>;
  final at = jsNumOrNull(rec['lastDeletedIndex']);
  final index = math.max(0, math.min(cats.length, at != null && at.isFinite ? at.floor() : cats.length));
  cats.insert(index, restored);
  state['categories'] = cats;
  state['categoryRecovery'] = {'lastDeletedCategory': null, 'lastDeletedIndex': -1, 'modifiedAt': now};
  _persistOrder(state);
  return '${jsStr(restored['name']).isEmpty ? 'Category' : jsStr(restored['name'])} restored';
}

/// The default categories missing from the account (`v171MissingDefaultCategories`).
List<Map<String, dynamic>> missingDefaultCategories(Map<String, dynamic> state) {
  final have = {for (final c in asList(state['categories'])) jsStr(asMap(c)?['id'])};
  return [for (final c in kDefaultCategories) if (!have.contains(jsStr(c['id']))) c];
}

/// `v171RestoreDefaultCategories`.
String restoreDefaultCategories(Map<String, dynamic> state) {
  final missing = missingDefaultCategories(state);
  if (missing.isEmpty) return 'All default categories are already present.';
  final cats = [for (final c in asList(state['categories'])) c];
  for (final c in missing) {
    cats.add({...c, 'id': jsStr(c['id']), 'custom': false});
  }
  state['categories'] = cats;
  _persistOrder(state);
  final n = missing.length;
  return '$n default categor${n == 1 ? 'y' : 'ies'} restored with original IDs';
}

/// `v282ConfirmCategoryClear`: removes the category's Library titles (kept in
/// the activity log so Library History can restore them).
String clearCategory(Map<String, dynamic> state, String id, int now, String Function() uid) {
  final cat = asList(state['categories']).map(asMap).whereType<Map<String, dynamic>>().where((c) => jsStr(c['id']) == id).firstOrNull;
  if (cat == null) return 'That category no longer exists.';
  final kept = <dynamic>[], removed = <dynamic>[];
  for (final item in asList(state['library'])) {
    (jsStr(asMap(item)?['categoryId']) == id ? removed : kept).add(item);
  }
  final name = jsStr(cat['name']);
  if (removed.isEmpty) return '$name is already empty';
  state['library'] = kept;
  final log = [for (final x in asList(state['activityLog'])) x];
  log.insert(0, {
    'id': uid(),
    'timestamp': now,
    'action': 'Clear category',
    'detail': '$name · ${removed.length} titles',
    'deletedItems': [...removed],
    'restoreVersion': 191,
  });
  if (log.length > 1000) log.length = 1000;
  state['activityLog'] = log;
  return '$name cleared · ${removed.length} titles';
}

/// Moves a category (the order every page shows them in).
void moveCategory(Map<String, dynamic> state, String id, int to) {
  final cats = [for (final c in asList(state['categories'])) c];
  final from = cats.indexWhere((c) => jsStr(asMap(c)?['id']) == id);
  if (from < 0) return;
  final target = to.clamp(0, cats.length - 1);
  if (target == from) return;
  cats.insert(target, cats.removeAt(from));
  state['categories'] = cats;
  _persistOrder(state);
}

// ---- saved palettes (v144) ----

/// `v144NormalizeCustomCategoryIcons`.
List<Map<String, dynamic>> savedCategoryIcons(Map<String, dynamic>? settings) {
  final out = <Map<String, dynamic>>[];
  final seen = <String>{};
  for (final raw in asList(settings?['customCategoryIcons'])) {
    final row = asMap(raw);
    if (row == null) continue;
    final type = row['type'] == 'url' ? 'url' : 'emoji';
    var value = jsStr(row['value']).trim();
    if (type == 'url') {
      value = safeCategoryIconUrl(value);
      if (value.isEmpty) continue;
    } else {
      if (value.isEmpty) continue;
      value = value.runes.take(12).map(String.fromCharCode).join();
    }
    if (!seen.add('$type:$value')) continue;
    out.add({'type': type, 'value': value});
  }
  return out;
}

/// `v144NormalizeCustomCategoryColors`.
List<String> savedCategoryColors(Map<String, dynamic>? settings) {
  final out = <String>[];
  for (final raw in asList(settings?['customCategoryColors'])) {
    var v = jsStr(raw).trim().toUpperCase();
    if (RegExp(r'^#[0-9A-F]{3}$').hasMatch(v)) v = '#${v.substring(1).split('').map((x) => '$x$x').join()}';
    if (!RegExp(r'^#[0-9A-F]{6}$').hasMatch(v) || out.contains(v)) continue;
    out.add(v);
  }
  return out;
}

/// A hex colour as the palette saves it, or null when it isn't one.
String? normalizeHexColor(String raw) {
  var v = raw.trim().toUpperCase();
  if (!v.startsWith('#')) v = '#$v';
  if (RegExp(r'^#[0-9A-F]{3}$').hasMatch(v)) v = '#${v.substring(1).split('').map((x) => '$x$x').join()}';
  return RegExp(r'^#[0-9A-F]{6}$').hasMatch(v) ? v : null;
}
