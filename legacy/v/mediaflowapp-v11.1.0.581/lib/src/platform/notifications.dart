// MediaFlow's notifications, each one switchable on this device (Settings →
// Notifications), with quiet hours and a test button:
//   streak       daily reminder when nothing is logged yet (time)
//   risk         "your streak ends at midnight" later in the evening (time)
//   recovery     a Cover / Metadata Recovery finished (or paused on iOS)
//   release      a new episode / chapter of a title you follow is out
//   level        level up
//   milestone    streak, Library and completion milestones
//   weekly       weekly summary (day + time)
//   sync         the account could not sync for a while
//   update       a new MediaFlow version is available
//   discord      the Discord link expired
// Android and iOS schedule the timed ones with the system; Windows shows them
// while MediaFlow runs (it can keep running in the tray). Settings are per
// device (AppPrefs), nothing is written to the account.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../config.dart';
import '../data/account_controller.dart';
import '../data/app_prefs.dart';
import '../data/recovery_runner.dart';
import '../logic/progress_summary.dart' show computeDayStreak;
import '../logic/stats.dart';
import '../state/models.dart';
import '../util/js.dart';
import 'discord_presence.dart' show DiscordPresence;

/// One kind of notification and its default.
class NotifType {
  const NotifType(this.key, this.title, this.subtitle, this.channel, {this.on = true, this.time, this.weekly = false});
  final String key, title, subtitle, channel;
  final bool on;
  final String? time; // default "HH:mm" for timed ones
  final bool weekly;
}

const kNotifTypes = <NotifType>[
  NotifType('streak', 'Streak reminder', "A daily nudge when you haven't logged yet", 'Streak reminder', on: false, time: '20:00'),
  NotifType('risk', 'Streak at risk', 'Late in the evening when your streak would end at midnight', 'Streak at risk', time: '22:00'),
  NotifType('recovery', 'Recovery', 'When a Cover or Metadata Recovery finishes (progress shows while it runs)', 'Recovery'),
  NotifType('release', 'New episodes & chapters', 'When a title you follow gets a new episode or chapter', 'New episodes & chapters'),
  NotifType('level', 'Level up', 'When you reach a new level', 'Level & milestones'),
  NotifType('milestone', 'Milestones', 'Streak, Library and completion milestones', 'Level & milestones'),
  NotifType('weekly', 'Weekly summary', 'Your week in MediaFlow', 'Weekly summary', on: false, time: '18:00', weekly: true),
  NotifType('sync', 'Sync problems', "When your account couldn't sync for a while", 'Sync problems'),
  NotifType('update', 'New version', 'When a new MediaFlow version is out', 'Updates'),
  NotifType('discord', 'Discord link', 'When the Discord link expired and needs linking again', 'Discord'),
];

const _ids = {
  'streak': 1, 'risk': 2, 'weekly': 3, 'recovery': 10, 'level': 20, 'milestone': 21,
  'sync': 30, 'update': 40, 'discord': 50, 'test': 99,
};

class AppNotifications with WidgetsBindingObserver {
  AppNotifications._();
  static final AppNotifications instance = AppNotifications._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false, _observing = false;
  AccountController? _account;
  final Map<String, Timer> _desktop = {};
  final Map<String, String> _scheduled = {};
  AppLifecycleState _life = AppLifecycleState.resumed;
  Timer? _hourly, _syncTimer;

  AppPrefs get _prefs => AppPrefs.instance;

  bool get supported => Platform.isAndroid || Platform.isIOS || Platform.isWindows;

  // ---- settings (this device) ----

  NotifType _type(String key) => kNotifTypes.firstWhere((t) => t.key == key);

  bool isOn(String key) {
    // The old streak-reminder switch still counts (it was the only one).
    if (key == 'streak') return _prefs.get<bool>('notif.streak', _prefs.get<bool>('reminderOn', false));
    return _prefs.get<bool>('notif.$key', _type(key).on);
  }

  ({int h, int m}) timeOf(String key) {
    final def = _type(key).time ?? '20:00';
    final raw = key == 'streak' ? _prefs.get<String>('notif.streak.time', _prefs.get<String>('reminderTime', def)) : _prefs.get<String>('notif.$key.time', def);
    return _hm(raw, def);
  }

  /// 1 = Monday … 7 = Sunday.
  int get weeklyDay => _prefs.get<int>('notif.weekly.day', 7).clamp(1, 7).toInt();
  bool get quietOn => _prefs.get<bool>('notif.quiet', false);
  ({int h, int m}) get quietFrom => _hm(_prefs.get<String>('notif.quiet.from', '22:30'), '22:30');
  ({int h, int m}) get quietTo => _hm(_prefs.get<String>('notif.quiet.to', '08:00'), '08:00');

  static ({int h, int m}) _hm(String raw, String def) {
    var parts = raw.split(':');
    if (parts.length != 2) parts = def.split(':');
    final h = int.tryParse(parts[0]) ?? 20, m = int.tryParse(parts[1]) ?? 0;
    return (h: h.clamp(0, 23).toInt(), m: m.clamp(0, 59).toInt());
  }

  static String fmt(({int h, int m}) t) => '${t.h.toString().padLeft(2, '0')}:${t.m.toString().padLeft(2, '0')}';

  Future<void> setOn(String key, bool on) async {
    await _prefs.set('notif.$key', on);
    if (on) await requestPermission();
    _scheduled.clear();
    await refresh();
  }

  Future<void> setTime(String key, int h, int m) async {
    await _prefs.set('notif.$key.time', fmt((h: h, m: m)));
    _scheduled.clear();
    await refresh();
  }

  Future<void> setWeeklyDay(int day) async {
    await _prefs.set('notif.weekly.day', day);
    _scheduled.clear();
    await refresh();
  }

  Future<void> setQuiet({bool? on, ({int h, int m})? from, ({int h, int m})? to}) async {
    if (on != null) await _prefs.set('notif.quiet', on);
    if (from != null) await _prefs.set('notif.quiet.from', fmt(from));
    if (to != null) await _prefs.set('notif.quiet.to', fmt(to));
    _scheduled.clear();
    await refresh();
  }

  bool _inQuiet(DateTime t) {
    if (!quietOn) return false;
    final m = t.hour * 60 + t.minute, a = quietFrom.h * 60 + quietFrom.m, b = quietTo.h * 60 + quietTo.m;
    if (a == b) return false;
    return a < b ? (m >= a && m < b) : (m >= a || m < b);
  }

  /// A scheduled time inside quiet hours moves to when they end.
  DateTime _outOfQuiet(DateTime t) {
    if (!_inQuiet(t)) return t;
    var end = DateTime(t.year, t.month, t.day, quietTo.h, quietTo.m);
    if (!end.isAfter(t)) end = end.add(const Duration(days: 1));
    return end;
  }

  // ---- plugin ----

  Future<void> init() async {
    if (_ready || !supported) return;
    try {
      tzdata.initializeTimeZones();
      await _plugin.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
        windows: WindowsInitializationSettings(
          appName: 'MediaFlow',
          appUserModelId: 'AlexGodly.MediaFlow',
          guid: '6f1c3c7e-9a52-4f0e-9a8b-2b5d3c1e7a40',
        ),
      ));
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  /// Asks for permission to show notifications (Android 13+, iOS).
  Future<bool> requestPermission() async {
    await init();
    try {
      if (Platform.isAndroid) {
        final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        return await android?.requestNotificationsPermission() ?? true;
      }
      if (Platform.isIOS) {
        final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
        return await ios?.requestPermissions(alert: true, sound: true, badge: false) ?? false;
      }
    } catch (_) {}
    return true;
  }

  NotificationDetails _details(String key) {
    final t = key == 'test' ? null : _type(key);
    final channel = key == 'test' ? 'test' : t!.channel.toLowerCase().replaceAll(RegExp(r'[^a-z]+'), '_');
    return NotificationDetails(
      android: AndroidNotificationDetails(key == 'streak' ? 'streak' : channel, key == 'test' ? 'Test' : t!.channel,
          channelDescription: key == 'test' ? 'Test notifications' : t!.subtitle, importance: Importance.defaultImportance),
      iOS: const DarwinNotificationDetails(),
      windows: const WindowsNotificationDetails(),
    );
  }

  /// Shows [key] now (unless it is off or quiet hours are on).
  Future<void> show(String key, String title, String body, {int? id, bool force = false}) async {
    if (!supported) return;
    if (!force && (!isOn(key) || _inQuiet(DateTime.now()))) return;
    await init();
    if (!_ready) return;
    try {
      await _plugin.show(id ?? _ids[key] ?? 0, title, body, _details(key));
    } catch (_) {}
  }

  Future<void> test() async {
    await requestPermission();
    await show('test', 'MediaFlow', 'Notifications work on this device ✓', force: true);
  }

  Future<void> _schedule(String key, DateTime at, String title, String body, {DateTimeComponents? repeat}) async {
    final when = _outOfQuiet(at);
    final sig = '${isOn(key)}|${when.toIso8601String()}|$title|$body|$repeat';
    if (_scheduled[key] == sig) return;
    _scheduled[key] = sig;
    final id = _ids[key]!;
    _desktop.remove(key)?.cancel();
    try {
      await _plugin.cancel(id);
    } catch (_) {}
    if (!isOn(key)) return;
    if (Platform.isWindows) {
      // Shown while MediaFlow runs (it can stay in the tray).
      _desktop[key] = Timer(when.difference(DateTime.now()), () {
        _scheduled.remove(key);
        unawaited(_fire(key, title, body));
      });
      return;
    }
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(when.toUtc(), tz.UTC),
        _details(key),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: repeat,
      );
    } catch (_) {}
  }

  /// Windows timers re-check before showing (a log meanwhile cancels it).
  Future<void> _fire(String key, String title, String body) async {
    final sessions = asList(_account?.view?.state['sessions']);
    final today = computeDayStreak(sessions, DateTime.now().millisecondsSinceEpoch) > 0;
    if ((key == 'streak' || key == 'risk') && today) {
      unawaited(refresh());
      return;
    }
    await show(key, title, body);
    unawaited(refresh());
  }

  // ---- following the account ----

  void attach(AccountController account) {
    if (identical(_account, account)) return;
    _account?.removeListener(_onAccount);
    _account = account;
    _levelSeen = null;
    account.addListener(_onAccount);
    if (!_observing) {
      _observing = true;
      DiscordPresence.instance.onLinkExpired = discordExpired;
      if (!_prefs.get<bool>('notif.asked', false) && kNotifTypes.any((t) => isOn(t.key))) {
        unawaited(_prefs.set('notif.asked', true));
        unawaited(requestPermission());
      }
      WidgetsBinding.instance.addObserver(this);
      RecoveryRunner.instance.addListener(_onRunner);
      _hourly = Timer.periodic(const Duration(hours: 1), (_) => unawaited(_periodic()));
      unawaited(Future<void>.delayed(const Duration(seconds: 20), _periodic));
    }
    _onAccount();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _life = state;
    if (state == AppLifecycleState.paused && Platform.isIOS && RecoveryRunner.instance.anyRunning) {
      unawaited(show('recovery', 'Recovery paused', 'MediaFlow continues the recovery when you open it again.'));
    }
  }

  Timer? _debounce;
  void _onAccount() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () {
      unawaited(refresh());
      _checkProgress();
      _checkSync();
    });
  }

  /// Re-plans the timed notifications.
  Future<void> refresh() async {
    if (!supported) return;
    await init();
    if (!_ready) return;
    final view = _account?.view;
    if (view == null) return;
    final sessions = asList(view.state['sessions']);
    final now = DateTime.now();
    final loggedToday = computeDayStreak(sessions, now.millisecondsSinceEpoch) > 0;
    final streak = computeDayStreak(sessions, now.subtract(const Duration(days: 1)).millisecondsSinceEpoch);

    // Daily reminder.
    final s = timeOf('streak');
    var at = DateTime(now.year, now.month, now.day, s.h, s.m);
    if (loggedToday || !at.isAfter(now)) at = at.add(const Duration(days: 1));
    await _schedule(
        'streak',
        at,
        'MediaFlow',
        loggedToday
            ? 'Keep your ${streak + 1}-day streak going: log something today.'
            : streak > 0
                ? "You haven't logged today. Log something to keep your $streak-day streak."
                : "You haven't logged anything today.");

    // Streak at risk: only when there is a streak to lose.
    final r = timeOf('risk');
    var riskAt = DateTime(now.year, now.month, now.day, r.h, r.m);
    if (loggedToday || !riskAt.isAfter(now)) riskAt = riskAt.add(const Duration(days: 1));
    final atStake = loggedToday ? streak + 1 : streak;
    if (atStake > 0) {
      await _schedule('risk', riskAt, 'Your streak ends at midnight',
          'Log something before midnight to keep your $atStake-day streak 🔥');
    } else {
      await _cancel('risk');
    }

    // Weekly summary (its numbers are refreshed whenever the account changes).
    final w = timeOf('weekly');
    var weekAt = DateTime(now.year, now.month, now.day, w.h, w.m);
    while (weekAt.weekday != weeklyDay || !weekAt.isAfter(now)) {
      weekAt = weekAt.add(const Duration(days: 1));
    }
    String body;
    try {
      final m = StatsModel(view.state, now);
      final mins = m.week.minutes.round();
      body = '${mins >= 60 ? '${(mins / 60).toStringAsFixed(1)} h' : '$mins min'} this week · ${m.week.unitsText()} · '
          '${m.streak}-day streak · level ${m.level.level}';
    } catch (_) {
      body = 'See how your week went.';
    }
    await _schedule('weekly', weekAt, 'Your week in MediaFlow', body);
  }

  Future<void> _cancel(String key) async {
    if (_scheduled[key] == 'off') return;
    _scheduled[key] = 'off';
    _desktop.remove(key)?.cancel();
    try {
      await _plugin.cancel(_ids[key]!);
    } catch (_) {}
  }

  // ---- level and milestones ----

  int? _levelSeen;

  void _checkProgress() {
    final view = _account?.view;
    if (view == null || !_account!.hasData) return;
    StatsModel m;
    try {
      m = StatsModel(view.state, DateTime.now());
    } catch (_) {
      return;
    }
    final level = m.level.level;
    final stored = _prefs.get<int>('notif.seen.level', 0);
    if (_levelSeen == null) {
      // First look on this device: remember, don't announce the past.
      _levelSeen = level;
      if (stored == 0) unawaited(_prefs.set('notif.seen.level', level));
    }
    if (stored > 0 && level > stored) {
      unawaited(show('level', 'Level up! 🎉', 'You reached level $level in MediaFlow.'));
    }
    if (level != stored) unawaited(_prefs.set('notif.seen.level', level));

    final completed = view.library.where((t) => t.isCompleted).length;
    // The title always shows the real number; the milestone passed is the reason
    // (v565: a late notification said "50-day streak" on day 56).
    _milestone('streak', m.streak, const [7, 14, 30, 50, 100, 200, 365, 500, 1000],
        (n, v) => ('$v-day streak! 🔥', v == n ? 'You have logged $v days in a row.' : 'You passed $n days in a row.'));
    _milestone('library', view.library.length, const [50, 100, 250, 500, 1000, 2500, 5000],
        (n, v) => ('$v titles in your Library', v == n ? 'Your Library just reached $v titles.' : 'Your Library passed $n titles.'));
    _milestone('completed', completed, const [10, 25, 50, 100, 250, 500, 1000],
        (n, v) => ('$v titles completed', v == n ? "You've completed $v titles." : "You've passed $n completed titles."));
  }

  void _milestone(String key, int value, List<int> steps, (String, String) Function(int milestone, int value) text) {
    final reached = steps.where((s) => value >= s).fold<int>(0, (a, b) => b);
    final pref = 'notif.seen.$key';
    final stored = _prefs.get<int>(pref, -1);
    if (stored < 0) {
      unawaited(_prefs.set(pref, reached)); // first look: no announcement
      return;
    }
    if (reached > stored) {
      final (title, body) = text(reached, value);
      unawaited(show('milestone', title, body, id: 21 + steps.indexOf(reached)));
    }
    if (reached != stored) unawaited(_prefs.set(pref, reached));
  }

  // ---- sync ----

  void _checkSync() {
    final a = _account;
    if (a == null) return;
    if (a.status == SyncState.error) {
      _syncTimer ??= Timer(const Duration(minutes: 3), () {
        _syncTimer = null;
        if (a.status != SyncState.error) return;
        final last = _prefs.get<int>('notif.sync.last', 0);
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - last < 6 * 3600000) return;
        unawaited(_prefs.set('notif.sync.last', now));
        unawaited(show('sync', "MediaFlow couldn't sync", (a.message ?? '').isEmpty ? 'Open MediaFlow to retry.' : a.message!));
      });
    } else {
      _syncTimer?.cancel();
      _syncTimer = null;
    }
  }

  // ---- recovery finished ----

  final Set<RecoveryJob> _running = {};
  void _onRunner() {
    final r = RecoveryRunner.instance;
    for (final j in [r.cover, r.metadata].whereType<RecoveryJob>()) {
      if (j.running) {
        _running.add(j);
      } else if (_running.remove(j)) {
        if (_life == AppLifecycleState.resumed && !Platform.isWindows) continue; // it is on screen
        final name = j.kind == 'cover' ? 'Cover Recovery' : 'Metadata Recovery';
        final review = j.kind == 'cover' ? j.coverReviews.length : j.metadataReviews.length;
        unawaited(show('recovery', j.stopped ? '$name stopped' : '$name finished',
            '${j.done} / ${j.total} checked · ${j.applied} saved${review > 0 ? ' · $review to review' : ''}'));
      }
    }
  }

  // ---- discord ----

  void discordExpired() => unawaited(show('discord', 'Discord link expired', 'Open MediaFlow → Settings → Discord to link your account again.'));

  // ---- periodic: new version, new episodes / chapters ----

  bool _periodicBusy = false;
  Future<void> _periodic() async {
    if (_periodicBusy) return;
    _periodicBusy = true;
    try {
      await _checkUpdate();
      await _checkReleases();
    } catch (_) {
    } finally {
      _periodicBusy = false;
    }
  }

  Future<Object?> _json(Uri uri, {Map<String, dynamic>? post}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = post == null ? await client.getUrl(uri) : await client.postUrl(uri);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      req.headers.set(HttpHeaders.userAgentHeader, 'MediaFlowApp/$kAppVersionLabel');
      if (post != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(post));
      }
      final res = await req.close().timeout(const Duration(seconds: 12));
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      return jsonDecode(await res.transform(utf8.decoder).join());
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  Future<void> _checkUpdate() async {
    if (!isOn('update')) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _prefs.get<int>('notif.update.checked', 0) < 12 * 3600000) return;
    await _prefs.set('notif.update.checked', now);
    final j = asMap(await _json(Uri.parse('https://api.github.com/repos/AlexGodly/MediaFlowApp/releases/latest')));
    final tag = jsStr(j?['tag_name']);
    if (tag.isEmpty || !isNewerVersion(tag, kAppVersionLabel) || _prefs.get<String>('notif.update.tag', '') == tag) return;
    await _prefs.set('notif.update.tag', tag);
    await _prefs.set('updateUrl', jsStr(j?['html_url']));
    await show('update', 'MediaFlow update available', '${jsStr(j?['name']).isEmpty ? tag : jsStr(j?['name'])} is out. Open Settings to get it.');
  }

  /// Episodes from AniList's airing schedule (anime with an AniList or MAL
  /// ID), chapters from MangaDex (titles with a MangaDex ID). Read only.
  Future<void> _checkReleases() async {
    if (!isOn('release')) return;
    final view = _account?.view;
    if (view == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _prefs.get<int>('notif.release.checked', 0) < 6 * 3600000) return;
    await _prefs.set('notif.release.checked', now);
    final following = view.library.where((t) => !t.isCompleted && t.status != 'dropped').toList()
      ..sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    final seen = Map<String, dynamic>.of(_prefs.get<Map>('notif.release.seen', const {}).cast<String, dynamic>());

    // Anime: one AniList request for up to 50 titles.
    final byAnilist = <int, LibraryTitle>{}, byMal = <int, LibraryTitle>{};
    for (final t in following) {
      final ids = asMap(t.raw['externalIds']) ?? const {};
      final unit = view.category(t.categoryId).unit;
      if (unit != 'episodes') continue;
      final al = int.tryParse(jsStr(ids['anilist'])), mal = int.tryParse(jsStr(ids['mal']));
      if (al != null && byAnilist.length < 50) {
        byAnilist[al] = t;
      } else if (mal != null && byMal.length < 50) {
        byMal[mal] = t;
      }
    }
    Future<void> airing(String field, Map<int, LibraryTitle> map) async {
      if (map.isEmpty) return;
      final d = asMap(await _json(Uri.parse('https://graphql.anilist.co'), post: {
        'query': 'query(\$ids:[Int]){Page(perPage:50){media($field:\$ids,type:ANIME){id idMal status episodes nextAiringEpisode{episode airingAt}}}}',
        'variables': {'ids': map.keys.toList()},
      }));
      for (final m in asList(asMap(asMap(d?['data'])?['Page'])?['media']).map(asMap).whereType<Map<String, dynamic>>()) {
        final key = field == 'id_in' ? jsNum(m['id']).toInt() : jsNum(m['idMal']).toInt();
        final t = map[key];
        if (t == null) continue;
        final next = asMap(m['nextAiringEpisode']);
        final aired = next == null
            ? (m['status'] == 'FINISHED' ? jsNum(m['episodes']).toInt() : 0)
            : jsNum(next['episode']).toInt() - 1;
        final id = 'a${t.id}';
        final last = jsNum(seen[id]).toInt();
        if (aired > 0 && aired > t.progress && aired > last) {
          if (last > 0) {
            await show('release', 'New episode: ${t.title}', 'Episode $aired is out · you are at ${t.progress.round()}.', id: 2000 + (t.id.hashCode & 0xffff));
          }
          seen[id] = aired;
        }
      }
    }

    await airing('id_in', byAnilist);
    await airing('idMal_in', byMal);

    // Manga / comics with a MangaDex ID: the newest English chapter.
    var asked = 0;
    for (final t in following) {
      if (asked >= 15) break;
      final md = jsStr((asMap(t.raw['externalIds']) ?? const {})['mangadex']);
      if (!RegExp(r'^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$', caseSensitive: false).hasMatch(md)) continue;
      asked++;
      final d = asMap(await _json(Uri.parse(
          'https://api.mangadex.org/manga/$md/feed?translatedLanguage[]=en&order[chapter]=desc&limit=1&contentRating[]=safe&contentRating[]=suggestive&contentRating[]=erotica')));
      final ch = double.tryParse(jsStr(asMap(asMap(asList(d?['data']).firstOrNull)?['attributes'])?['chapter']));
      if (ch == null) continue;
      final id = 'm${t.id}';
      final last = jsNum(seen[id]).toDouble();
      if (ch > t.progress && ch > last) {
        if (last > 0) {
          await show('release', 'New chapter: ${t.title}', 'Chapter ${fmtChapter(ch)} is out · you are at ${t.progress.round()}.', id: 3000 + (t.id.hashCode & 0xffff));
        }
        seen[id] = ch;
      }
      await Future<void>.delayed(const Duration(milliseconds: 400)); // MangaDex asks for ≤ 5 requests a second
    }
    await _prefs.set('notif.release.seen', seen);
  }

  static String fmtChapter(double c) => c == c.truncateToDouble() ? '${c.toInt()}' : '$c';

  void dispose() {
    _hourly?.cancel();
  }
}
