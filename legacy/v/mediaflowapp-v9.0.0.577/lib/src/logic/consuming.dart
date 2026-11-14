// "Consuming…" (7.0.0): which title MediaFlow shows on Discord as the one
// you're watching, reading or playing right now.
//
// Saved in the Discord settings (PresenceConfig.raw, account settings), so it
// is the same on every device:
//   consumingSource   where the title comes from:
//                       'edited'      the last title you edited in the log (default)
//                       'reroll'      the task's last reroll
//                       'recommended' the task's recommended title
//                       'assigned'    only a title you choose yourself
//   pinned            a title you chose (Pin / Choose / Settings). It always
//                     wins over the source while it lasts.
//   consumingCleared  {titleId, at}: Clear / Stop. That title isn't shown
//                     until the source gives another one or you choose one;
//                     Discord shows its normal status meanwhile.

import '../util/js.dart';
import 'custom_status.dart' show activePin;
import 'title_names.dart' show displayTitle, namePrefs, titleNames;

const List<(String, String)> kConsumingSources = [
  ('edited', 'The last title I edited in the log'),
  ('reroll', 'The last reroll'),
  ('recommended', 'The recommended title'),
  ('assigned', 'Only a title I choose'),
];

String consumingSource(Map<String, dynamic>? config) {
  final v = jsStr(config?['consumingSource']);
  return kConsumingSources.any((s) => s.$1 == v) ? v : 'edited';
}

/// The last-edited moment of a log entry (its own edits and its units').
int _editedAt(Map<String, dynamic> e) {
  var at = jsNum(e['v369UpdatedAt']).toInt();
  at = at > jsNum(e['loggedAt']).toInt() ? at : jsNum(e['loggedAt']).toInt();
  for (final u in asList(e['v369Units'])) {
    final m = asMap(u);
    if (m == null) continue;
    for (final k in const ['v369UpdatedAt', 'loggedAt']) {
      final t = jsNum(m[k]).toInt();
      if (t > at) at = t;
    }
  }
  return at;
}

/// The title the [source] points at now, or null.
String? sourceTitleId(String source, Map<String, dynamic>? task, Map<String, dynamic>? logDraft) {
  switch (source) {
    case 'edited':
      final entries = [for (final e in asList(logDraft?['entries'])) asMap(e)].whereType<Map<String, dynamic>>().toList();
      Map<String, dynamic>? best;
      var bestAt = -1;
      for (final e in entries) {
        if (jsStr(e['libraryId']).isEmpty) continue;
        final at = _editedAt(e);
        if (at >= bestAt) {
          best = e;
          bestAt = at;
        }
      }
      return best == null ? null : jsStr(best['libraryId']);
    case 'reroll':
      final history = asList(task?['v180RecommendationHistory']);
      if (history.length < 2) return null;
      final id = jsStr(asMap(history.last)?['libraryId']);
      return id.isEmpty ? null : id;
    case 'recommended':
      final history = asList(task?['v180RecommendationHistory']);
      final id = history.isNotEmpty ? jsStr(asMap(history.first)?['libraryId']) : jsStr(task?['libraryId']);
      return id.isEmpty ? null : id;
    default:
      return null;
  }
}

/// The title Consuming… shows now, or null (Discord then shows its normal
/// status). [task] and [logDraft] are the open log's (null when none).
String? consumingTitleId(Map<String, dynamic>? config, Map<String, dynamic>? task, Map<String, dynamic>? logDraft, int now) {
  final pin = activePin(config, now);
  if (pin != null) return pin.titleId;
  final source = consumingSource(config);
  if (source == 'assigned' || task == null) return null;
  final id = sourceTitleId(source, task, logDraft);
  if (id == null || id.isEmpty) return null;
  final cleared = asMap(config?['consumingCleared']);
  if (cleared != null && jsStr(cleared['titleId']) == id) return null;
  return id;
}

/// The Discord settings after Clear / Stop: no pinned title, and [shownId]
/// (what Consuming… showed) stays hidden until the source moves on.
Map<String, dynamic> clearedConsuming(Map<String, dynamic> config, String? shownId, int now) => {
      ...config,
      'pinned': null,
      'consumingCleared': {'titleId': shownId ?? '', 'at': now},
      'version': 1,
    };

/// The Discord settings after choosing [titleId] yourself: it's pinned, and
/// any earlier Clear no longer applies.
Map<String, dynamic> withoutClear(Map<String, dynamic> config) => {...config, 'consumingCleared': null, 'version': 1};

// ---- What Discord calls a title (7.0.0) ----
//
// Discord settings:
//   titleName      'mediaflow' (default): the name MediaFlow shows for the
//                  title (Settings → Title names, per category or per title);
//                  'main': always the main name.
//   consumingName  {titleId, lang, custom}: a name for Discord only, used while
//                  that title is the one being consumed.
//   titleNames     {titleId: {lang, custom}}: "Keep for this title", used every
//                  time that title is on Discord.
// None of this changes the title itself or what MediaFlow shows.

/// The name Discord shows for [item]. [consuming]: it's the Consuming… title.
String discordTitleName(Map<String, dynamic> item,
    {Map<String, dynamic>? settings, Map<String, dynamic>? config, bool consuming = false}) {
  final main = cleanTitle(item['title']);
  final id = jsStr(item['id']);
  final kept = id.isEmpty ? null : asMap(asMap(config?['titleNames'])?[id]);
  final now = asMap(config?['consumingName']);
  final choice = kept ?? (consuming && now != null && jsStr(now['titleId']) == id ? now : null);
  if (choice != null) {
    final custom = cleanTitle(choice['custom']);
    if (custom.isNotEmpty) return custom;
    final lang = jsStr(choice['lang']);
    if (lang == 'main') return main;
    if (lang.isNotEmpty) {
      for (final n in titleNames(item)) {
        if (n.lang == lang) return n.text;
      }
    }
  }
  if (jsStr(config?['titleName']) == 'main') return main;
  final shown = displayTitle(item, namePrefs(settings));
  return shown.isEmpty ? main : shown;
}

/// The Discord settings with a Discord-only name for [titleId]: [lang] (a
/// language code or 'main') or [custom] text. [keep]: for every time the title
/// is on Discord; otherwise only while it's being consumed. Both empty: back
/// to the usual name.
Map<String, dynamic> withDiscordName(Map<String, dynamic> config, String titleId,
    {String lang = '', String custom = '', bool keep = false}) {
  final kept = <String, dynamic>{...?asMap(config['titleNames'])};
  final clear = lang.isEmpty && custom.trim().isEmpty;
  final value = {'lang': lang, 'custom': custom.trim()};
  Object? consuming = config['consumingName'];
  if (keep) {
    if (clear) {
      kept.remove(titleId);
    } else {
      kept[titleId] = value;
    }
    if (jsStr(asMap(consuming)?['titleId']) == titleId) consuming = null;
  } else {
    kept.remove(titleId);
    consuming = clear ? null : {'titleId': titleId, ...value};
  }
  return {...config, 'titleNames': kept, 'consumingName': consuming, 'version': 1};
}

/// The Discord-only name chosen for [titleId], if any: (lang, custom, kept).
({String lang, String custom, bool keep})? discordNameChoice(Map<String, dynamic>? config, String titleId) {
  final kept = asMap(asMap(config?['titleNames'])?[titleId]);
  if (kept != null) return (lang: jsStr(kept['lang']), custom: jsStr(kept['custom']), keep: true);
  final now = asMap(config?['consumingName']);
  if (now != null && jsStr(now['titleId']) == titleId) return (lang: jsStr(now['lang']), custom: jsStr(now['custom']), keep: false);
  return null;
}
