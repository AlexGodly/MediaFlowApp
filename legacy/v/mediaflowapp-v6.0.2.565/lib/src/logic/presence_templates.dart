// Fully customizable Discord Rich Presence. The look is saved in the account
// (`settings.mediaflowAppDiscord`, an app-only section the website keeps as
// it is), so every device shows the same status; turning it on or off and
// linking Discord stay per device.
//
// Each situation has two lines (details, state) written as templates with
// placeholders such as {title}, {progress}, {total}, {unit}; empty pieces and
// the separators around them disappear, so "{title} · {unit} {progress}" with
// no progress becomes just "Frieren".

import '../util/js.dart';

/// Situations the app can be in, with what they are called in Settings.
const kPresenceSituations = <(String, String)>[
  ('logging', 'Logging a title'),
  ('upNext', 'Recommendation waiting'),
  ('picking', 'Log page, nothing picked'),
  ('batch', 'Batch Log'),
  ('title', 'Title details'),
  ('editing', 'Editing a title'),
  ('library', 'Library'),
  ('history', 'History'),
  ('extras', 'Extras / On This Day'),
  ('collections', 'Collections'),
  ('collection', 'Inside a collection'),
  ('order', 'Personal Order'),
  ('stats', 'Statistics'),
  ('recovery', 'Recovery'),
  ('settings', 'Settings'),
  ('account', 'Account'),
  ('pinned', 'A title shown with "Show on Discord"'),
  ('rating', 'Rate Your Library'),
  ('missingCovers', 'Missing Covers'),
  ('oldSystem', 'Old System'),
  ('overview', 'Library Overview'),
  ('consumption', 'Consumption history'),
  ('recent', 'Recently viewed'),
  ('ratings', 'Ratings history'),
  ('other', 'Anything else'),
  ('idle', 'Idle'),
];

/// Every placeholder, with an example, for the editor's help list.
const kPresencePlaceholders = <(String, String)>[
  ('{title}', 'Title name · Frieren'),
  ('{verb}', 'Watching / Reading / Listening to / Playing'),
  ('{action}', 'What you\'re doing · Logging'),
  ('{progress}', 'Progress (while logging: after or before this log, see Settings) · 12'),
  ('{before}', 'Progress before this log · 12'),
  ('{after}', 'Progress after this log · 15'),
  ('{total}', 'Total · 28'),
  ('{unit}', 'Unit · Episode'),
  ('{units}', 'Unit, plural · episodes'),
  ('{percent}', 'Progress percent · 43%'),
  ('{season}', 'Season · Season 2'),
  ('{category}', 'Category · Anime'),
  ('{more}', 'Other titles in the log · +2 more'),
  ('{count}', 'Titles in the log or list · 3'),
  ('{collection}', 'Collection name'),
  ('{level}', 'Your level · 24'),
  ('{streak}', 'Day streak · 7'),
  ('{xp}', 'Total XP · 12,345'),
  ('{library}', 'Library size · 1,240'),
  ('{rerolls}', 'Rerolls of the current task · 3'),
];

/// Presets to start from.
final Map<String, Map<String, (String, String)>> kPresencePresets = {
  'detailed': {
    'logging': ('{action} {title}', '{unit} {progress} / {total} · {more}'),
    'upNext': ('Up next: {title}', '{category}'),
    'picking': ('Picking something to log', ''),
    'batch': ('Logging {count} titles', 'Batch Log'),
    'title': ('Looking at {title}', '{unit} {progress} / {total}'),
    'editing': ('Editing {title}', '{category}'),
    'library': ('Browsing the Library', '{library} titles'),
    'history': ('Looking through History', ''),
    'extras': ('Looking back', 'On This Day and tools'),
    'collections': ('Organising collections', ''),
    'collection': ('Browsing a collection', '{collection} · {count} titles'),
    'order': ('Planning the Personal Order', ''),
    'stats': ('Checking stats', 'Level {level} · {streak}-day streak'),
    'recovery': ('Recovering covers and details', ''),
    'settings': ('Tidying up settings', ''),
    'account': ('Managing the account', ''),
    'pinned': ('{title}', '{unit} {progress} / {total}'),
    'rating': ('Rating the Library', '{category}'),
    'missingCovers': ('Finding missing covers', ''),
    'oldSystem': ('Balancing the Old System', ''),
    'overview': ('Looking at the Library overview', '{library} titles'),
    'consumption': ('Looking through consumption history', ''),
    'recent': ('Browsing recently viewed', ''),
    'ratings': ('Looking at ratings', ''),
    'other': ('Using MediaFlow', ''),
    'idle': ('Idle in MediaFlow', ''),
  },
  'simple': {
    'logging': ('{title}', '{unit} {progress}'),
    'upNext': ('{title}', 'Up next'),
    'picking': ('Using MediaFlow', ''),
    'batch': ('{title}', '{more}'),
    'title': ('{title}', ''),
    'editing': ('{title}', ''),
    'library': ('Using MediaFlow', ''),
    'history': ('Using MediaFlow', ''),
    'extras': ('Using MediaFlow', ''),
    'collections': ('Using MediaFlow', ''),
    'collection': ('{collection}', ''),
    'order': ('Using MediaFlow', ''),
    'stats': ('Level {level}', ''),
    'recovery': ('Using MediaFlow', ''),
    'settings': ('Using MediaFlow', ''),
    'account': ('Using MediaFlow', ''),
    'pinned': ('{title}', '{unit} {progress}'),
    'rating': ('Using MediaFlow', ''),
    'missingCovers': ('Using MediaFlow', ''),
    'oldSystem': ('Using MediaFlow', ''),
    'overview': ('Using MediaFlow', ''),
    'consumption': ('Using MediaFlow', ''),
    'recent': ('Using MediaFlow', ''),
    'ratings': ('Using MediaFlow', ''),
    'other': ('Using MediaFlow', ''),
    'idle': ('Idle', ''),
  },
};

/// The saved look, with defaults filled in.
class PresenceConfig {
  PresenceConfig(this.raw);
  final Map<String, dynamic> raw;

  static const key = 'mediaflowAppDiscord';

  static PresenceConfig of(Map<String, dynamic>? settings) => PresenceConfig(asMap(settings?[key]) ?? const <String, dynamic>{});

  String _pick(String k, List<String> allowed, String def) {
    final v = jsStr(raw[k]);
    return allowed.contains(v) ? v : def;
  }

  String get preset => _pick('preset', const ['detailed', 'simple', 'custom'], 'detailed');

  /// full | activity (no titles or covers) | minimal ("Using MediaFlow").
  String get privacy => _pick('privacy', const ['full', 'activity', 'minimal'], 'full');

  /// What Discord's short status line shows: name ("Watching MediaFlow"),
  /// details ("Watching Frieren") or state.
  String get statusLine => _pick('statusLine', const ['name', 'details', 'state'], 'name');

  /// title (restarts with each title) | screen (each screen) | app | off.
  String get timer => _pick('timer', const ['title', 'screen', 'app', 'off'], 'title');

  /// cover | logo.
  String get picture => _pick('picture', const ['cover', 'logo'], 'cover');

  /// logo | none.
  String get smallPicture => _pick('smallPicture', const ['logo', 'none'], 'logo');

  /// last (the entry edited last) | first | all ("Frieren + 2 more").
  String get draftEntry => _pick('draftEntry', const ['last', 'first', 'all'], 'last');

  /// "Logging Frieren" or just "Frieren" for {action} while logging.
  bool get showAction => raw['showAction'] != false;

  /// While logging, {progress} is where the title will be after this log
  /// (the draft) or where it is now (before it).
  String get progressMode => _pick('progressMode', const ['after', 'before'], 'after');

  /// What the activity name says, i.e. the header of the profile card
  /// ("Watching MediaFlow" / "Watching Frieren"): mediaflow | status (the same
  /// line as the short status) | custom ([nameTemplate]). By default it
  /// follows the status line, so choosing "the title" changes both.
  String get activityName {
    final v = jsStr(raw['activityName']);
    if (const ['mediaflow', 'status', 'custom'].contains(v)) return v;
    return statusLine == 'name' ? 'mediaflow' : 'status';
  }

  String get nameTemplate => raw.containsKey('nameTemplate') ? jsStr(raw['nameTemplate']) : '{title}';

  /// show | clear.
  String get idle => _pick('idle', const ['show', 'clear'], 'show');

  /// v6: whether progress (episode, chapter, total, percent) is shown at all.
  bool get showProgress => raw['showProgress'] != false;

  /// v6: never switch to the Idle status (keep showing what was last shown).
  bool get neverIdle => raw['neverIdle'] == true;

  /// v6: the activity type: auto (MediaFlow decides from the category) or
  /// always playing / watching / listening / competing.
  String get activityType => _pick('activityType', const ['auto', 'playing', 'watching', 'listening', 'competing'], 'auto');

  /// v6: Discord online status set while MediaFlow runs (linked account):
  /// default (leave it) | online | idle | dnd | invisible.
  String get onlineStatus => _pick('onlineStatus', const ['default', 'online', 'idle', 'dnd', 'invisible'], 'default');

  int get idleMinutes {
    final n = jsNum(raw['idleMinutes']).toInt();
    return n >= 1 && n <= 120 ? n : 5;
  }

  String get largeText => raw.containsKey('largeText') ? jsStr(raw['largeText']) : '{title}';
  String get smallText => raw.containsKey('smallText') ? jsStr(raw['smallText']) : 'MediaFlow · {category}';

  List<String> get hiddenCategories => asList(raw['hiddenCategories']).map(jsStr).where((s) => s.isNotEmpty).toList();

  /// Category id → watching | reading | listening | playing (missing = automatic).
  Map<String, String> get types => {
        for (final e in (asMap(raw['types']) ?? const {}).entries)
          if (const ['watching', 'reading', 'listening', 'playing'].contains(e.value)) e.key: jsStr(e.value),
      };

  /// The two lines for a situation.
  (String, String) template(String situation) {
    final custom = asMap(asMap(raw['templates'])?[situation]);
    final base = kPresencePresets[preset == 'simple' ? 'simple' : 'detailed']![situation] ?? kPresencePresets['detailed']!['other']!;
    if (preset != 'custom' || custom == null) return base;
    return (
      custom.containsKey('details') ? jsStr(custom['details']) : base.$1,
      custom.containsKey('state') ? jsStr(custom['state']) : base.$2,
    );
  }

  /// A copy with [changes] applied (what Settings saves).
  Map<String, dynamic> withChanges(Map<String, dynamic> changes) => {...raw, ...changes, 'version': 1};

  /// A copy with one situation's lines changed (switches to the custom preset,
  /// keeping what the previous preset showed for the other situations).
  Map<String, dynamic> withTemplate(String situation, String details, String state) {
    final templates = <String, dynamic>{...?asMap(raw['templates'])};
    if (preset != 'custom') {
      for (final s in kPresenceSituations) {
        final t = template(s.$1);
        templates.putIfAbsent(s.$1, () => {'details': t.$1, 'state': t.$2});
      }
    }
    templates[situation] = {'details': details, 'state': state};
    return withChanges({'preset': 'custom', 'templates': templates});
  }
}

final _placeholder = RegExp(r'\{([a-zA-Z]+)\}');
final _chunkSep = RegExp(r'\s+[·•|]\s+|\s+[-–—]\s+');
final _edges = RegExp(r'^[\s·•|/,:\-–—]+|[\s·•|/,:\-–—]+$');

/// Fills a template. A piece whose placeholders are all empty disappears with
/// its separator: chunks are split at " · ", " | ", " - ", and inside a chunk
/// at " / " — so "{unit} {progress} / {total}" without a total gives
/// "Episode 12", and "{title} · {more}" without other titles gives "Frieren".
String renderPresence(String template, Map<String, String> values) {
  if (template.trim().isEmpty) return '';
  String value(String name) => (values[name] ?? values[name.toLowerCase()] ?? '').trim();
  bool allEmpty(String part) {
    final names = _placeholder.allMatches(part).map((m) => m[1]!).toList();
    return names.isNotEmpty && names.every((n) => value(n).isEmpty);
  }

  String fill(String part) => part.replaceAllMapped(_placeholder, (m) => value(m[1]!));

  final seps = _chunkSep.allMatches(template).map((m) => m[0]!).toList();
  final chunks = template.split(_chunkSep);
  final kept = <(int, String)>[];
  for (var i = 0; i < chunks.length; i++) {
    if (allEmpty(chunks[i])) continue;
    final parts = chunks[i].split(RegExp(r'\s*/\s*')).where((p) => !allEmpty(p)).map(fill);
    final text = parts.join(' / ').replaceAll(RegExp(r'\s{2,}'), ' ').replaceAll(_edges, '').trim();
    if (text.isNotEmpty) kept.add((i, text));
  }
  final out = StringBuffer();
  for (var k = 0; k < kept.length; k++) {
    if (k > 0) {
      final i = kept[k].$1;
      out.write(i - 1 < seps.length ? seps[i - 1] : ' · ');
    }
    out.write(kept[k].$2);
  }
  return out.toString();
}

/// Capitalises the first letter ("episode" → "Episode").
String capFirst(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
