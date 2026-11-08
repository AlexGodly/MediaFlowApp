// Discord Rich Presence through Discord's official Social SDK (no user tokens,
// nothing unofficial):
//  - Windows: the SDK talks to the Discord app on this PC; nothing to link.
//  - Android / iOS: the person links their Discord account once (Discord's
//    own sign-in, OAuth2 with PKCE as a public client); the SDK then sets the
//    status through their account. Tokens stay in the system's secure storage.
// What is shown comes from the screen being used (lib/src/ui/presence.dart),
// filtered by the privacy choice in Settings.

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/app_prefs.dart';
import '../logic/custom_status.dart';
import '../logic/presence_templates.dart';
import '../util/js.dart';
import 'discord_ffi.dart';

/// What MediaFlow is doing at a moment: a situation (see
/// `kPresenceSituations`) and the values its templates can use.
@immutable
class PresenceInfo {
  const PresenceInfo({
    required this.situation,
    this.values = const {},
    this.cover,
    this.categoryName,
    this.categoryId,
    this.kind = PresenceKind.other,
  });

  final String situation;

  /// title, progress, total, unit, units, percent, season, category, more,
  /// count, collection, rerolls, action, verb…
  final Map<String, String> values;

  /// The title's cover link (https), if any.
  final String? cover;
  final String? categoryName, categoryId;
  final PresenceKind kind;

  /// What restarts the "title" timer.
  String get subject => values['title'] ?? values['collection'] ?? '';

  String get key => '$situation|${values.entries.map((e) => '${e.key}=${e.value}').join(';')}|$cover|$categoryId|${kind.index}';
}

/// Decides Discord's verb (Watching / Listening / Playing).
enum PresenceKind { watching, reading, listening, playing, other }

class DiscordPresence extends ChangeNotifier {
  DiscordPresence._();
  static final DiscordPresence instance = DiscordPresence._();

  static const int applicationId = 1554979701787992225;
  static const String logoUrl = 'https://raw.githubusercontent.com/AlexGodly/MediaFlowApp/main/assets/branding/mediaflow-logo-rounded-512.png';

  static bool get mobile => Platform.isAndroid || Platform.isIOS;
  static bool get supported => Platform.isWindows || Platform.isAndroid || Platform.isIOS;

  DiscordFfi? _ffi;
  Pointer<DOpaque>? _client;
  Timer? _pump;
  NativeCallable<StatusCb>? _statusCb;
  final _secure = const FlutterSecureStorage();

  /// The saved link stopped working (Discord removed or expired it).
  void Function()? onLinkExpired;

  /// Connection state for Settings.
  String statusText = 'Off';
  bool linked = false, linking = false, connected = false;
  String lastError = '';

  PresenceInfo? _wanted;
  String _sentKey = '';
  int _startedAt = DateTime.now().millisecondsSinceEpoch;
  DateTime _lastSend = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _sendTimer;
  bool _idle = false;

  // ---- settings (this device) ----

  bool get enabled => AppPrefs.instance.get<bool>('discordEnabled', true);

  /// The look shared by every device (account settings, see
  /// presence_templates.dart), set by the app when the account changes.
  PresenceConfig config = PresenceConfig(const {});

  /// Values every template can use (level, streak, xp, library).
  Map<String, String> Function()? globals;

  void setConfig(PresenceConfig c) {
    if (c.raw == config.raw || jsonEncode(c.raw) == jsonEncode(config.raw)) return;
    config = c;
    _sentKey = '';
    _schedule();
    notifyListeners();
  }

  bool get available => supported && DiscordFfi.load() != null;

  Future<void> setEnabled(bool on) async {
    await AppPrefs.instance.set('discordEnabled', on);
    if (on) {
      await start();
    } else {
      _clear();
      _stopClient();
    }
    notifyListeners();
  }

  // ---- client ----

  /// Starts the SDK (when bundled and turned on). Safe to call more than once.
  Future<void> start() async {
    if (!supported || !enabled || _client != null) return;
    final ffi = DiscordFfi.load();
    if (ffi == null) {
      statusText = 'Not available in this build';
      notifyListeners();
      return;
    }
    _ffi = ffi;
    try {
      final client = DiscordFfi.obj();
      ffi.clientInit(client);
      ffi.clientSetAppId(client, applicationId);
      _client = client;
      _statusCb = NativeCallable<StatusCb>.isolateLocal(_onStatus);
      ffi.clientSetStatusChanged(client, _statusCb!.nativeFunction, nullptr, nullptr);
      _pump = Timer.periodic(const Duration(milliseconds: 200), (_) {
        try {
          ffi.runCallbacks();
        } catch (_) {}
      });
      _minute ??= Timer.periodic(const Duration(minutes: 1), (_) => _schedule());
      statusText = mobile ? 'Not linked' : 'Waiting for the Discord app';
      final refresh = await _readToken('refresh');
      linked = refresh != null && refresh.isNotEmpty;
      if (linked) {
        statusText = 'Connecting…';
        _refresh(refresh!);
      }
    } catch (e) {
      lastError = '$e';
      statusText = 'Could not start Discord';
    }
    notifyListeners();
    _sentKey = '';
    _schedule();
  }

  void _stopClient() {
    final ffi = _ffi, client = _client;
    _pump?.cancel();
    _pump = null;
    _minute?.cancel();
    _minute = null;
    if (ffi != null && client != null) {
      try {
        ffi.clientDisconnect(client);
        ffi.clientDrop(client);
      } catch (_) {}
      calloc.free(client);
    }
    _client = null;
    _statusCb?.close();
    _statusCb = null;
    connected = false;
    statusText = 'Off';
  }

  void _onStatus(int status, int error, int detail, Pointer<Void> _) {
    connected = status == ClientStatus.ready || status == ClientStatus.connected;
    statusText = switch (status) {
      ClientStatus.ready => 'Connected',
      ClientStatus.connected => 'Connected',
      ClientStatus.connecting || ClientStatus.reconnecting => 'Connecting…',
      _ => linked ? 'Disconnected' : (mobile ? 'Not linked' : 'Waiting for the Discord app'),
    };
    if (status == ClientStatus.ready) {
      _sentKey = '';
      _schedule();
    }
    notifyListeners();
  }

  // ---- account linking (Discord's OAuth2 with PKCE, public client) ----

  /// Opens Discord to approve MediaFlow, then connects.
  Future<void> link() async {
    final ffi = _ffi, client = _client;
    if (ffi == null || client == null || linking) return;
    linking = true;
    lastError = '';
    statusText = 'Waiting for Discord…';
    notifyListeners();
    final verifier = DiscordFfi.obj();
    final challenge = DiscordFfi.obj();
    final args = DiscordFfi.obj();
    late final NativeCallable<AuthorizeCb> cb;
    void cleanup() {
      try {
        ffi.challengeDrop(challenge);
        ffi.argsDrop(args);
      } catch (_) {}
      calloc.free(challenge);
      calloc.free(args);
    }

    try {
      ffi.createVerifier(client, verifier);
      ffi.verifierChallenge(verifier, challenge);
      ffi.argsInit(args);
      ffi.argsSetClientId(args, applicationId);
      final scopes = using((a) {
        final out = a<DString>();
        ffi.defaultPresenceScopes(out);
        return ffi.take(out);
      });
      using((a) => ffi.argsSetScopes(args, DiscordFfi.str(scopes, a).ref));
      ffi.argsSetChallenge(args, challenge);
      final verifierText = using((a) {
        final out = a<DString>();
        ffi.verifierVerifier(verifier, out);
        return ffi.take(out);
      });
      ffi.verifierDrop(verifier);
      calloc.free(verifier);
      cb = NativeCallable<AuthorizeCb>.isolateLocal((Pointer<DOpaque> result, DString code, DString redirect, Pointer<Void> _) {
        cb.close();
        final codeText = ffi.takeValue(code), redirectText = ffi.takeValue(redirect);
        final (ok, error) = ffi.takeResult(result);
        if (!ok) {
          _linkFailed(error.isEmpty ? 'Linking was cancelled.' : error);
          return;
        }
        _exchange(codeText, verifierText, redirectText);
      });
      ffi.clientAuthorize(client, args, cb.nativeFunction, nullptr, nullptr);
    } catch (e) {
      _linkFailed('$e');
    } finally {
      cleanup();
    }
  }

  void _linkFailed(String error) {
    linking = false;
    lastError = error;
    statusText = linked ? 'Disconnected' : 'Not linked';
    notifyListeners();
  }

  void _exchange(String code, String verifier, String redirect) {
    final ffi = _ffi!, client = _client!;
    late final NativeCallable<TokenCb> cb;
    cb = NativeCallable<TokenCb>.isolateLocal(_tokenHandler(() => cb.close()));
    using((a) => ffi.clientGetToken(client, applicationId, DiscordFfi.str(code, a).ref, DiscordFfi.str(verifier, a).ref,
        DiscordFfi.str(redirect, a).ref, cb.nativeFunction, nullptr, nullptr));
  }

  void _refresh(String refresh) {
    final ffi = _ffi!, client = _client!;
    late final NativeCallable<TokenCb> cb;
    cb = NativeCallable<TokenCb>.isolateLocal(_tokenHandler(() => cb.close(), refreshing: true));
    using((a) => ffi.clientRefreshToken(client, applicationId, DiscordFfi.str(refresh, a).ref, cb.nativeFunction, nullptr, nullptr));
  }

  void Function(Pointer<DOpaque>, DString, DString, int, int, DString, Pointer<Void>) _tokenHandler(void Function() close,
      {bool refreshing = false}) {
    return (Pointer<DOpaque> result, DString access, DString refresh, int type, int expiresIn, DString scopes, Pointer<Void> _) {
      close();
      final ffi = _ffi!;
      final accessText = ffi.takeValue(access), refreshText = ffi.takeValue(refresh);
      ffi.takeValue(scopes);
      final (ok, error) = ffi.takeResult(result);
      if (!ok || accessText.isEmpty) {
        if (refreshing) {
          // The link was removed on Discord's side (or expired): link again.
          unawaited(_deleteTokens());
          linked = false;
          onLinkExpired?.call();
        }
        _linkFailed(error.isEmpty ? 'Discord did not accept the link.' : error);
        return;
      }
      unawaited(_saveToken('refresh', refreshText));
      linked = true;
      _useToken(type, accessText);
    };
  }

  void _useToken(int type, String access) {
    final ffi = _ffi!, client = _client!;
    late final NativeCallable<ResultCb> cb;
    cb = NativeCallable<ResultCb>.isolateLocal((Pointer<DOpaque> result, Pointer<Void> _) {
      cb.close();
      final (ok, error) = ffi.takeResult(result);
      linking = false;
      if (!ok) {
        _linkFailed(error);
        return;
      }
      statusText = 'Connecting…';
      ffi.clientConnect(client);
      notifyListeners();
    });
    using((a) => ffi.clientUpdateToken(client, type, DiscordFfi.str(access, a).ref, cb.nativeFunction, nullptr, nullptr));
  }

  /// Removes the link from this device (the person can also remove MediaFlow
  /// under Discord → Settings → Authorized Apps).
  Future<void> unlink() async {
    _clear();
    await _deleteTokens();
    linked = false;
    _stopClient();
    await start();
  }

  Future<String?> _readToken(String k) async {
    try {
      return await _secure.read(key: 'discord.$k');
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveToken(String k, String v) async {
    try {
      await _secure.write(key: 'discord.$k', value: v);
    } catch (_) {}
  }

  Future<void> _deleteTokens() async {
    try {
      await _secure.delete(key: 'discord.refresh');
    } catch (_) {}
  }

  // ---- what is shown ----

  /// The app's current activity (from the screen in use).
  void show(PresenceInfo? info) {
    final before = _wanted;
    final timer = config.timer;
    final changed = timer == 'title'
        ? (info?.subject != before?.subject || (info?.subject ?? '').isEmpty && info?.situation != before?.situation)
        : timer == 'screen'
            ? info?.situation != before?.situation
            : false;
    if (changed) _startedAt = DateTime.now().millisecondsSinceEpoch;
    _wanted = info;
    _schedule();
  }

  void setIdle(bool idle) {
    if (idle == _idle) return;
    _idle = idle;
    if (!idle) _startedAt = DateTime.now().millisecondsSinceEpoch;
    _schedule();
  }

  /// Discord accepts about one update every few seconds: changes are
  /// coalesced and the latest one is sent.
  void _schedule() {
    if (_client == null) return;
    _sendTimer?.cancel();
    final wait = const Duration(seconds: 4) - DateTime.now().difference(_lastSend);
    _sendTimer = Timer(wait.isNegative ? const Duration(milliseconds: 300) : wait, _send);
  }

  /// The account's settings (Custom Status lives there) and how to turn a
  /// pinned Library title into a status; set by the app.
  Map<String, dynamic>? accountSettings;
  PresenceInfo? Function(String titleId)? pinnedInfo;
  Timer? _minute;

  void setAccountSettings(Map<String, dynamic>? settings) {
    final custom = jsonEncode(settings?[kCustomStatusKey]);
    final before = jsonEncode(accountSettings?[kCustomStatusKey]);
    accountSettings = settings;
    if (custom != before) {
      _sentKey = '';
      _schedule();
      notifyListeners();
    }
    // Schedules and "until" times are checked every minute while connected.
    if (_client != null) _minute ??= Timer.periodic(const Duration(minutes: 1), (_) => _schedule());
  }

  /// What Discord last accepted (for Settings' preview).
  DiscordActivity? accepted;

  /// What is actually shown: Custom Status when one applies, else a title
  /// pinned with "Show on Discord", else the situation's templates — after
  /// the privacy settings.
  DiscordActivity? effective() {
    final now = DateTime.now();
    final custom = currentCustomStatus(accountSettings, now);
    if (custom != null) return customActivity(custom.status, custom.appliedAt);
    final c = config;
    final statusLine = switch (c.statusLine) { 'details' => 2, 'state' => 1, _ => 0 };
    final g = globals?.call() ?? const <String, String>{};
    final pin = activePin(c.raw, now.millisecondsSinceEpoch);
    final pinned = pin == null ? null : pinnedInfo?.call(pin.titleId);
    if (_idle && pinned == null) {
      if (c.idle == 'clear') return null;
      final t = c.template('idle');
      final d = renderPresence(t.$1, g);
      final details = _clip(d.isEmpty ? 'Idle in MediaFlow' : d);
      final state = _opt(renderPresence(t.$2, g));
      return DiscordActivity(
        name: _activityName(c, statusLine, details, state, g),
        details: details,
        state: state,
        large: logoUrl,
        largeText: 'MediaFlow',
        type: ActivityType.playing,
        statusLine: statusLine,
      );
    }
    final w = pinned ?? _wanted ?? const PresenceInfo(situation: 'other');
    final hidden = w.categoryId != null && c.hiddenCategories.contains(w.categoryId);
    if (c.privacy == 'minimal' || hidden) {
      return DiscordActivity(
        name: 'MediaFlow',
        details: 'Using MediaFlow',
        large: logoUrl,
        largeText: 'MediaFlow',
        type: ActivityType.playing,
        statusLine: 0,
        start: c.timer != 'off' ? _startedAt : 0,
      );
    }
    final full = c.privacy == 'full';
    final values = <String, String>{...g, ...w.values};
    if (!full) {
      // Titles and collection names hidden: the category stands in.
      final cat = (w.categoryName ?? '').toLowerCase();
      for (final k in const ['title', 'collection']) {
        if ((values[k] ?? '').isNotEmpty) values[k] = cat.isEmpty ? 'a title' : cat;
      }
    }
    if (!c.showAction) values['action'] = '';
    final t = c.template(w.situation);
    final details = _clip(renderPresence(t.$1, values).isEmpty ? 'Using MediaFlow' : renderPresence(t.$1, values));
    final state = _opt(renderPresence(t.$2, values));
    final cover = full && c.picture == 'cover' && (w.cover ?? '').startsWith('https://') ? w.cover! : null;
    final pinType = pin == null ? '' : pin.type;
    final kind = switch (pinType.isNotEmpty ? pinType : c.types[w.categoryId ?? '']) {
      'watching' => PresenceKind.watching,
      'listening' => PresenceKind.listening,
      'playing' || 'reading' => PresenceKind.playing,
      _ => w.kind,
    };
    final type = switch (kind) {
      PresenceKind.watching => ActivityType.watching,
      PresenceKind.listening => ActivityType.listening,
      _ => ActivityType.playing,
    };
    final largeText = renderPresence(c.largeText, values);
    final smallText = renderPresence(c.smallText, values);
    return DiscordActivity(
      name: _activityName(c, statusLine, details, state, values),
      details: details,
      state: state,
      large: cover ?? logoUrl,
      largeText: _clip(largeText.isEmpty ? 'MediaFlow' : largeText),
      small: cover != null && c.smallPicture == 'logo' ? logoUrl : null,
      smallText: cover != null && c.smallPicture == 'logo' ? _clip(smallText.isEmpty ? 'MediaFlow' : smallText) : null,
      type: type,
      statusLine: statusLine,
      start: c.timer != 'off' ? _startedAt : 0,
    );
  }

  /// The activity name (profile card header): MediaFlow, the same text as
  /// the status line, or the custom template.
  static String _activityName(PresenceConfig c, int statusLine, String details, String? state, Map<String, String> values) {
    switch (c.activityName) {
      case 'status':
        final line = statusLine == 2 ? details : statusLine == 1 ? (state ?? details) : '';
        final title = (values['title'] ?? '').trim();
        return _clip(line.isNotEmpty ? line : (title.isNotEmpty ? title : 'MediaFlow'));
      case 'custom':
        final n = renderPresence(c.nameTemplate, values);
        return _clip(n.isEmpty ? 'MediaFlow' : n);
      default:
        return 'MediaFlow';
    }
  }

  /// A Custom Status as Discord would get it (also for the editor's preview).
  DiscordActivity customActivity(Map<String, dynamic> st, int appliedAt) {
    final g = globals?.call() ?? const <String, String>{};
    final values = <String, String>{...g, ...?_wanted?.values};
    String fill(Object? v) => renderPresence(jsStr(v), values);
    final times = statusTimes(st, appliedAt);
    final name = fill(st['name']);
    final details = fill(st['details']);
    return DiscordActivity(
      name: _clip(name.isEmpty ? 'MediaFlow' : name),
      details: details.isEmpty ? null : _clip(details),
      state: _opt(fill(st['state'])),
      large: jsStr(st['largeImage']),
      largeText: _opt(fill(st['largeText'])),
      small: jsStr(st['smallImage']).isEmpty ? null : jsStr(st['smallImage']),
      smallText: _opt(fill(st['smallText'])),
      type: switch (st['type']) {
        'listening' => ActivityType.listening,
        'watching' => ActivityType.watching,
        'competing' => ActivityType.competing,
        _ => ActivityType.playing,
      },
      statusLine: switch (st['display']) { 'details' => 2, 'state' => 1, _ => 0 },
      start: times.start,
      end: times.end,
      detailsUrl: jsStr(st['detailsUrl']),
      stateUrl: jsStr(st['stateUrl']),
      largeUrl: jsStr(st['largeUrl']),
      smallUrl: jsStr(st['smallUrl']),
      partyCurrent: jsNum(st['partyCurrent']).toInt(),
      partyMax: jsNum(st['partyMax']).toInt(),
      buttons: [for (final b in asList(st['buttons']).map(asMap).whereType<Map<String, dynamic>>()) (jsStr(b['label']), jsStr(b['url']))],
      custom: true,
    );
  }

  static String? _opt(String s) => s.trim().isEmpty ? null : _clip(s);

  static String _clip(String s) {
    final t = s.trim();
    if (t.length < 2) return '$t  '.substring(0, 2);
    return t.length > 128 ? '${t.substring(0, 127)}…' : t;
  }

  /// What the SDK version in this build can show (Custom Status hides the rest).
  bool get supportsParty => _ffi?.hasParty ?? DiscordFfi.load()?.hasParty ?? false;
  bool get supportsButtons => _ffi?.hasButtons ?? DiscordFfi.load()?.hasButtons ?? false;
  bool get supportsLinks => _ffi?.hasLinks ?? DiscordFfi.load()?.hasLinks ?? false;
  bool get supportsEnd => (_ffi ?? DiscordFfi.load())?.timestampsSetEnd != null;

  void _send() {
    final ffi = _ffi, client = _client;
    if (ffi == null || client == null || !enabled) return;
    final e = effective();
    final key = e?.key ?? 'clear';
    if (key == _sentKey) return;
    _lastSend = DateTime.now();
    _sentKey = key;
    if (e == null) {
      _clear();
      return;
    }
    final activity = DiscordFfi.obj(), assets = DiscordFfi.obj(), times = DiscordFfi.obj();
    final party = DiscordFfi.obj();
    final buttons = <Pointer<DOpaque>>[];
    var partyInit = false;
    try {
      using((a) {
        Pointer<DString> str(String v) => DiscordFfi.str(v, a);
        ffi.activityInit(activity);
        ffi.activitySetName(activity, str(e.name).ref);
        ffi.activitySetType(activity, e.type);
        // What the short status line shows ("Watching MediaFlow" / "Watching Frieren").
        final display = a<Int32>()..value = e.statusLine;
        ffi.activitySetStatusDisplayType(activity, display);
        if (e.details != null) ffi.activitySetDetails(activity, str(e.details!));
        if (e.state != null) ffi.activitySetState(activity, str(e.state!));
        if (e.detailsUrl.isNotEmpty) ffi.activitySetDetailsUrl?.call(activity, str(e.detailsUrl));
        if (e.stateUrl.isNotEmpty) ffi.activitySetStateUrl?.call(activity, str(e.stateUrl));
        ffi.assetsInit(assets);
        if (e.large.isNotEmpty) {
          ffi.assetsSetLargeImage(assets, str(e.large));
          if (e.largeText != null) ffi.assetsSetLargeText(assets, str(e.largeText!));
          if (e.largeUrl.isNotEmpty) ffi.assetsSetLargeUrl?.call(assets, str(e.largeUrl));
        }
        if (e.small != null) {
          ffi.assetsSetSmallImage(assets, str(e.small!));
          if (e.smallText != null) ffi.assetsSetSmallText(assets, str(e.smallText!));
          if (e.smallUrl.isNotEmpty) ffi.assetsSetSmallUrl?.call(assets, str(e.smallUrl));
        }
        ffi.activitySetAssets(activity, assets);
        ffi.timestampsInit(times);
        if (e.start > 0 || e.end > 0) {
          if (e.start > 0) ffi.timestampsSetStart(times, e.start);
          if (e.end > 0) ffi.timestampsSetEnd?.call(times, e.end);
          ffi.activitySetTimestamps(activity, times);
        }
        if (e.partyMax > 0 && ffi.hasParty) {
          ffi.partyInit!(party);
          partyInit = true;
          ffi.partySetId!(party, str('mediaflow-${e.name}').ref);
          ffi.partySetCurrentSize!(party, e.partyCurrent.clamp(0, e.partyMax).toInt());
          ffi.partySetMaxSize!(party, e.partyMax);
          ffi.activitySetParty!(activity, party);
        }
        if (e.buttons.isNotEmpty && ffi.hasButtons) {
          for (final (label, url) in e.buttons.take(2)) {
            final b = DiscordFfi.obj();
            buttons.add(b);
            ffi.buttonInit!(b);
            ffi.buttonSetLabel!(b, str(label).ref);
            ffi.buttonSetUrl!(b, str(url).ref);
            ffi.activityAddButton!(activity, b);
          }
        }
        late final NativeCallable<ResultCb> cb;
        cb = NativeCallable<ResultCb>.isolateLocal((Pointer<DOpaque> result, Pointer<Void> _) {
          cb.close();
          final (ok, error) = ffi.takeResult(result);
          if (!ok) {
            lastError = error;
            _sentKey = ''; // try again with the next change
          } else {
            lastError = '';
            accepted = e;
          }
          notifyListeners();
        });
        ffi.clientUpdatePresence(client, activity, cb.nativeFunction, nullptr, nullptr);
      });
    } catch (err) {
      lastError = '$err';
    } finally {
      try {
        for (final b in buttons) {
          ffi.buttonDrop?.call(b);
        }
        if (partyInit) ffi.partyDrop?.call(party);
        ffi.timestampsDrop(times);
        ffi.assetsDrop(assets);
        ffi.activityDrop(activity);
      } catch (_) {}
      for (final b in buttons) {
        calloc.free(b);
      }
      calloc.free(party);
      calloc.free(times);
      calloc.free(assets);
      calloc.free(activity);
    }
  }

  void _clear() {
    final ffi = _ffi, client = _client;
    if (ffi == null || client == null) return;
    try {
      ffi.clientClearPresence(client);
    } catch (_) {}
    _sentKey = 'clear';
    accepted = null;
  }

  /// Clears the status (app closing or going to the background on a phone).
  void pause() => _clear();

  void resume() {
    _sentKey = '';
    _schedule();
  }
}

/// One status as sent to Discord.
class DiscordActivity {
  const DiscordActivity({
    required this.name,
    this.details,
    this.state,
    required this.large,
    this.largeText,
    this.small,
    this.smallText,
    required this.type,
    required this.statusLine,
    this.start = 0,
    this.end = 0,
    this.detailsUrl = '',
    this.stateUrl = '',
    this.largeUrl = '',
    this.smallUrl = '',
    this.partyCurrent = 0,
    this.partyMax = 0,
    this.buttons = const [],
    this.custom = false,
  });
  final String name, large;
  final String? details, state, largeText, small, smallText;
  final int type, statusLine, start, end, partyCurrent, partyMax;
  final String detailsUrl, stateUrl, largeUrl, smallUrl;
  final List<(String, String)> buttons;

  /// From Custom Status (not the automatic status).
  final bool custom;

  /// Kept for older callers: whether a timer runs.
  bool get timer => start > 0;

  /// The status line text Discord shows next to the verb.
  String get statusText => statusLine == 2 ? (details ?? name) : statusLine == 1 ? (state ?? name) : name;

  String get key => [
        name, details, state, large, largeText, small, smallText, type, statusLine, start, end,
        detailsUrl, stateUrl, largeUrl, smallUrl, partyCurrent, partyMax, buttons.map((b) => '${b.$1}>${b.$2}').join(','),
      ].join('|');
}
