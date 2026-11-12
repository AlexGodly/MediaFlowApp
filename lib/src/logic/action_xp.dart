// XP for everything you do (website v565, 413-v565-xp-everywhere.js).
//
// Every change you make that really changes your account earns XP for its kind
// (settings.leveling.mf565ActionXP[group]), times the day-streak multiplier.
// Changes that already earn their own XP (logging, Library edits, ratings,
// Collections, Personal Order, covers…) keep only their own reward. The same
// action on the same thing earns once per 5 minutes; different things always
// earn. Events go to the shared v348 ledger, so they sync, appear in XP History
// and count toward total XP and level — on the website and in the app alike.

import 'dart:math' as math;

import '../util/js.dart';
import 'leveling.dart';

/// `MF565_ACTION_GROUPS`: id, label, default XP.
const List<(String, String, double)> kActionXpGroups = [
  ('library', 'Library tools', 3),
  ('history', 'History edits', 3),
  ('categories', 'Categories', 3),
  ('collections', 'Collections & Personal Order tools', 3),
  ('data', 'Imports, exports & backups', 5),
  ('appearance', 'Themes & appearance', 2),
  ('settings', 'Settings', 2),
  ('other', 'Everything else', 2),
];

/// `MF565_BG_DEFAULTS`: background work XP.
const Map<String, double> kBackgroundXpDefaults = {'mf565BackupXP': 5, 'mf565RecoveryXP': 10, 'mf565FreshCheckXP': 2};

const Duration kActionRepeat = Duration(minutes: 5);

String actionGroupLabel(String group) => kActionXpGroups.firstWhere((g) => g.$1 == group, orElse: () => kActionXpGroups.last).$2;

/// `mf565ActionRate`.
double actionRate(Map<String, dynamic> state, String group) {
  final map = asMap(asMap(asMap(state['settings'])?['leveling'])?['mf565ActionXP']);
  final def = kActionXpGroups.firstWhere((g) => g.$1 == group, orElse: () => kActionXpGroups.last).$3;
  final raw = jsNumOrNull(map?[group]) ?? def;
  return raw.isFinite ? raw.clamp(0, 100000).toDouble() : def;
}

final _appearance = RegExp(r'theme|appearance|colou?r|icon|navigation|nav|dock|layout|view|density|font', caseSensitive: false);

/// The kind of a setting change, by its path (the website groups by action name).
String settingGroup(List<String> path) {
  final p = path.join('.');
  if (RegExp(r'categor', caseSensitive: false).hasMatch(p)) return 'categories';
  if (RegExp(r'backup|import|export|sync', caseSensitive: false).hasMatch(p)) return 'data';
  if (_appearance.hasMatch(p)) return 'appearance';
  return 'settings';
}

/// The kind of an edit, by what it changed. Null: no action XP (it changed
/// nothing countable, or it already earned its own XP).
({String group, String subject})? editGroup(List<List<String>> paths) {
  if (paths.isEmpty) return null;
  // Already rewarded by its own XP rule (Library edits, ratings, collections…).
  if (paths.any((p) => p.isNotEmpty && p.first == 'xpLedger')) return null;
  final roots = {for (final p in paths) if (p.isNotEmpty && p.first != 'activityLog' && p.first != 'savedAt') p.first};
  if (roots.isEmpty) return null;
  String subjectOf(String root) {
    final p = paths.firstWhere((p) => p.isNotEmpty && p.first == root, orElse: () => const []);
    return p.length > 1 ? p[1] : root;
  }

  for (final (root, group) in const [
    ('sessions', 'history'),
    ('library', 'library'),
    ('categories', 'categories'),
    ('collections', 'collections'),
    ('personalOrder', 'collections'),
    ('orderPlan', 'collections'),
  ]) {
    if (roots.contains(root)) return (group: group, subject: subjectOf(root));
  }
  if (roots.contains('settings')) {
    final p = paths.firstWhere((p) => p.isNotEmpty && p.first == 'settings');
    return (group: settingGroup(p.sublist(1)), subject: p.length > 1 ? p[1] : 'settings');
  }
  return (group: 'other', subject: roots.first);
}

/// One XP event in the v348 ledger (website `mf565LedgerEvent`). The key is
/// fixed, so replaying it (sync, another device) never counts it twice.
class ActionXpOp {
  ActionXpOp({required this.key, required this.kind, required this.base, required this.source, required this.at,
      this.details = '', this.subjectId = ''});

  final String key, kind, source, details, subjectId;
  final double base;
  final int at;

  Map<String, dynamic> toJson() =>
      {'key': key, 'xpKind': kind, 'base': base, 'source': source, 'details': details, 'subjectId': subjectId, 'at': at};

  static ActionXpOp fromJson(Map<String, dynamic> j) => ActionXpOp(
        key: jsStr(j['key']),
        kind: jsStr(j['xpKind']),
        base: jsNum(j['base']),
        source: jsStr(j['source']),
        details: jsStr(j['details']),
        subjectId: jsStr(j['subjectId']),
        at: jsNum(j['at']).toInt(),
      );

  /// Writes the event. Returns the XP written (0: nothing written).
  double write(Map<String, dynamic> state) {
    final l = Leveling(state);
    if (!l.enabled || key.isEmpty) return 0;
    var ledger = asMap(state['xpLedger']);
    if (ledger == null) {
      ledger = <String, dynamic>{};
      state['xpLedger'] = ledger;
    }
    Map<String, dynamic> part(String k) {
      var m = asMap(ledger![k]);
      if (m == null) {
        m = <String, dynamic>{};
        ledger[k] = m;
      }
      return m;
    }

    final events = part('v348ActionEvents');
    if (events[key] != null) return 0;
    final mult = awardMultiplier(l, asList(state['sessions']), at);
    final xp = math.max(0, jsRound(base * mult)).toDouble();
    if (xp == 0) return 0;
    events[key] = jsOut(xp);
    part('v348EventMeta')[key] = <String, dynamic>{
      'kind': kind,
      'baseXP': jsOut(jsRound(base * 100) / 100),
      'multiplier': jsOut(mult),
      'xp': jsOut(xp),
      'timestamp': at,
      'source': source,
      'details': details.length > 300 ? details.substring(0, 300) : details,
      'subjectId': subjectId.length > 120 ? subjectId.substring(0, 120) : subjectId,
    };
    return xp;
  }
}

/// The 5-minute repeat rule (website `MF565_XP.recent`), kept on this device.
class ActionRepeat {
  final Map<String, int> _recent = {};

  /// Whether [key] may earn now (and remembers it when it may).
  bool allow(String key, int now) {
    final last = _recent[key] ?? 0;
    if (now - last < kActionRepeat.inMilliseconds) return false;
    _recent[key] = now;
    if (_recent.length > 2000) _recent.removeWhere((_, t) => now - t > kActionRepeat.inMilliseconds);
    return true;
  }
}
