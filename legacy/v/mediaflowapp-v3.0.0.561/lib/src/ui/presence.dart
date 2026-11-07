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

import '../platform/discord_presence.dart';
import '../state/models.dart';
import '../util/js.dart';
import 'home_shell.dart' show Section;

export '../platform/discord_presence.dart' show PresenceInfo, PresenceKind;

/// The default status of each section.
PresenceInfo sectionPresence(Section s, [AccountView? view]) => switch (s) {
      Section.log => const PresenceInfo(details: 'Picking something to log'),
      Section.library => PresenceInfo(
          details: 'Browsing the Library',
          state: view == null ? null : '${fmtCount(view.library.length)} title${view.library.length == 1 ? '' : 's'}',
        ),
      Section.history => const PresenceInfo(details: 'Looking through History'),
      Section.extras => const PresenceInfo(details: 'Looking back', state: 'On This Day and tools'),
      Section.collections => const PresenceInfo(details: 'Organising collections'),
      Section.order => const PresenceInfo(details: 'Planning the Personal Order'),
      Section.stats => const PresenceInfo(details: 'Checking stats'),
      Section.settings => const PresenceInfo(details: 'Tidying up settings'),
      Section.account => const PresenceInfo(details: 'Managing the account'),
    };

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

/// A status about one title (cover when there is one).
PresenceInfo titlePresence(String verb, Map<String, dynamic> item, Category cat, {String? state, String? genericVerb}) {
  final title = cleanTitle(item['title']);
  final cover = jsStr(item['coverUrl']).trim();
  return PresenceInfo(
    details: '$verb $title',
    genericDetails: '${genericVerb ?? verb} ${cat.name.toLowerCase()}',
    state: state,
    title: title,
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
    _view = view;
    _update();
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
    if (s == null) return const PresenceInfo(details: 'Using MediaFlow');
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
  @override
  void initState() {
    super.initState();
    PresenceHub.instance.push(this, widget.info);
  }

  @override
  void didUpdateWidget(PresenceScope old) {
    super.didUpdateWidget(old);
    PresenceHub.instance.push(this, widget.info);
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
  static const _after = Duration(minutes: 5);
  DateTime _last = DateTime.now();
  late final _timer = Stream.periodic(const Duration(seconds: 30)).listen((_) {
    DiscordPresence.instance.setIdle(DateTime.now().difference(_last) >= _after);
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
