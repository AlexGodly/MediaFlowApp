// A title's names in every language (website v565, 411-v565-titles.js).
//
// Library item fields:
//   mf565Names         [{lang,text,source}]  names in other languages (manual or recovered)
//   mf565NameLanguage  '' (follow settings) or a language code for this title
//   mf565NameExempt    true: always show the main title, whatever the settings say
// Settings: settings.mf565TitleNames = {global: 'main'|lang, categories: {categoryId: lang}}
// The main title (item.title) never changes: only what is shown changes, and
// search finds a title by any of its names.

import 'dart:convert';

import '../util/js.dart';

/// `MF565_LANGS`: code and label, in the website's order.
const List<(String, String)> kTitleLanguages = [
  ('main', 'Main title'),
  ('en', 'English'),
  ('ja-Latn', 'Romanised Japanese'),
  ('ja', 'Japanese'),
  ('zh', 'Chinese'),
  ('zh-Latn', 'Romanised Chinese (pinyin)'),
  ('ko', 'Korean'),
  ('ko-Latn', 'Romanised Korean'),
  ('es', 'Spanish'),
  ('fr', 'French'),
  ('de', 'German'),
  ('it', 'Italian'),
  ('pt', 'Portuguese'),
  ('ru', 'Russian'),
  ('ar', 'Arabic'),
  ('th', 'Thai'),
  ('vi', 'Vietnamese'),
  ('id', 'Indonesian'),
  ('other', 'Other'),
];
final Set<String> kTitleLanguageCodes = {for (final l in kTitleLanguages) l.$1};

String titleLanguageLabel(String code) =>
    kTitleLanguages.firstWhere((l) => l.$1 == code, orElse: () => (code, code.isEmpty ? 'Unknown' : code)).$2;

/// `mf565ScriptLang`: Japanese kana, Korean hangul, then CJK ideographs.
String scriptLang(Object? text) {
  final s = jsStr(text);
  if (RegExp('[぀-ヿ]').hasMatch(s)) return 'ja';
  if (RegExp('[가-힯]').hasMatch(s)) return 'ko';
  if (RegExp('[一-鿿]').hasMatch(s)) return 'zh';
  return '';
}

typedef TitleName = ({String lang, String text, String source});

/// `mf565Names`: every name a title has, tagged with its language when known.
List<TitleName> titleNames(Map<String, dynamic>? item) {
  final out = <TitleName>[];
  final seen = <String>{};
  void add(String lang, Object? text, String source) {
    final t = cleanTitle(text);
    if (t.isEmpty) return;
    final key = '$lang\u0001${t.toLowerCase()}';
    if (!seen.add(key)) return;
    out.add((lang: lang, text: t, source: source));
  }

  for (final raw in asList(item?['mf565Names'])) {
    final n = asMap(raw);
    if (n == null) continue;
    final lang = jsStr(n['lang']);
    add(kTitleLanguageCodes.contains(lang) ? lang : 'other', n['text'], jsStr(n['source']));
  }
  if (jsTruthy(item?['titleEnglish'])) add('en', item!['titleEnglish'], 'metadata');
  if (jsTruthy(item?['titleRomaji'])) add('ja-Latn', item!['titleRomaji'], 'metadata');
  final fields = asMap(asMap(item?['universalMetadata'])?['fields']);
  final ot = fields?['originalTitle'];
  final original = asMap(ot) != null ? asMap(ot)!['value'] : (ot ?? item?['originalTitle']);
  if (original is String && original.isNotEmpty) {
    final l = scriptLang(original);
    add(l.isEmpty ? 'other' : l, original, 'metadata');
  }
  final alt = fields?['alternateTitles'];
  final altList = asMap(alt) != null ? asList(asMap(alt)!['value']) : asList(alt);
  for (final a in altList) {
    if (a is String) add(scriptLang(a), a, 'metadata');
  }
  return out;
}

/// `mf565NamePrefs`.
({String global, Map<String, String> categories}) namePrefs(Map<String, dynamic>? settings) {
  final raw = asMap(settings?['mf565TitleNames']);
  final g = jsStr(raw?['global']);
  final cats = <String, String>{};
  asMap(raw?['categories'])?.forEach((k, v) {
    if (kTitleLanguageCodes.contains(jsStr(v))) cats[k] = jsStr(v);
  });
  return (global: kTitleLanguageCodes.contains(g) ? g : 'main', categories: cats);
}

/// `mf565NameLang`.
String nameLang(Map<String, dynamic>? item, ({String global, Map<String, String> categories}) prefs) {
  if (jsTruthy(item?['mf565NameExempt'])) return 'main';
  final own = jsStr(item?['mf565NameLanguage']);
  if (kTitleLanguageCodes.contains(own)) return own;
  return prefs.categories[jsStr(item?['categoryId'])] ?? prefs.global;
}

/// `mf565DisplayTitle`: the name shown for a title. Falls back to the main title.
String displayTitle(Map<String, dynamic>? item, ({String global, Map<String, String> categories}) prefs) {
  final main = cleanTitle(item?['title']);
  final lang = nameLang(item, prefs);
  if (lang == 'main') return main;
  for (final n in titleNames(item)) {
    if (n.lang == lang) return n.text;
  }
  return main;
}

/// Whether any title shows something other than its main name (the common case
/// is "no": then nothing needs replacing anywhere).
bool namesInUse(Map<String, dynamic>? settings, Iterable<Map<String, dynamic>> library) {
  final p = namePrefs(settings);
  if (p.global != 'main' || p.categories.isNotEmpty) return true;
  return library.any((i) => jsStr(i['mf565NameLanguage']).isNotEmpty);
}

/// `mf565NameMatches`: does a search query match any name of this title?
bool nameMatches(Map<String, dynamic>? item, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  if (cleanTitle(item?['title']).toLowerCase().contains(q)) return true;
  return titleNames(item).any((n) => n.text.toLowerCase().contains(q));
}

/// `mf565SearchText`.
String nameSearchText(Map<String, dynamic>? item) =>
    [cleanTitle(item?['title']), ...titleNames(item).map((n) => n.text)].join('\n').toLowerCase();

/// `mf565AddNames`: adds names this title doesn't have yet (never removes or
/// edits one). Returns how many were added.
int addTitleNames(Map<String, dynamic> item, List<TitleName> names) {
  if (names.isEmpty) return 0;
  final have = {for (final n in titleNames(item)) '${n.lang}\u0001${n.text.toLowerCase()}'};
  final list = [for (final x in asList(item['mf565Names'])) x];
  final main = cleanTitle(item['title']).toLowerCase();
  var added = 0;
  for (final n in names) {
    final key = '${n.lang}\u0001${n.text.toLowerCase()}';
    if (have.contains(key) || main == n.text.toLowerCase()) continue;
    have.add(key);
    list.add(<String, dynamic>{'lang': n.lang, 'text': n.text, 'source': n.source});
    added++;
  }
  if (added > 0) item['mf565Names'] = list.length > 60 ? list.sublist(0, 60) : list;
  return added;
}

/// The title editor's "Unit & names" values (website `mf565ReadEditor`).
class TitleExtras {
  TitleExtras({this.unit = '', this.seconds = 0, this.names = const [], this.lang = '', this.exempt = false});

  static TitleExtras of(Map<String, dynamic>? item) => TitleExtras(
        unit: jsStr(item?['mf565Unit']).trim(),
        seconds: jsNum(item?['mf565SecondsPerUnit']).floor(),
        names: [
          for (final raw in asList(item?['mf565Names']))
            if (asMap(raw) != null) (lang: jsStr(asMap(raw)!['lang']), text: jsStr(asMap(raw)!['text']), source: jsStr(asMap(raw)!['source'])),
        ],
        lang: jsStr(item?['mf565NameLanguage']),
        exempt: jsTruthy(item?['mf565NameExempt']),
      );

  final String unit, lang;
  final int seconds;
  final List<TitleName> names;
  final bool exempt;

  /// `mf565WriteEditor`: writes these values to [item]; returns whether anything changed.
  bool writeTo(Map<String, dynamic> item, List<dynamic> namesBefore, int now) {
    var changed = false;
    void set(String k, Object v, Object empty) {
      final cur = item[k] ?? empty;
      if (jsonEncode(cur) == jsonEncode(v)) return;
      if (jsonEncode(v) == jsonEncode(empty)) {
        item.remove(k);
      } else {
        item[k] = v;
      }
      changed = true;
    }

    final u = unit.trim().length > 40 ? unit.trim().substring(0, 40) : unit.trim();
    set('mf565Unit', u, '');
    set('mf565SecondsPerUnit', u.isNotEmpty && seconds > 0 ? seconds : 0, 0);
    // Keep where each name came from when it is unchanged.
    final old = [for (final x in namesBefore) if (asMap(x) != null) asMap(x)!];
    final next = <Map<String, dynamic>>[];
    for (final n in names) {
      final text = cleanTitle(n.text);
      final t = text.length > 220 ? text.substring(0, 220) : text;
      if (t.isEmpty || !kTitleLanguageCodes.contains(n.lang)) continue;
      final o = old.where((x) => jsStr(x['lang']) == n.lang && jsStr(x['text']) == t).firstOrNull;
      next.add({'lang': n.lang, 'text': t, 'source': jsStr(o?['source']).isEmpty ? 'manual' : jsStr(o!['source'])});
    }
    String pairs(List<Map<String, dynamic>> l) => jsonEncode([for (final x in l) [x['lang'], x['text']]]);
    if (pairs(old) != pairs(next)) {
      if (next.isNotEmpty) {
        item['mf565Names'] = next;
      } else {
        item.remove('mf565Names');
      }
      changed = true;
    }
    set('mf565NameLanguage', kTitleLanguageCodes.contains(lang) ? lang : '', '');
    set('mf565NameExempt', exempt, false);
    if (changed) item['modifiedAt'] = now > jsNum(item['modifiedAt']) ? now : jsOut(jsNum(item['modifiedAt']));
    return changed;
  }
}
