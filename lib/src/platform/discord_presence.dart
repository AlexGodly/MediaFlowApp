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

import '../logic/presence_templates.dart';

import '../data/app_prefs.dart';
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

  /// What is actually shown: the situation's templates filled in, after the
  /// privacy settings.
  ({String details, String? state, String large, String largeText, String? small, String? smallText, int type, int statusLine, bool timer})?
      effective() {
    final c = config;
    final statusLine = switch (c.statusLine) { 'details' => 2, 'state' => 1, _ => 0 };
    final g = globals?.call() ?? const <String, String>{};
    if (_idle) {
      if (c.idle == 'clear') return null;
      final t = c.template('idle');
      final d = renderPresence(t.$1, g);
      return (
        details: _clip(d.isEmpty ? 'Idle in MediaFlow' : d),
        state: _opt(renderPresence(t.$2, g)),
        large: logoUrl,
        largeText: 'MediaFlow',
        small: null,
        smallText: null,
        type: ActivityType.playing,
        statusLine: statusLine,
        timer: false,
      );
    }
    final w = _wanted ?? const PresenceInfo(situation: 'other');
    final hidden = w.categoryId != null && c.hiddenCategories.contains(w.categoryId);
    if (c.privacy == 'minimal' || hidden) {
      return (
        details: 'Using MediaFlow',
        state: null,
        large: logoUrl,
        largeText: 'MediaFlow',
        small: null,
        smallText: null,
        type: ActivityType.playing,
        statusLine: 0,
        timer: c.timer != 'off',
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
    final details = renderPresence(t.$1, values);
    final state = renderPresence(t.$2, values);
    final cover = full && c.picture == 'cover' && (w.cover ?? '').startsWith('https://') ? w.cover! : null;
    final kind = switch (c.types[w.categoryId ?? '']) {
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
    return (
      details: _clip(details.isEmpty ? 'Using MediaFlow' : details),
      state: _opt(state),
      large: cover ?? logoUrl,
      largeText: _clip(largeText.isEmpty ? 'MediaFlow' : largeText),
      small: cover != null && c.smallPicture == 'logo' ? logoUrl : null,
      smallText: cover != null && c.smallPicture == 'logo' ? _clip(smallText.isEmpty ? 'MediaFlow' : smallText) : null,
      type: type,
      statusLine: statusLine,
      timer: c.timer != 'off',
    );
  }

  static String? _opt(String s) => s.trim().isEmpty ? null : _clip(s);

  static String _clip(String s) {
    final t = s.trim();
    if (t.length < 2) return '$t  '.substring(0, 2);
    return t.length > 128 ? '${t.substring(0, 127)}…' : t;
  }

  void _send() {
    final ffi = _ffi, client = _client;
    if (ffi == null || client == null || !enabled) return;
    final e = effective();
    final key = e == null ? 'clear' : '${e.details}|${e.state}|${e.large}|${e.largeText}|${e.small}|${e.smallText}|${e.type}|${e.statusLine}|${e.timer ? _startedAt : 0}';
    if (key == _sentKey) return;
    _lastSend = DateTime.now();
    _sentKey = key;
    if (e == null) {
      _clear();
      return;
    }
    final activity = DiscordFfi.obj(), assets = DiscordFfi.obj(), times = DiscordFfi.obj();
    try {
      using((a) {
        ffi.activityInit(activity);
        ffi.activitySetName(activity, DiscordFfi.str('MediaFlow', a).ref);
        ffi.activitySetType(activity, e.type);
        // What the short status line shows ("Watching MediaFlow" / "Watching Frieren").
        final display = a<Int32>()..value = e.statusLine;
        ffi.activitySetStatusDisplayType(activity, display);
        ffi.activitySetDetails(activity, DiscordFfi.str(e.details, a));
        if (e.state != null) ffi.activitySetState(activity, DiscordFfi.str(e.state!, a));
        ffi.assetsInit(assets);
        ffi.assetsSetLargeImage(assets, DiscordFfi.str(e.large, a));
        ffi.assetsSetLargeText(assets, DiscordFfi.str(e.largeText, a));
        if (e.small != null) {
          ffi.assetsSetSmallImage(assets, DiscordFfi.str(e.small!, a));
          ffi.assetsSetSmallText(assets, DiscordFfi.str(e.smallText ?? 'MediaFlow', a));
        }
        ffi.activitySetAssets(activity, assets);
        ffi.timestampsInit(times);
        if (e.timer) {
          ffi.timestampsSetStart(times, _startedAt);
          ffi.activitySetTimestamps(activity, times);
        }
        late final NativeCallable<ResultCb> cb;
        cb = NativeCallable<ResultCb>.isolateLocal((Pointer<DOpaque> result, Pointer<Void> _) {
          cb.close();
          final (ok, error) = ffi.takeResult(result);
          if (!ok) {
            lastError = error;
            _sentKey = ''; // try again with the next change
            notifyListeners();
          } else if (lastError.isNotEmpty) {
            lastError = '';
            notifyListeners();
          }
        });
        ffi.clientUpdatePresence(client, activity, cb.nativeFunction, nullptr, nullptr);
      });
    } catch (err) {
      lastError = '$err';
    } finally {
      try {
        ffi.timestampsDrop(times);
        ffi.assetsDrop(assets);
        ffi.activityDrop(activity);
      } catch (_) {}
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
  }

  /// Clears the status (app closing or going to the background on a phone).
  void pause() => _clear();

  void resume() {
    _sentKey = '';
    _schedule();
  }
}
