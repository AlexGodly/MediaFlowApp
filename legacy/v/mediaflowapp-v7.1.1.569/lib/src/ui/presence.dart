// What MediaFlow is doing right now, for Discord Rich Presence.
//
// Every screen reports its activity here (CLAUDE.md: a new or changed screen
// must set its Discord status in the same release; test/presence_test.dart
// checks every screen does):
//  - each section of the app has a status ([sectionPresence], and screens can
//    refine theirs with [PresenceHub.section] — e.g. Log with the title);
//  - screens opened on top (Title Details, the title editor, sheets) wrap
//    their content in [PresenceScope]; the newest one on screen wins.

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../logic/consuming.dart';
import '../logic/log_draft.dart' show LogDraftEditor;
import '../logic/presence_templates.dart';
import '../logic/resume.dart' show readLogging;
import '../logic/title_units.dart' show titleUnit;
import '../platform/discord_presence.dart';
import '../state/models.dart';
import '../util/js.dart';
import 'home_shell.dart' show Section;

export '../platform/discord_presence.dart' show PresenceInfo, PresenceKind;

/// The default status of each section.
PresenceInfo sectionPresence(Section s, [AccountView? view]) => PresenceInfo(
      situation: switch (s) {
        Section.log => 'picking',
        Section.library => 'library',
        Section.history => 'history',
        Section.extras => 'extras',
        Section.collections => 'collections',
        Section.order => 'order',
        Section.oldSystem => 'oldSystem',
        Section.recovery => 'recovery',
        Section.rate => 'rating',
        Section.covers => 'missingCovers',
        Section.stats => 'stats',
        Section.settings => 'settings',
        Section.account => 'account',
      },
    );

String fmtCount(int n) {
  final s = '$n';
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

/// Discord's verb for a category ("Watching", "Listening", "Playing").
PresenceKind presenceKind(Category cat) {
  final t = '${cat.raw['type'] ?? ''} ${cat.name} ${cat.unit}'.toLowerCase();
  if (RegExp(r'listen|music|album|song|podcast|audio').hasMatch(t)) return PresenceKind.listening;
  if (RegExp(r'read|book|manga|comic|novel|chapter|page|volume').hasMatch(t)) return PresenceKind.reading;
  if (RegExp(r'play|game|level|hour').hasMatch(t) && !RegExp(r'episode|movie|film|anime|show|series').hasMatch(t)) {
    return PresenceKind.playing;
  }
  if (RegExp(r'video|watch|episode|movie|film|anime|show|series|tv').hasMatch(t)) return PresenceKind.watching;
  return PresenceKind.other;
}

/// The verb in the status line for a category.
String presenceVerb(Category cat, {String fallback = 'Logging'}) => switch (presenceKind(cat)) {
      PresenceKind.watching => 'Watching',
      PresenceKind.reading => 'Reading',
      PresenceKind.listening => 'Listening to',
      PresenceKind.playing => 'Playing',
      PresenceKind.other => fallback,
    };

/// Where [item] stands in an open log: {after} this log ([progress]),
/// {before} it, and the season being logged.
({double progress, double before, String? season}) draftProgress(
    LogDraftEditor ed, Map<String, dynamic> item, Map<String, dynamic> entry) {
  // A missing start (null, as JS Number(null) would make it 0) means the
  // title's saved progress.
  final start = entry['v179StartProgress'];
  final before = start == null || (start is String && start.trim().isEmpty)
      ? LogDraftEditor.startProgress(item)
      : jsNum(start);
  final double progress;
  if (ed.itemized) {
    progress = ed.projectedProgress(item, entry);
  } else if (entry['v179EndProgress'] != null) {
    progress = jsNum(entry['v179EndProgress']);
  } else {
    progress = before + jsNum(entry['qty']);
  }
  final season = jsStr(ed.selectedSeason(entry, item)?['name']);
  return (progress: progress, before: before, season: season.isEmpty ? null : season);
}

/// The draft entry for [titleId] in an open log (the last edited one when
/// the title is in it more than once), or null.
Map<String, dynamic>? draftEntryFor(LogDraftEditor ed, String titleId) {
  Map<String, dynamic>? best;
  var bestAt = -1.0;
  for (final e in ed.entries) {
    if (jsStr(e['libraryId']) != titleId) continue;
    final at = jsNum(e['v369UpdatedAt']);
    if (best == null || at >= bestAt) {
      best = e;
      bestAt = at;
    }
  }
  return best;
}

/// A status about one title: its name, progress (from the log draft while
/// logging) and cover.
PresenceInfo titlePresence(String situation, Map<String, dynamic> item, Category cat,
    {double? progress, double? before, String? season, String more = '', int count = 0, String action = ''}) {
  // 7.0.0: the name MediaFlow shows for the title (or Discord's own choice).
  final title = discordTitleName(item,
      settings: DiscordPresence.instance.accountSettings, config: DiscordPresence.instance.config.raw, consuming: situation == 'pinned');
  final cover = jsStr(item['coverUrl']).trim();
  // While logging, {progress} follows Settings → Discord: after the draft
  // (default) or before it; {before} and {after} are both always there.
  final after = progress;
  final useBefore = before != null && DiscordPresence.instance.config.progressMode == 'before';
  final p = (useBefore ? before : progress) ?? jsNumOrNull(item['progress']);
  final total = jsNumOrNull(item['total']);
  final hasProgress = p != null && (p > 0 || (total ?? 0) > 0);
  String num(double v) => v == v.truncateToDouble() ? fmtCount(v.toInt()) : v.toStringAsFixed(1);
  // 7.1.1: the title's own unit (website v565), else its category's.
  final unitKey = titleUnit(item, cat.raw);
  final unit = unitLabel(unitKey, 1);
  return PresenceInfo(
    situation: situation,
    values: {
      'title': title,
      'category': cat.name,
      'verb': presenceVerb(cat, fallback: 'Logging'),
      'action': action.isEmpty ? presenceVerb(cat, fallback: 'Logging') : action,
      if (hasProgress) 'progress': num(p),
      if (before != null) 'before': num(before),
      if (after != null) 'after': num(after),
      if (hasProgress && total != null && total > 0) 'total': num(total),
      if (hasProgress && total != null && total > 0) 'percent': '${(p / total * 100).clamp(0, 100).round()}%',
      if (hasProgress) 'unit': capFirst(unit),
      'units': unitLabel(unitKey, 2),
      if ((season ?? '').isNotEmpty) 'season': season!,
      if (more.isNotEmpty) 'more': more,
      if (count > 0) 'count': '$count',
    },
    cover: cover.startsWith('https://') ? cover : null,
    categoryName: cat.name,
    categoryId: cat.id,
    kind: presenceKind(cat),
  );
}

class PresenceHub {
  PresenceHub._();
  static final PresenceHub instance = PresenceHub._();

  Section? _section;
  AccountView? _view;
  final Map<Section, PresenceInfo> _sections = {};
  final List<(Object, PresenceInfo)> _overlays = [];

  /// The section on screen (from the app's navigation).
  void setSection(Section s, AccountView? view) {
    _section = s;
    if (!identical(view, _view)) {
      _view = view;
      _globals = null;
      DiscordPresence.instance.globals ??= () => _globals ??= _computeGlobals();
      DiscordPresence.instance.setConfig(PresenceConfig.of(asMap(view?.state['settings'])));
      DiscordPresence.instance.setAccountSettings(asMap(view?.state['settings']));
      DiscordPresence.instance.consumingTitle ??= (config, now) {
        final log = _openLog();
        return consumingTitleId(config, log?.task, log?.logDraft, now);
      };
      DiscordPresence.instance.pinnedInfo ??= (id) {
        final v = _view;
        final t = v?.library.where((x) => x.id == id).firstOrNull;
        if (v == null || t == null) return null;
        // 7.1.1: while the title is in the open log, its progress comes from
        // the draft ({progress} after or before it, as set in Settings), like
        // the Log page's own status — not only what was saved.
        final log = _openLog();
        if (log != null) {
          final ed = LogDraftEditor(state: log.state, task: log.task, logDraft: log.logDraft, entryDraft: <String, dynamic>{});
          final entry = draftEntryFor(ed, id);
          final item = ed.item(id) ?? t.raw;
          if (entry != null) {
            final d = draftProgress(ed, item, entry);
            return titlePresence('pinned', item, v.category(t.categoryId), progress: d.progress, before: d.before, season: d.season);
          }
        }
        return titlePresence('pinned', t.raw, v.category(t.categoryId));
      };
    }
    _update();
  }

  /// The open log as the Log page has it right now (set while its form is
  /// open), so Discord follows the draft as you type.
  ({Map<String, dynamic> state, Map<String, dynamic> task, Map<String, dynamic> logDraft})? Function()? liveLog;

  ({Map<String, dynamic> state, Map<String, dynamic> task, Map<String, dynamic> logDraft})? _openLog() {
    final live = liveLog?.call();
    if (live != null) return live;
    final v = _view;
    final logging = v == null ? null : readLogging(v.state);
    if (logging == null || logging['active'] != true) return null;
    final task = asMap(logging['currentTask']), draft = asMap(logging['logDraft']);
    if (task == null || draft == null) return null;
    return (state: v!.state, task: task, logDraft: draft);
  }

  /// Level, XP and streak worked out in the background with each sync
  /// (AccountController.presenceStats), set by the home screen.
  Map<String, num>? Function()? statsSource;

  Map<String, String>? _globals;
  Map<String, String> _computeGlobals() {
    final v = _view;
    if (v == null) return const {};
    // 7.0.0: never work out Statistics on the screen's thread here. It ran
    // after every change to the account (slow frames every 20–30 s while
    // logging on big accounts); the numbers now come with each sync.
    final s = statsSource?.call();
    return {
      if (s != null) ...{
        'level': '${s['level']?.toInt() ?? 1}',
        'xp': fmtCount((s['xp'] ?? 0).round()),
        'streak': '${s['streak']?.toInt() ?? 0}',
      },
      'library': fmtCount(v.library.length),
    };
  }

  /// A section's own, more precise status (null: back to its default).
  void section(Section s, PresenceInfo? info) {
    final old = _sections[s];
    if (info == null) {
      _sections.remove(s);
    } else {
      _sections[s] = info;
    }
    if (old?.key != info?.key && s == _section) _update();
  }

  void push(Object owner, PresenceInfo info) {
    final i = _overlays.indexWhere((o) => identical(o.$1, owner));
    if (i >= 0) {
      if (_overlays[i].$2.key == info.key) return;
      _overlays[i] = (owner, info);
    } else {
      _overlays.add((owner, info));
    }
    _update();
  }

  void remove(Object owner) {
    final before = _overlays.length;
    _overlays.removeWhere((o) => identical(o.$1, owner));
    if (_overlays.length != before) _update();
  }

  PresenceInfo get current {
    if (_overlays.isNotEmpty) return _overlays.last.$2;
    final s = _section;
    if (s == null) return const PresenceInfo(situation: 'other');
    return _sections[s] ?? sectionPresence(s, _view);
  }

  void _update() => DiscordPresence.instance.show(current);
}

/// Sets the Discord status while [child] is on screen (screens opened on top
/// of the app: Title Details, the editor, sheets).
class PresenceScope extends StatefulWidget {
  const PresenceScope({super.key, required this.info, required this.child});
  final PresenceInfo info;
  final Widget child;

  @override
  State<PresenceScope> createState() => _PresenceScopeState();
}

class _PresenceScopeState extends State<PresenceScope> {
  // Pages kept alive in the background (a section you left) have tickers off;
  // their status only counts while they are on screen.
  bool _on = false;

  void _sync() {
    final on = TickerMode.of(context);
    if (on) {
      PresenceHub.instance.push(this, widget.info);
    } else if (_on) {
      PresenceHub.instance.remove(this);
    }
    _on = on;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(PresenceScope old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    PresenceHub.instance.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Notices when the person stops using the app (no touch, mouse or keys for
/// five minutes) so Discord shows "Idle in MediaFlow" (or clears it).
class PresenceIdleWatcher extends StatefulWidget {
  const PresenceIdleWatcher({super.key, required this.child});
  final Widget child;

  @override
  State<PresenceIdleWatcher> createState() => _PresenceIdleWatcherState();
}

class _PresenceIdleWatcherState extends State<PresenceIdleWatcher> {
  DateTime _last = DateTime.now();
  late final _timer = Stream.periodic(const Duration(seconds: 30)).listen((_) {
    DiscordPresence.instance.setIdle(DateTime.now().difference(_last) >= Duration(minutes: DiscordPresence.instance.config.idleMinutes));
  });

  bool _key(KeyEvent _) {
    _active();
    return false;
  }

  void _active() {
    _last = DateTime.now();
    DiscordPresence.instance.setIdle(false);
  }

  @override
  void initState() {
    super.initState();
    _timer;
    HardwareKeyboard.instance.addHandler(_key);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_key);
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _active(),
        onPointerSignal: (_) => _active(),
        onPointerHover: (_) => _active(),
        child: widget.child,
      );
}
