import '../logic/title_names.dart';
import '../util/js.dart';

/// Unit labels, identical to the website's UNITS table.
const Map<String, List<String>> kUnits = {
  'episodes': ['episode', 'episodes'],
  'chapters': ['chapter', 'chapters'],
  'movies': ['movie', 'movies'],
  'issues': ['issue', 'issues'],
  'sessions': ['session', 'sessions'],
  'videos': ['video', 'videos'],
  'pages': ['page', 'pages'],
  'volumes': ['volume', 'volumes'],
  'tracks': ['track', 'tracks'],
  'albums': ['album', 'albums'],
  'levels': ['level', 'levels'],
  'missions': ['mission', 'missions'],
  'matches': ['match', 'matches'],
  'lessons': ['lesson', 'lessons'],
  'items': ['item', 'items'],
};

String unitLabel(String unit, num count) {
  // Website v565: a title's own unit ("rounds") reads as typed; singular is a best guess.
  if (unit.isNotEmpty && !kUnits.containsKey(unit)) return count == 1 ? unitSingular(unit) : unit;
  final u = kUnits[unit] ?? kUnits['episodes']!;
  return count == 1 ? u[0] : u[1];
}

/// Website v565 `mf565Singular`.
String unitSingular(String word) {
  if (RegExp(r'(ch|sh|ss|x|z)es$', caseSensitive: false).hasMatch(word)) return word.substring(0, word.length - 2);
  if (RegExp(r'[^aeiou]ies$', caseSensitive: false).hasMatch(word)) return '${word.substring(0, word.length - 3)}y';
  if (RegExp(r'[^s]s$', caseSensitive: false).hasMatch(word)) return word.substring(0, word.length - 1);
  return word;
}

/// Read-only view of one category in the account state.
class Category {
  Category(this.raw);
  final Map<String, dynamic> raw;

  String get id => jsStr(raw['id']);
  String get name => jsStr(raw['name']).isEmpty ? 'Category' : jsStr(raw['name']);
  String get icon => jsStr(raw['icon']);
  String get iconUrl => jsStr(raw['iconUrl']);
  String get color => jsStr(raw['color']);
  String get unit => jsStr(raw['unit']).isEmpty ? 'episodes' : jsStr(raw['unit']);
  double get minutesPerUnit => jsNum(raw['minutesPerUnit']);
  double? get target => jsNumOrNull(raw['target']);
  bool get enabled => raw['enabled'] != false;

  /// The website's `getCategory()` fallback for removed categories.
  static Category removed(String id) => Category({
        'id': id, 'name': '(removed category)', 'icon': '❔', 'color': '#555', 'unit': 'episodes',
        'target': 1, 'minutesPerUnit': 10, 'weight': 1, 'enabled': false,
      });
}

/// Read-only view of a Library title.
class LibraryTitle {
  LibraryTitle(this.raw, [this._shown]);
  final Map<String, dynamic> raw;

  /// v565: the name chosen for display (title-language settings), when it differs.
  final String? _shown;

  String get id => jsStr(raw['id']);

  /// The name shown for this title (website v565 mf565DisplayTitle).
  String get title => _shown ?? mainTitle;

  /// The stored main title: matching, imports, recovery and History use it.
  String get mainTitle => cleanTitle(raw['title']).isEmpty ? 'Untitled' : cleanTitle(raw['title']);
  String get categoryId => jsStr(raw['categoryId']);
  String get status => jsStr(raw['status']).isEmpty ? 'planned' : jsStr(raw['status']);
  double get progress => jsNum(raw['progress']);
  double? get total {
    final t = jsNumOrNull(raw['total']);
    return raw['total'] == null || t == null || t <= 0 ? null : t;
  }

  String get coverUrl => jsStr(raw['coverUrl']);
  double? get rating => raw['rating'] == null ? null : jsNumOrNull(raw['rating']);
  int get modifiedAt => jsNum(raw['modifiedAt']).toInt();
  int get createdAt => jsNum(raw['createdAt']).toInt();
  List<dynamic> get seasons => asList(raw['seasons']);

  /// `v120IsCompleted` / `v179IsComplete`.
  bool get isCompleted =>
      status == 'completed' || (total != null && progress >= total!);

  /// Where a "reached" log starts: completed titles start a rewatch from 0.
  double get logStart => isCompleted ? 0 : (progress < 0 ? 0 : progress);
}

/// Read-only view of a History log (a "session" in the website's data).
class LogRecord {
  LogRecord(this.raw);
  final Map<String, dynamic> raw;

  String get id => jsStr(raw['id']);
  int get timestamp => jsNum(raw['timestamp']).toInt();
  String get date => jsStr(raw['date']);
  String get categoryId => jsStr(raw['categoryId']);
  String get status => jsStr(raw['status']);
  String get source => jsStr(raw['source']);
  String get note => jsStr(raw['note']);
  String get unit => jsStr(raw['unit']);
  double get amount => jsNum(raw['actualAmount']);
  double get minutes => jsNum(raw['minutes']);
  bool get skipped => status == 'skipped';
  double get xp {
    final withStreak = jsNumOrNull(raw['xpWithStreak']);
    if (raw.containsKey('xpWithStreak') && withStreak != null) return withStreak;
    return jsNum(raw['xp']);
  }

  List<Map<String, dynamic>> get titles =>
      asList(raw['titles']).map(asMap).whereType<Map<String, dynamic>>().toList();

  String get titleSummary {
    final names = titles.map((t) => cleanTitle(t['title'])).where((t) => t.isNotEmpty).toList();
    if (names.isNotEmpty) return names.join(', ');
    return note;
  }
}

/// Library items as titles, each showing the name chosen by the title-language
/// settings (website v565). The common case (no name settings) costs nothing.
List<LibraryTitle> libraryTitlesFor(Map<String, dynamic>? settings, List<Map<String, dynamic>> items) {
  if (!namesInUse(settings, items)) return [for (final i in items) LibraryTitle(i)];
  final prefs = namePrefs(settings);
  return [
    for (final i in items)
      LibraryTitle(i, () {
        final shown = displayTitle(i, prefs);
        return shown.isEmpty || shown == cleanTitle(i['title']) ? null : shown;
      }()),
  ];
}

/// Convenience accessors over the whole account state.
class AccountView {
  AccountView(this.state) {
    for (final c in asList(state['categories'])) {
      final m = asMap(c);
      if (m != null) {
        final cat = Category(m);
        categories.add(cat);
        _categories.putIfAbsent(cat.id, () => cat);
      }
    }
  }

  final Map<String, dynamic> state;
  final List<Category> categories = [];

  // Built on first use: a new view is made after every change, and most
  // screens never look at every log.
  late final List<LibraryTitle> library =
      libraryTitlesFor(asMap(state['settings']), [for (final i in asList(state['library'])) if (asMap(i) != null) asMap(i)!]);

  /// v565: main title → shown name, for text that stores a title by name
  /// (History, On This Day). A main name shared by titles that show different
  /// names is left as it is (website mf565RebuildNameMap).
  late final Map<String, String> shownNames = () {
    final map = <String, String>{}, clash = <String>{};
    for (final t in library) {
      final main = t.mainTitle;
      if (clash.contains(main)) continue;
      final shown = t.title;
      if (map.containsKey(main) && map[main] != shown) {
        map.remove(main);
        clash.add(main);
        continue;
      }
      if (shown != main) map[main] = shown;
    }
    return map;
  }();

  /// The name to show for a title stored by its main name.
  String shownName(String main) => shownNames[main.trim()] ?? main;
  late final List<LogRecord> logs = [
    for (final s in asList(state['sessions']))
      if (asMap(s) != null) LogRecord(asMap(s)!),
  ];
  final Map<String, Category> _categories = {};

  Category category(String id) => _categories[id] ?? Category.removed(id);
  String get profileName => jsStr(state['profileName']);
}
