// Covers for offline use: every cover is kept once it has been shown; on top
// of that the user can keep the covers of all titles, chosen categories or
// chosen titles on this device ahead of time, kept up to date after each sync.
// AppPrefs (this device): offlineCoverMode 'shown' | 'all' | 'categories' |
// 'titles', offlineCoverCategories, offlineCoverTitles.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../state/models.dart';
import 'account_controller.dart';
import 'app_prefs.dart';
import 'cover_cache.dart';

class OfflineCovers extends ChangeNotifier {
  OfflineCovers._();
  static final OfflineCovers instance = OfflineCovers._();

  AccountController? _account;
  bool running = false;
  bool _cancel = false;
  int done = 0, total = 0, failed = 0;
  DateTime? _lastRun;

  static String get mode => AppPrefs.instance.get<String>('offlineCoverMode', 'shown');
  static Set<String> get categories => {for (final x in AppPrefs.instance.get<List>('offlineCoverCategories', const [])) '$x'};
  static Set<String> get titles => {for (final x in AppPrefs.instance.get<List>('offlineCoverTitles', const [])) '$x'};

  void attach(AccountController account) {
    if (identical(_account, account)) return;
    _account?.removeListener(_changed);
    _account = account;
    account.addListener(_changed);
  }

  // After a sync brings new titles, top up (at most every 10 minutes).
  void _changed() {
    if (mode == 'shown' || running) return;
    if (_lastRun != null && DateTime.now().difference(_lastRun!) < const Duration(minutes: 10)) return;
    unawaited(run());
  }

  /// The cover links the chosen scope covers.
  static List<String> urlsFor(AccountView view, {String? scope, Set<String>? cats, Set<String>? ids}) {
    final m = scope ?? mode;
    final c = cats ?? categories, t = ids ?? titles;
    final out = <String>{};
    for (final title in view.library) {
      final keep = switch (m) {
        'all' => true,
        'categories' => c.contains(title.categoryId),
        'titles' => t.contains(title.id),
        _ => false,
      };
      final url = title.coverUrl;
      if (keep && url.startsWith('http')) out.add(url);
    }
    return out.toList();
  }

  /// The links that could not be downloaded in the last run (10.0.0); the
  /// reason for each is in `CoverCache.instance.failures`.
  final List<String> failedUrls = [];

  /// Downloads the covers of the chosen scope that are not on the device yet.
  /// A failure that may pass (a timeout, a busy or refusing host, no
  /// connection) is tried again twice, a little later; nothing is ever marked
  /// unavailable for good — the next run tries every missing cover again.
  /// [only] limits the run to these links (Retry).
  Future<void> run({String? scope, Set<String>? cats, Set<String>? ids, List<String>? only}) async {
    final view = _account?.view;
    if (view == null || running) return;
    final urls = only ?? urlsFor(view, scope: scope, cats: cats, ids: ids);
    running = true;
    _cancel = false;
    done = 0;
    failed = 0;
    failedUrls.clear();
    total = urls.length;
    _lastRun = DateTime.now();
    notifyListeners();
    try {
      // A few at a time: fast, without flooding the image hosts or memory.
      var next = 0;
      Future<void> worker() async {
        while (!_cancel && next < urls.length) {
          final url = urls[next++];
          var f = await CoverCache.instance.file(url);
          for (var attempt = 1; f == null && attempt <= 2 && !_cancel; attempt++) {
            if (CoverCache.instance.failures[url]?.recoverable != true) break;
            await Future<void>.delayed(Duration(seconds: attempt * 3));
            f = await CoverCache.instance.file(url);
          }
          if (f == null) {
            failed++;
            failedUrls.add(url);
          }
          done++;
          if (done % 10 == 0 || done == total) notifyListeners();
        }
      }

      await Future.wait([for (var i = 0; i < 4; i++) worker()]);
    } finally {
      running = false;
      notifyListeners();
    }
  }

  /// Tries the covers that failed in the last run again.
  Future<void> retryFailed() => run(only: List.of(failedUrls));

  /// The titles behind the failed links, with the reason.
  List<({LibraryTitle title, String reason, bool recoverable})> failures(AccountView view) {
    final byUrl = <String, List<LibraryTitle>>{};
    for (final t in view.library) {
      if (t.coverUrl.isNotEmpty) (byUrl[t.coverUrl] ??= []).add(t);
    }
    return [
      for (final url in failedUrls)
        for (final t in byUrl[url] ?? const <LibraryTitle>[])
          (
            title: t,
            reason: CoverCache.instance.failures[url]?.reason ?? 'Not downloaded',
            recoverable: CoverCache.instance.failures[url]?.recoverable ?? true,
          ),
    ];
  }

  void cancel() => _cancel = true;
}
