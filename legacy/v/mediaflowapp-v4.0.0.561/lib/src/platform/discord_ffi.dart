// Bindings to the Discord Social SDK's C interface (cdiscord.h, SDK
// 1.10.19337) — only what Rich Presence and account linking need. The SDK is
// bundled by CI (tool/discord_sdk.py); when it is missing, [DiscordFfi.load]
// returns null and the app works without Rich Presence.

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// `Discord_String` {ptr, size}.
final class DString extends Struct {
  external Pointer<Uint8> ptr;
  @Size()
  external int size;
}

/// Every SDK object is a struct holding one opaque pointer.
final class DOpaque extends Struct {
  external Pointer<Void> opaque;
}

typedef _VoidObj = Void Function(Pointer<DOpaque>);
typedef _VoidObjD = void Function(Pointer<DOpaque>);
typedef _SetStrPtr = Void Function(Pointer<DOpaque>, Pointer<DString>);
typedef _SetStrPtrD = void Function(Pointer<DOpaque>, Pointer<DString>);
typedef _SetStr = Void Function(Pointer<DOpaque>, DString);
typedef _SetStrD = void Function(Pointer<DOpaque>, DString);
typedef _SetU64 = Void Function(Pointer<DOpaque>, Uint64);
typedef _SetU64D = void Function(Pointer<DOpaque>, int);
typedef _SetI32 = Void Function(Pointer<DOpaque>, Int32);
typedef _SetI32D = void Function(Pointer<DOpaque>, int);
typedef _SetObj = Void Function(Pointer<DOpaque>, Pointer<DOpaque>);
typedef _SetObjD = void Function(Pointer<DOpaque>, Pointer<DOpaque>);
typedef _BoolObj = Bool Function(Pointer<DOpaque>);
typedef _BoolObjD = bool Function(Pointer<DOpaque>);
typedef _I32Obj = Int32 Function(Pointer<DOpaque>);
typedef _I32ObjD = int Function(Pointer<DOpaque>);
typedef _GetStr = Void Function(Pointer<DOpaque>, Pointer<DString>);
typedef _GetStrD = void Function(Pointer<DOpaque>, Pointer<DString>);

// Callbacks (all receive a user-data pointer last).
typedef ResultCb = Void Function(Pointer<DOpaque> result, Pointer<Void> userData);
typedef AuthorizeCb = Void Function(Pointer<DOpaque> result, DString code, DString redirectUri, Pointer<Void> userData);
typedef TokenCb = Void Function(
    Pointer<DOpaque> result, DString access, DString refresh, Int32 tokenType, Int32 expiresIn, DString scopes, Pointer<Void> userData);
typedef StatusCb = Void Function(Int32 status, Int32 error, Int32 detail, Pointer<Void> userData);

typedef _WithCb<T extends Function> = Void Function(Pointer<DOpaque>, Pointer<NativeFunction<T>>, Pointer<Void>, Pointer<Void>);

/// `Discord_ActivityTypes`.
abstract final class ActivityType {
  static const playing = 0, listening = 2, watching = 3;
}

/// `Discord_Client_Status`.
abstract final class ClientStatus {
  static const disconnected = 0, connecting = 1, connected = 2, ready = 3, reconnecting = 4;
}

class DiscordFfi {
  DiscordFfi._(DynamicLibrary l)
      : runCallbacks = l.lookupFunction<Void Function(), void Function()>('Discord_RunCallbacks'),
        free = l.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('Discord_Free'),
        clientInit = l.lookupFunction<_VoidObj, _VoidObjD>('Discord_Client_Init'),
        clientDrop = l.lookupFunction<_VoidObj, _VoidObjD>('Discord_Client_Drop'),
        clientSetAppId = l.lookupFunction<_SetU64, _SetU64D>('Discord_Client_SetApplicationId'),
        clientConnect = l.lookupFunction<_VoidObj, _VoidObjD>('Discord_Client_Connect'),
        clientDisconnect = l.lookupFunction<_VoidObj, _VoidObjD>('Discord_Client_Disconnect'),
        clientStatus = l.lookupFunction<_I32Obj, _I32ObjD>('Discord_Client_GetStatus'),
        clientClearPresence = l.lookupFunction<_VoidObj, _VoidObjD>('Discord_Client_ClearRichPresence'),
        clientUpdatePresence = l.lookupFunction<
            Void Function(Pointer<DOpaque>, Pointer<DOpaque>, Pointer<NativeFunction<ResultCb>>, Pointer<Void>, Pointer<Void>),
            void Function(Pointer<DOpaque>, Pointer<DOpaque>, Pointer<NativeFunction<ResultCb>>, Pointer<Void>, Pointer<Void>)>(
          'Discord_Client_UpdateRichPresence',
        ),
        clientSetStatusChanged = l.lookupFunction<_WithCb<StatusCb>,
            void Function(Pointer<DOpaque>, Pointer<NativeFunction<StatusCb>>, Pointer<Void>, Pointer<Void>)>(
          'Discord_Client_SetStatusChangedCallback',
        ),
        defaultPresenceScopes =
            l.lookupFunction<Void Function(Pointer<DString>), void Function(Pointer<DString>)>('Discord_Client_GetDefaultPresenceScopes'),
        createVerifier = l.lookupFunction<_SetObj, _SetObjD>('Discord_Client_CreateAuthorizationCodeVerifier'),
        verifierChallenge = l.lookupFunction<_SetObj, _SetObjD>('Discord_AuthorizationCodeVerifier_Challenge'),
        verifierVerifier = l.lookupFunction<_GetStr, _GetStrD>('Discord_AuthorizationCodeVerifier_Verifier'),
        verifierDrop = l.lookupFunction<_VoidObj, _VoidObjD>('Discord_AuthorizationCodeVerifier_Drop'),
        challengeDrop = l.lookupFunction<_VoidObj, _VoidObjD>('Discord_AuthorizationCodeChallenge_Drop'),
        argsInit = l.lookupFunction<_VoidObj, _VoidObjD>('Discord_AuthorizationArgs_Init'),
        argsDrop = l.lookupFunction<_VoidObj, _VoidObjD>('Discord_AuthorizationArgs_Drop'),
        argsSetClientId = l.lookupFunction<_SetU64, _SetU64D>('Discord_AuthorizationArgs_SetClientId'),
        argsSetScopes = l.lookupFunction<_SetStr, _SetStrD>('Discord_AuthorizationArgs_SetScopes'),
        argsSetChallenge = l.lookupFunction<_SetObj, _SetObjD>('Discord_AuthorizationArgs_SetCodeChallenge'),
        clientAuthorize = l.lookupFunction<
            Void Function(Pointer<DOpaque>, Pointer<DOpaque>, Pointer<NativeFunction<AuthorizeCb>>, Pointer<Void>, Pointer<Void>),
            void Function(Pointer<DOpaque>, Pointer<DOpaque>, Pointer<NativeFunction<AuthorizeCb>>, Pointer<Void>, Pointer<Void>)>(
          'Discord_Client_Authorize',
        ),
        clientGetToken = l.lookupFunction<
            Void Function(Pointer<DOpaque>, Uint64, DString, DString, DString, Pointer<NativeFunction<TokenCb>>, Pointer<Void>, Pointer<Void>),
            void Function(Pointer<DOpaque>, int, DString, DString, DString, Pointer<NativeFunction<TokenCb>>, Pointer<Void>, Pointer<Void>)>(
          'Discord_Client_GetToken',
        ),
        clientRefreshToken = l.lookupFunction<
            Void Function(Pointer<DOpaque>, Uint64, DString, Pointer<NativeFunction<TokenCb>>, Pointer<Void>, Pointer<Void>),
            void Function(Pointer<DOpaque>, int, DString, Pointer<NativeFunction<TokenCb>>, Pointer<Void>, Pointer<Void>)>(
          'Discord_Client_RefreshToken',
        ),
        clientUpdateToken = l.lookupFunction<
            Void Function(Pointer<DOpaque>, Int32, DString, Pointer<NativeFunction<ResultCb>>, Pointer<Void>, Pointer<Void>),
            void Function(Pointer<DOpaque>, int, DString, Pointer<NativeFunction<ResultCb>>, Pointer<Void>, Pointer<Void>)>(
          'Discord_Client_UpdateToken',
        ),
        resultSuccessful = l.lookupFunction<_BoolObj, _BoolObjD>('Discord_ClientResult_Successful'),
        resultError = l.lookupFunction<_GetStr, _GetStrD>('Discord_ClientResult_Error'),
        resultDrop = l.lookupFunction<_VoidObj, _VoidObjD>('Discord_ClientResult_Drop'),
        activityInit = l.lookupFunction<_VoidObj, _VoidObjD>('Discord_Activity_Init'),
        activityDrop = l.lookupFunction<_VoidObj, _VoidObjD>('Discord_Activity_Drop'),
        activitySetName = l.lookupFunction<_SetStr, _SetStrD>('Discord_Activity_SetName'),
        activitySetType = l.lookupFunction<_SetI32, _SetI32D>('Discord_Activity_SetType'),
        activitySetStatusDisplayType = l.lookupFunction<Void Function(Pointer<DOpaque>, Pointer<Int32>), void Function(Pointer<DOpaque>, Pointer<Int32>)>(
          'Discord_Activity_SetStatusDisplayType',
        ),
        activitySetState = l.lookupFunction<_SetStrPtr, _SetStrPtrD>('Discord_Activity_SetState'),
        activitySetDetails = l.lookupFunction<_SetStrPtr, _SetStrPtrD>('Discord_Activity_SetDetails'),
        activitySetAssets = l.lookupFunction<_SetObj, _SetObjD>('Discord_Activity_SetAssets'),
        activitySetTimestamps = l.lookupFunction<_SetObj, _SetObjD>('Discord_Activity_SetTimestamps'),
        assetsInit = l.lookupFunction<_VoidObj, _VoidObjD>('Discord_ActivityAssets_Init'),
        assetsDrop = l.lookupFunction<_VoidObj, _VoidObjD>('Discord_ActivityAssets_Drop'),
        assetsSetLargeImage = l.lookupFunction<_SetStrPtr, _SetStrPtrD>('Discord_ActivityAssets_SetLargeImage'),
        assetsSetLargeText = l.lookupFunction<_SetStrPtr, _SetStrPtrD>('Discord_ActivityAssets_SetLargeText'),
        assetsSetSmallImage = l.lookupFunction<_SetStrPtr, _SetStrPtrD>('Discord_ActivityAssets_SetSmallImage'),
        assetsSetSmallText = l.lookupFunction<_SetStrPtr, _SetStrPtrD>('Discord_ActivityAssets_SetSmallText'),
        timestampsInit = l.lookupFunction<_VoidObj, _VoidObjD>('Discord_ActivityTimestamps_Init'),
        timestampsDrop = l.lookupFunction<_VoidObj, _VoidObjD>('Discord_ActivityTimestamps_Drop'),
        timestampsSetStart = l.lookupFunction<_SetU64, _SetU64D>('Discord_ActivityTimestamps_SetStart');

  static DiscordFfi? _instance;
  static bool _tried = false;
  static String loadError = '';

  /// The SDK bundled with this build, or null when it is not there.
  static DiscordFfi? load() {
    if (_tried) return _instance;
    _tried = true;
    try {
      final lib = Platform.isWindows
          ? DynamicLibrary.open('discord_partner_sdk.dll')
          : Platform.isAndroid
              ? DynamicLibrary.open('libdiscord_partner_sdk.so')
              : Platform.isIOS
                  ? DynamicLibrary.open('discord_partner_sdk.framework/discord_partner_sdk')
                  : throw UnsupportedError('Discord Rich Presence is not available on this platform');
      _instance = DiscordFfi._(lib);
    } catch (e) {
      loadError = '$e';
      _instance = null;
    }
    return _instance;
  }

  final void Function() runCallbacks;
  final void Function(Pointer<Void>) free;
  final _VoidObjD clientInit, clientDrop, clientConnect, clientDisconnect, clientClearPresence;
  final _SetU64D clientSetAppId;
  final _I32ObjD clientStatus;
  final void Function(Pointer<DOpaque>, Pointer<DOpaque>, Pointer<NativeFunction<ResultCb>>, Pointer<Void>, Pointer<Void>)
      clientUpdatePresence;
  final void Function(Pointer<DOpaque>, Pointer<NativeFunction<StatusCb>>, Pointer<Void>, Pointer<Void>) clientSetStatusChanged;
  final void Function(Pointer<DString>) defaultPresenceScopes;
  final _SetObjD createVerifier, verifierChallenge, argsSetChallenge;
  final _GetStrD verifierVerifier, resultError;
  final _VoidObjD verifierDrop, challengeDrop, argsInit, argsDrop;
  final _SetU64D argsSetClientId;
  final _SetStrD argsSetScopes;
  final void Function(Pointer<DOpaque>, Pointer<DOpaque>, Pointer<NativeFunction<AuthorizeCb>>, Pointer<Void>, Pointer<Void>)
      clientAuthorize;
  final void Function(Pointer<DOpaque>, int, DString, DString, DString, Pointer<NativeFunction<TokenCb>>, Pointer<Void>, Pointer<Void>)
      clientGetToken;
  final void Function(Pointer<DOpaque>, int, DString, Pointer<NativeFunction<TokenCb>>, Pointer<Void>, Pointer<Void>) clientRefreshToken;
  final void Function(Pointer<DOpaque>, int, DString, Pointer<NativeFunction<ResultCb>>, Pointer<Void>, Pointer<Void>) clientUpdateToken;
  final _BoolObjD resultSuccessful;
  final _VoidObjD resultDrop;
  final _VoidObjD activityInit, activityDrop, assetsInit, assetsDrop, timestampsInit, timestampsDrop;
  final _SetStrD activitySetName;
  final _SetI32D activitySetType;
  final void Function(Pointer<DOpaque>, Pointer<Int32>) activitySetStatusDisplayType;
  final _SetStrPtrD activitySetState, activitySetDetails, assetsSetLargeImage, assetsSetLargeText, assetsSetSmallImage, assetsSetSmallText;
  final _SetObjD activitySetAssets, activitySetTimestamps;
  final _SetU64D timestampsSetStart;

  // ---- helpers ----

  /// A new SDK object (struct of one opaque pointer), zeroed.
  static Pointer<DOpaque> obj() => calloc<DOpaque>();

  /// A Discord_String holding [s] (UTF-8). Free with [freeStr].
  static Pointer<DString> str(String s, Arena arena) {
    final bytes = utf8.encode(s);
    final data = arena<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    data.asTypedList(bytes.length).setAll(0, bytes);
    final d = arena<DString>();
    d.ref.ptr = data;
    d.ref.size = bytes.length;
    return d;
  }

  /// Reads a Discord_String the SDK handed over (not freed).
  static String read(DString s) => s.size == 0 || s.ptr == nullptr ? '' : utf8.decode(s.ptr.asTypedList(s.size), allowMalformed: true);

  /// Reads and frees a Discord_String the SDK returned into [out].
  String take(Pointer<DString> out) {
    final text = read(out.ref);
    if (out.ref.ptr != nullptr) free(out.ref.ptr.cast());
    return text;
  }

  /// Reads a string a callback handed over and frees it (the callback owns it).
  String takeValue(DString s) {
    final text = read(s);
    if (s.ptr != nullptr) free(s.ptr.cast());
    return text;
  }

  /// Whether a callback's result succeeded (and its error text); frees it.
  (bool, String) takeResult(Pointer<DOpaque> result) {
    if (result == nullptr) return (false, 'No result');
    final ok = resultSuccessful(result);
    final error = ok ? '' : errorOf(result);
    resultDrop(result);
    return (ok, error);
  }

  String errorOf(Pointer<DOpaque> result) => using((arena) {
        final out = arena<DString>();
        resultError(result, out);
        return take(out);
      });
}
