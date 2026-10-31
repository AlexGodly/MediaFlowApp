// The website's recommendation logging form, as data: `S.logDraft` and
// `S.entryDraft` from MediaFlow v554, edited with the same rules the website's
// form actions use (openLogForm, addLogEntry, v179 progress mode, v252 seasons,
// v369 per-unit "Advanced" logging, v394/v400 Progress Reached / Amount Consumed).
//
// The draft maps are stored in the account (resumeStateV285.logging) unchanged,
// so a draft started in the app continues on the website and vice versa.

import 'dart:math' as math;

import '../util/js.dart';
import 'log_engine.dart' show normalizeSeasons;

typedef Clock = int Function();

int _systemNow() => DateTime.now().millisecondsSinceEpoch;

class LogDraftEditor {
  LogDraftEditor({
    required this.state,
    required this.task,
    required this.logDraft,
    required this.entryDraft,
    Clock? clock,
    String Function()? uid,
  })  : clock = clock ?? _systemNow,
        _uid = uid;

  /// The account (read only here: Library, categories, History, settings).
  final Map<String, dynamic> state;
  final Map<String, dynamic> task;
  final Map<String, dynamic> logDraft;
  Map<String, dynamic> entryDraft;
  final Clock clock;
  final String Function()? _uid;

  String uid() => _uid?.call() ?? mediaFlowUid(clock());

  // ---- opening -----------------------------------------------------------------

  /// `App.openLogForm` (base → v179 → v181 → v369).
  static LogDraftEditor open(Map<String, dynamic> state, Map<String, dynamic> task,
      {Clock? clock, String Function()? uid}) {
    final editor = LogDraftEditor(
      state: state,
      task: task,
      logDraft: <String, dynamic>{},
      entryDraft: <String, dynamic>{'title': '', 'qty': 1},
      clock: clock,
      uid: uid,
    );
    final cat = editor.category(jsStr(task['categoryId']));
    final mid = jsNum(task['targetMid']);
    editor.logDraft
      ..['categoryId'] = task['categoryId']
      ..['amount'] = task['targetMid']
      ..['minutes'] = jsOut(jsRound(mid * jsNum(cat['minutesPerUnit'])))
      ..['note'] = ''
      ..['entries'] = <dynamic>[]
      ..['updateLibrary'] = true;
    final mode = editor.defaultMode;
    editor.logDraft['v179Mode'] = mode;
    if (mode == 'progress') {
      editor.logDraft
        ..['updateLibrary'] = true
        ..['amount'] = 0
        ..['minutes'] = 0;
      editor.entryDraft = {'title': '', 'qty': 1, 'libraryId': null, 'endProgress': ''};
    }
    editor.logDraft['v369Interface'] = editor.defaultInterface;
    editor.logDraft['v369CommitId'] = editor.uid();
    if (editor.logDraft['v369Interface'] == 'itemized') editor.logDraft['v179Mode'] = 'amount';
    return editor;
  }

  // ---- lookups -----------------------------------------------------------------

  Map<String, dynamic> get settings => asMap(state['settings']) ?? const {};

  List<Map<String, dynamic>> get library =>
      asList(state['library']).map(asMap).whereType<Map<String, dynamic>>().toList();

  Map<String, dynamic>? item(Object? id) {
    final s = jsStr(id);
    if (s.isEmpty) return null;
    for (final i in library) {
      if (jsStr(i['id']) == s) return i;
    }
    return null;
  }

  Map<String, dynamic> category(String id) {
    final cats = asList(state['categories']).map(asMap).whereType<Map<String, dynamic>>().toList();
    for (final c in cats) {
      if (jsStr(c['id']) == id) return c;
    }
    return cats.isNotEmpty ? cats.first : <String, dynamic>{'id': id, 'unit': 'episodes', 'minutesPerUnit': 0};
  }

  /// `v181DefaultLoggingMode`.
  String get defaultMode => asMap(settings['v181Logging'])?['defaultMode'] == 'amount' ? 'amount' : 'progress';

  /// `v369DefaultInterface`.
  String get defaultInterface =>
      asMap(settings['v369Logging'])?['defaultInterface'] == 'quick' ? 'quick' : 'itemized';

  bool get itemized => logDraft['v369Interface'] == 'itemized';

  /// `v179Mode('single')` while logging.
  String get mode => logDraft['v179Mode'] == null
      ? defaultMode
      : (logDraft['v179Mode'] == 'progress' ? 'progress' : 'amount');

  List<Map<String, dynamic>> get entries {
    final list = logDraft['entries'];
    if (list is! List) logDraft['entries'] = <dynamic>[];
    return asList(logDraft['entries']).map(asMap).whereType<Map<String, dynamic>>().toList();
  }

  Map<String, dynamic>? entry(int index) {
    final list = asList(logDraft['entries']);
    return index >= 0 && index < list.length ? asMap(list[index]) : null;
  }

  // ---- shared rules ----------------------------------------------------------------

  static bool isComplete(Map<String, dynamic>? item) {
    if (item == null) return false;
    if (jsStr(item['status']) == 'completed') return true;
    final total = jsNum(item['total']);
    return total > 0 && jsNum(item['progress']) >= total;
  }

  /// `v179StartProgress`: a completed title is a rewatch, starting at 0.
  static double startProgress(Map<String, dynamic>? item) {
    if (item == null || isComplete(item)) return 0;
    return math.max(0, jsNum(item['progress']));
  }

  /// `v179ClampEndProgress`.
  static double clampEnd(Map<String, dynamic>? item, Object? value) {
    var end = math.max(0.0, jsNum(value));
    final total = jsNumOrNull(item?['total']);
    if (total != null && total.isFinite && total > 0) end = math.min(end, total);
    return end;
  }

  static double calculatedQty(Map<String, dynamic>? item, Object? start, Object? end) =>
      math.max(0.0, clampEnd(item, end) - math.max(0.0, jsNum(start)));

  static List<Map<String, dynamic>> seasonsOf(Map<String, dynamic>? item) {
    if (item == null) return const [];
    final source = jsStr(item['seasonSource']).isEmpty ? 'manual' : jsStr(item['seasonSource']);
    return normalizeSeasons(item['seasons'], source);
  }

  /// `v252SeasonOffset`.
  static int seasonOffset(Map<String, dynamic> item, String seasonId) {
    var offset = 0.0;
    for (final s in seasonsOf(item)) {
      if (jsStr(s['id']) == seasonId) break;
      offset += s['total'] != null && jsNum(s['total']) > 0 ? jsNum(s['total']) : jsNum(s['progress']);
    }
    return math.max(0, jsRound(offset).toInt());
  }

  /// `v252SeasonGlobalEnd`.
  static double seasonGlobalEnd(Map<String, dynamic> item, String seasonId, Object? local) {
    final season = seasonsOf(item).where((s) => jsStr(s['id']) == seasonId).firstOrNull;
    if (season == null) return clampEnd(item, local);
    var l = _v252Num(local);
    if (jsNum(season['total']) > 0) l = math.min(l, jsNum(season['total']));
    return clampEnd(item, seasonOffset(item, seasonId) + l);
  }

  static double _v252Num(Object? v) {
    final n = jsNumOrNull(v);
    return n != null && n.isFinite ? math.max(0, jsRound(n)) : 0;
  }

  /// `findLibraryMatch` (exact title in a category).
  Map<String, dynamic>? findLibraryMatch(String categoryId, String title) {
    final q = cleanTitle(title).trim().toLowerCase();
    if (q.isEmpty) return null;
    for (final i in library) {
      if (jsStr(i['categoryId']) == categoryId && cleanTitle(i['title']).trim().toLowerCase() == q) return i;
    }
    return null;
  }

  Map<String, dynamic>? _resolveTyped(String title) {
    final assigned = jsStr(task['categoryId']);
    var match = item(entryDraft['libraryId']);
    match ??= findLibraryMatch(assigned, title);
    if (match == null) {
      final key = cleanTitle(title).toLowerCase();
      for (final i in library) {
        if (i['status'] != 'dropped' && cleanTitle(i['title']).toLowerCase() == key) return i;
      }
    }
    return match;
  }

  /// `v179SyncSingleFromEntries`.
  void syncSingle() {
    var amount = 0.0, minutes = 0.0;
    for (final e in entries) {
      final qty = math.max(0.0, jsNum(e['qty']));
      amount += qty;
      final i = item(e['libraryId']);
      final cat = category(i != null ? jsStr(i['categoryId']) : jsStr(task['categoryId']));
      minutes += jsRound(qty * jsNum(cat['minutesPerUnit']));
    }
    logDraft['amount'] = jsOut(amount);
    logDraft['minutes'] = jsOut(minutes);
  }

  // ---- Quick logging ------------------------------------------------------------

  /// Picks a Library title (or a typed new title) for the next quick entry.
  void chooseTitle({String? libraryId, required String title}) {
    entryDraft = {
      ...entryDraft,
      'title': title,
      'libraryId': libraryId,
      if (mode == 'progress') 'endProgress': '',
    };
    final i = item(libraryId);
    if (i != null && mode == 'progress') {
      final seasons = seasonsOf(i);
      if (seasons.isNotEmpty) {
        // Default to the season holding the next unwatched episode.
        var target = seasons.first;
        for (final s in seasons) {
          final total = jsNum(s['total']);
          if (!(total > 0) || jsNum(s['progress']) < total) {
            target = s;
            break;
          }
        }
        entryDraft['v252SeasonId'] = jsStr(target['id']);
        entryDraft['v252SeasonEpisode'] = jsOut(jsNum(target['progress']) + 1);
      }
      entryDraft['endProgress'] = jsOut(clampEnd(i, startProgress(i) + 1));
    }
  }

  /// `App.addLogEntry` for the Quick form (amount or progress mode). Returns an
  /// error message, or null when the entry was added or updated.
  String? addQuickEntry() {
    if (itemized) return addItemizedEntry();
    final title = jsStr(entryDraft['title']).trim();
    if (title.isEmpty) return 'Choose or type a title first.';
    final selected = item(entryDraft['libraryId']);
    // v252: season view in progress mode.
    final useSeason = selected != null && seasonsOf(selected).isNotEmpty && mode == 'progress' &&
        entryDraft['v252UseSeasonView'] != false;
    final seasonId = jsStr(entryDraft['v252SeasonId']);
    final seasonEpisode = _v252Num(entryDraft['v252SeasonEpisode']);
    if (useSeason) entryDraft['endProgress'] = jsOut(seasonGlobalEnd(selected, seasonId, seasonEpisode));

    if (mode == 'progress') {
      final match = _resolveTyped(title);
      final start = match != null ? startProgress(match) : 0.0;
      var end = math.max(start, jsNum(entryDraft['endProgress']));
      if (match != null) end = clampEnd(match, end);
      final qty = math.max(0.0, end - start);
      if (qty <= 0) {
        return match != null
            ? 'Enter a ${_progressLabel(match).toLowerCase()} higher than ${_fmt(start)}.'
            : 'Enter the final progress you reached.';
      }
      if (match != null) {
        final existing = entries.indexWhere((e) => jsStr(e['libraryId']) == jsStr(match['id']));
        if (existing >= 0) {
          final e = entries[existing];
          final s = jsNumFromKey(e, 'v179StartProgress');
          e['v179StartProgress'] = jsOut(s != null && s.isFinite ? math.max(0, s) : start);
          e['v179EndProgress'] = jsOut(end);
          e['qty'] = jsOut(calculatedQty(match, e['v179StartProgress'], e['v179EndProgress']));
          _applySeasonMeta(e, selected, useSeason, seasonId, seasonEpisode);
          entryDraft = {'title': '', 'qty': 1, 'libraryId': null, 'endProgress': ''};
          syncSingle();
          return null;
        }
      }
      entryDraft['qty'] = jsOut(qty);
      logDraft['updateLibrary'] = true;
      final e = _baseAdd(title, match);
      final saved = item(e['libraryId']) ?? match;
      e['v179StartProgress'] = jsOut(saved != null ? startProgress(saved) : start);
      e['v179EndProgress'] = jsOut(saved != null ? clampEnd(saved, end) : end);
      e['qty'] = jsOut(saved != null ? calculatedQty(saved, e['v179StartProgress'], e['v179EndProgress']) : qty);
      _applySeasonMeta(e, selected, useSeason, seasonId, seasonEpisode);
      entryDraft = {'title': '', 'qty': 1, 'libraryId': null, 'endProgress': ''};
      syncSingle();
      return null;
    }
    final match = _resolveTyped(title);
    final e = _baseAdd(title, match);
    _applySeasonMeta(e, selected, false, seasonId, seasonEpisode);
    entryDraft = {'title': '', 'qty': 1, 'libraryId': null};
    return null;
  }

  /// Base `addLogEntry`: a new typed title is created on submit (kept as
  /// `isNew` with no Library id until then).
  Map<String, dynamic> _baseAdd(String title, Map<String, dynamic>? match) {
    final raw = jsNum(entryDraft['qty']);
    final qty = math.max(1.0, raw == 0 || raw.isNaN ? 1.0 : raw);
    final stamp = clock();
    final isRepeat = match != null &&
        (match['status'] == 'completed' || (jsNum(match['total']) > 0 && jsNum(match['progress']) >= jsNum(match['total'])));
    final e = <String, dynamic>{
      'title': title,
      'qty': jsOut(qty),
      'libraryId': match?['id'],
      'isNew': match == null,
      'isRepeat': isRepeat,
      'loggedAt': stamp,
      'v394When': stamp,
    };
    logDraft['entries'] = List<dynamic>.of(asList(logDraft['entries']))..add(e);
    return e;
  }

  void _applySeasonMeta(Map<String, dynamic> e, Map<String, dynamic>? selected, bool use, String seasonId, double episode) {
    if (selected == null || seasonsOf(selected).isEmpty || jsStr(e['libraryId']) != jsStr(selected['id'])) return;
    e['v252UseSeasonView'] = use;
    if (!use) return;
    final season = seasonsOf(selected).where((s) => jsStr(s['id']) == seasonId).firstOrNull;
    e['v252SeasonId'] = seasonId;
    e['v252SeasonNumber'] = season?['number'];
    e['v252SeasonName'] = jsStr(season?['name']);
    e['v252SeasonEpisode'] = jsOut(episode);
    e['v179EndProgress'] = jsOut(seasonGlobalEnd(selected, seasonId, episode));
    final start = e['v179StartProgress'] ?? startProgress(selected);
    e['qty'] = jsOut(calculatedQty(selected, start, e['v179EndProgress']));
  }

  /// `v179SetLogEntryEnd` (+ v525 quick touch).
  void setEntryEnd(int index, Object? value) {
    final e = entry(index);
    if (e == null) return;
    final i = item(e['libraryId']);
    if (i == null) return;
    final s = jsNumFromKey(e, 'v179StartProgress');
    final start = s != null && s.isFinite ? math.max(0.0, s) : startProgress(i);
    final before = e['v179EndProgress'];
    e['v179StartProgress'] = jsOut(start);
    e['v179EndProgress'] = jsOut(clampEnd(i, value));
    e['qty'] = jsOut(calculatedQty(i, start, e['v179EndProgress']));
    if (logDraft['v369Interface'] == 'quick' && jsNum(before) != jsNum(e['v179EndProgress'])) {
      e['v369UpdatedAt'] = clock();
    }
    syncSingle();
  }

  /// Amount mode: edit how much of a title was consumed.
  void setEntryQty(int index, Object? value) {
    final e = entry(index);
    if (e == null) return;
    e['qty'] = jsOut(math.max(0.0, jsNum(value)));
  }

  /// `v179SetLogMode('single', mode)` for this draft only.
  void setMode(String value) {
    final safe = value == 'progress' ? 'progress' : 'amount';
    logDraft['v179Mode'] = safe;
    if (safe != 'progress') return;
    logDraft['updateLibrary'] = true;
    for (final e in entries) {
      final i = item(e['libraryId']);
      if (i == null) continue;
      final s = jsNumFromKey(e, 'v179StartProgress');
      final start = s != null && s.isFinite ? math.max(0.0, s) : startProgress(i);
      e['v179StartProgress'] = jsOut(start);
      if (e['v179EndProgress'] == null || e['v179EndProgress'] == '') {
        final q = jsNum(e['qty']);
        e['v179EndProgress'] = jsOut(clampEnd(i, start + math.max(0.0, q == 0 ? 1 : q)));
      }
      e['qty'] = jsOut(calculatedQty(i, e['v179StartProgress'], e['v179EndProgress']));
    }
    syncSingle();
  }

  /// `v369SwitchInterface`: Quick ⇄ Advanced, only while no titles are added.
  String? switchInterface(String value) {
    if (entries.isNotEmpty) {
      return 'Remove session titles before changing the interface; this protects unfinished entries.';
    }
    final next = value == 'quick' ? 'quick' : 'itemized';
    logDraft['v369Interface'] = next;
    logDraft['v179Mode'] = next == 'itemized' ? 'amount' : defaultMode;
    return null;
  }

  /// `App.removeLogEntry`.
  void removeEntry(int index) {
    final list = asList(logDraft['entries']);
    if (index < 0 || index >= list.length) return;
    final removed = asMap(list[index]);
    final mutable = List<dynamic>.of(list)..removeAt(index);
    logDraft['entries'] = mutable;
    if (itemized && removed != null) {
      final id = jsStr(removed['libraryId']);
      if (!entries.any((e) => jsStr(e['libraryId']) == id)) {
        final deleted = asMap(logDraft['v369DeletedTitles']) ?? <String, dynamic>{};
        logDraft['v369DeletedTitles'] = {...deleted, id: clock()};
      }
      sync369();
    } else if (mode == 'progress') {
      syncSingle();
    }
  }

  // ---- Advanced (per unit) ------------------------------------------------------

  /// `App.addLogEntry` for the Advanced form: Library titles only.
  String? addItemizedEntry() {
    final id = jsStr(entryDraft['libraryId']);
    final typed = jsStr(entryDraft['title']).trim().toLowerCase();
    Map<String, dynamic>? i = id.isNotEmpty ? item(id) : null;
    if (i == null && typed.isNotEmpty) {
      for (final x in library) {
        if (cleanTitle(x['title']).toLowerCase() == typed && x['status'] != 'dropped') {
          i = x;
          break;
        }
      }
    }
    if (i == null) return 'Select a title from your Library for per-unit logging.';
    if (entries.any((e) => jsStr(e['libraryId']) == jsStr(i!['id']))) {
      return 'This title is already in your session. Open it to log another unit.';
    }
    final stamp = clock();
    final start = startProgress(i);
    final list = List<dynamic>.of(asList(logDraft['entries']))
      ..add(<String, dynamic>{
        'title': cleanTitle(i['title']),
        'libraryId': i['id'],
        'qty': 0,
        'v369UpdatedAt': stamp,
        'isRepeat': isComplete(i),
        'isNew': false,
        'loggedAt': stamp,
        'v394When': stamp,
        'v179StartProgress': jsOut(start),
        'v179EndProgress': jsOut(start),
        'v369Units': <dynamic>[],
        'v369SelectedSeasonId': '',
      });
    logDraft['entries'] = list;
    entryDraft = {'title': '', 'qty': 1, 'libraryId': null};
    sync369();
    return null;
  }

  static double unitSeconds(Map<String, dynamic> u) {
    final d = jsNumFromKey(u, 'durationSeconds');
    if (d != null) return math.max(0, d.floorToDouble());
    return math.max(0, jsRound(jsNum(u['minutes']) * 60));
  }

  /// `v369DefaultSeconds`.
  double defaultSeconds(Map<String, dynamic>? i) {
    final cat = category(jsStr(i?['categoryId']));
    final sec = jsNumFromKey(cat, 'secondsPerUnit');
    if (sec != null) return math.max(0, sec.floorToDouble());
    return math.max(0, jsRound(jsNum(cat['minutesPerUnit']) * 60));
  }

  List<Map<String, dynamic>> units(Map<String, dynamic> e) =>
      asList(e['v369Units']).map(asMap).whereType<Map<String, dynamic>>().toList();

  /// Units saved in History for [i] (`v369KnownUnits`).
  List<Map<String, dynamic>> knownUnits(Map<String, dynamic>? i) {
    final id = jsStr(i?['id']);
    if (id.isEmpty) return const [];
    final rows = <Map<String, dynamic>>[];
    for (final s in asList(state['sessions'])) {
      for (final t in asList(asMap(s)?['titles'])) {
        final m = asMap(t);
        if (m == null || jsStr(m['libraryId']) != id || m['repeat'] == true) continue;
        for (final u in asList(m['v369Units'])) {
          final um = asMap(u);
          if (um != null && um['isRepeat'] != true) rows.add(um);
        }
      }
    }
    return rows;
  }

  /// `v369ContiguousProgress`.
  static double contiguousProgress(Object? start, List<Map<String, dynamic>> units, String? seasonId, Object? limit) {
    final current = math.max(0, jsNum(start).floor());
    final relevant = <int>{};
    for (final u in units) {
      if (jsStr(u['seasonId']) != (seasonId ?? '') || u['isRepeat'] == true) continue;
      final n = jsNum(u['number']).floor();
      if (n > current) relevant.add(n);
    }
    final lim = jsNum(limit);
    final max = lim > 0 ? math.max(current, lim.floor()) : 9007199254740991;
    var end = current;
    while (end < max && relevant.contains(end + 1)) {
      end++;
    }
    return end.toDouble();
  }

  /// `v369ProjectedTitleProgress`.
  double projectedProgress(Map<String, dynamic> i, Map<String, dynamic> e) {
    final start = math.max(0.0, jsNum(i['progress']));
    if (e['isRepeat'] == true) return start;
    final all = [...knownUnits(i), ...units(e)];
    final seasons = seasonsOf(i);
    if (seasons.isEmpty) return contiguousProgress(start, all, null, i['total']);
    return seasons.fold<double>(0, (t, s) => t + contiguousProgress(s['progress'], all, jsStr(s['id']), s['total']));
  }

  Map<String, dynamic>? selectedSeason(Map<String, dynamic> e, Map<String, dynamic>? i) {
    final seasons = seasonsOf(i);
    if (seasons.isEmpty) return null;
    return seasons.where((s) => jsStr(s['id']) == jsStr(e['v369SelectedSeasonId'])).firstOrNull ?? seasons.first;
  }

  /// `v369NextNumber`.
  int nextNumber(Map<String, dynamic> e, Map<String, dynamic>? i) {
    final season = selectedSeason(e, i);
    final relevant = units(e).where((u) => jsStr(u['seasonId']) == jsStr(season?['id'])).toList();
    final last = relevant.isEmpty ? 0 : jsNum(relevant.last['number']).toInt();
    final base = season != null ? jsNum(season['progress']).toInt() : jsNum(i?['progress']).toInt();
    return [1, last + 1, base + 1].reduce(math.max);
  }

  /// `v394RuntimeForEntry`.
  double runtimeSeconds(Map<String, dynamic> e) {
    final actual = units(e).fold<double>(0, (n, u) => n + unitSeconds(u));
    if (e['v394RuntimeManual'] == true && units(e).isNotEmpty) {
      final total = jsNumFromKey(e, 'v394RuntimeSeconds');
      if (total != null && total >= 0) return jsRound(total);
    }
    return actual;
  }

  /// `v369Sync`.
  void sync369() {
    for (final e in entries) {
      if (e['v369Units'] is! List) continue;
      e['qty'] = asList(e['v369Units']).length;
      final i = item(e['libraryId']);
      e['v179EndProgress'] = jsOut(i != null ? projectedProgress(i, e) : math.max(0.0, jsNum(e['v179StartProgress'])) + jsNum(e['qty']));
    }
    syncSingle();
    final seconds = itemized
        ? entries.fold<double>(0, (n, e) => n + runtimeSeconds(e))
        : entries.fold<double>(0, (n, e) => n + units(e).fold<double>(0, (t, u) => t + unitSeconds(u)));
    logDraft['v369DurationSeconds'] = jsOut(seconds);
    logDraft['minutes'] = jsOut(seconds / 60);
  }

  List<dynamic> _unitList(Map<String, dynamic> e) {
    final list = e['v369Units'];
    if (list is List<dynamic>) return list;
    final created = <dynamic>[...asList(list)];
    e['v369Units'] = created;
    return created;
  }

  /// `v369AddUnit`: the next episode/chapter, stamped now.
  String? addUnit(int index, {bool forceRepeat = false}) {
    final e = entry(index), i = item(e?['libraryId']);
    if (e == null || i == null) return null;
    final season = selectedSeason(e, i);
    final storedNext = jsNum(e['v369NextNumber']).floor();
    final number = storedNext != 0 ? storedNext : nextNumber(e, i);
    if (number < 1 || number > 999999 || (season != null && jsNum(season['total']) > 0 && number > jsNum(season['total']))) {
      return 'Enter a valid episode/chapter/issue number for this title.';
    }
    final list = _unitList(e);
    final saved = math.max(0.0, jsNum(season != null ? season['progress'] : i['progress']));
    if (!forceRepeat && e['isRepeat'] != true && number <= saved) {
      return 'That unit is already within saved progress.';
    }
    if (!forceRepeat && units(e).any((x) => jsStr(x['seasonId']) == jsStr(season?['id']) && jsNum(x['number']) == number)) {
      return 'That unit is already in this draft.';
    }
    final now = clock();
    list.add(<String, dynamic>{
      'id': uid(),
      'number': number,
      'seasonId': season != null ? jsStr(season['id']) : null,
      'seasonName': season != null ? jsStr(season['name']) : null,
      'seasonNumber': season?['number'],
      'loggedAt': now,
      'durationSeconds': jsOut(defaultSeconds(i)),
      'v369UpdatedAt': now,
      'isRepeat': forceRepeat || e['isRepeat'] == true,
    });
    e['v369UpdatedAt'] = now;
    e['v369NextNumber'] = number + 1;
    sync369();
    return null;
  }

  /// `v369RemoveUnit`.
  void removeUnit(int index, int pos) {
    final e = entry(index);
    if (e == null) return;
    final list = _unitList(e);
    if (pos < 0 || pos >= list.length) return;
    final deleted = asMap(list[pos]);
    final tomb = asMap(e['v369DeletedUnits']) ?? <String, dynamic>{};
    e['v369DeletedUnits'] = {...tomb, jsStr(deleted?['id']): clock()};
    list.removeAt(pos);
    e['v369UpdatedAt'] = clock();
    sync369();
  }

  /// `App.v369EditUnit`: key is duration-0/1/2 (h/m/s), minutes, number,
  /// season or time (milliseconds).
  String? editUnit(int index, int pos, String key, Object? value) {
    final e = entry(index);
    final list = e == null ? const [] : _unitList(e);
    if (e == null || pos < 0 || pos >= list.length) return null;
    final u = asMap(list[pos])!;
    if (key.startsWith('duration-') || key == 'minutes') e['v394RuntimeManual'] = false;
    final now = clock();
    if (RegExp(r'^duration-[012]$').hasMatch(key)) {
      final which = int.parse(key.substring(key.length - 1));
      final t = unitSeconds(u).toInt();
      final parts = [t ~/ 3600, t % 3600 ~/ 60, t % 60];
      final v = jsNum(value).floor();
      parts[which] = v.clamp(0, which == 0 ? 9999 : 59).toInt();
      u['durationSeconds'] = parts[0] * 3600 + parts[1] * 60 + parts[2];
      u.remove('minutes');
      sync369();
    }
    if (key == 'minutes') {
      u['durationSeconds'] = math.max(0, jsRound(jsNum(value) * 60).toInt());
      u.remove('minutes');
      sync369();
    }
    if (key == 'number' || key == 'season') {
      final i = item(e['libraryId']);
      if (i == null) return null;
      final seasons = seasonsOf(i);
      final season = key == 'season'
          ? seasons.where((x) => jsStr(x['id']) == jsStr(value)).firstOrNull
          : seasons.where((x) => jsStr(x['id']) == jsStr(u['seasonId'])).firstOrNull;
      final number = key == 'number' ? jsNum(value).floor() : jsNum(u['number']).toInt();
      final saved = math.max(0.0, jsNum(season != null ? season['progress'] : i['progress']));
      if ((seasons.isNotEmpty && season == null) || !(number > 0 && number <= 999999) ||
          (season != null && jsNum(season['total']) > 0 && number > jsNum(season['total'])) ||
          (e['isRepeat'] != true && number <= saved) ||
          units(e).any((x) => !identical(x, u) && jsNum(x['number']) == number && jsStr(x['seasonId']) == jsStr(season?['id']))) {
        return 'Invalid unit number, saved progress, season, or duplicate entry.';
      }
      u['number'] = number;
      u['seasonId'] = season != null ? jsStr(season['id']) : null;
      u['seasonName'] = season != null ? jsStr(season['name']) : null;
      u['seasonNumber'] = season?['number'];
      e.remove('v369NextNumber');
      sync369();
    }
    if (key == 'time') {
      final time = jsNum(value);
      if (!validStamp(time, now)) return 'Choose a valid past date/time.';
      u['loggedAt'] = jsOut(time);
    }
    if (key == 'time' || key == 'number' || key == 'season' || key.startsWith('duration-') || key == 'minutes') {
      u['v369UpdatedAt'] = now;
      e['v369UpdatedAt'] = now;
    }
    return null;
  }

  static bool validStamp(double n, int now) => n.isFinite && n >= 946684800000 && n <= now + 300000;

  /// `v369ToggleUnitRepeat`.
  String? toggleUnitRepeat(int index, int pos) {
    final e = entry(index), i = item(e?['libraryId']);
    final list = e == null ? const [] : _unitList(e);
    if (e == null || i == null || pos < 0 || pos >= list.length) return null;
    final u = asMap(list[pos])!;
    final repeat = u['isRepeat'] != true;
    final season = seasonsOf(i).where((s) => jsStr(s['id']) == jsStr(u['seasonId'])).firstOrNull;
    if (!repeat && e['isRepeat'] != true && jsNum(u['number']) <= jsNum(season != null ? season['progress'] : i['progress'])) {
      return 'Already saved progress must remain marked as repeat consumption.';
    }
    final now = clock();
    u['isRepeat'] = repeat;
    u['v369UpdatedAt'] = now;
    e['v369UpdatedAt'] = now;
    sync369();
    return null;
  }

  /// `v369SelectSeason` / `v394ChooseSeason`.
  void selectSeason(int index, String id) {
    final e = entry(index), i = item(e?['libraryId']);
    if (e == null || i == null || !seasonsOf(i).any((s) => jsStr(s['id']) == id)) return;
    e['v369SelectedSeasonId'] = id;
    e.remove('v369NextNumber');
  }

  // ---- v394 Progress Reached / Amount Consumed ------------------------------------

  /// 'unit' | 'last' | 'amount'.
  static String method(Map<String, dynamic>? e) {
    final m = e?['v394Method'];
    return m == 'last' || m == 'amount' ? m as String : 'unit';
  }

  void setMethod(int index, String value) {
    final e = entry(index);
    if (e == null || !const ['unit', 'last', 'amount'].contains(value)) return;
    e['v394Method'] = value;
    e['v369UpdatedAt'] = clock();
  }

  ({Map<String, dynamic>? season, List<Map<String, dynamic>> units}) relevant(Map<String, dynamic> e, Map<String, dynamic>? i) {
    final season = selectedSeason(e, i);
    return (season: season, units: units(e).where((u) => jsStr(u['seasonId']) == jsStr(season?['id'])).toList());
  }

  /// `v394Base`: saved progress the bulk methods start from.
  static int bulkBase(Map<String, dynamic> e, Map<String, dynamic> i, Map<String, dynamic>? season) =>
      e['isRepeat'] == true ? 0 : math.max(0, jsNum(season != null ? season['progress'] : i['progress']).floor());

  static bool exactContiguous(List<Map<String, dynamic>> units, int base) {
    final sorted = units.map((u) => jsNum(u['number']).floor()).toList()..sort();
    for (var k = 0; k < sorted.length; k++) {
      if (sorted[k] != base + k + 1) return false;
    }
    return true;
  }

  /// `v400BulkStamp`.
  int bulkStamp(Map<String, dynamic> e, String m) {
    final now = clock();
    for (final key in [m == 'last' ? 'v400LastWhen' : 'v400AmountWhen', 'v394When', 'loggedAt']) {
      final v = jsNum(e[key]);
      if (validStamp(v, now)) return v.toInt();
    }
    return now;
  }

  /// Whether [setQuantity] would replace detailed per-unit entries (the website
  /// asks for confirmation first).
  bool quantityReplacesDetail(int index) {
    final e = entry(index), i = item(e?['libraryId']);
    if (e == null || i == null) return false;
    final r = relevant(e, i);
    final base = bulkBase(e, i, r.season);
    final inconsistent = r.units.isNotEmpty && !exactContiguous(r.units, base);
    final times = r.units.map((u) => jsNum(u['loggedAt'])).toSet().length > 1;
    final durations = r.units.map(unitSeconds).toSet().length > 1;
    final repeatMix = r.units.any((u) => (u['isRepeat'] == true) != (e['isRepeat'] == true));
    return inconsistent || times || durations || repeatMix;
  }

  /// `App.v394SetQuantity`: "Progress Reached" (last) or "Amount Consumed".
  String? setQuantity(int index, Object? value) {
    final e = entry(index), i = item(e?['libraryId']);
    if (e == null || i == null) return null;
    final m = method(e);
    if (m == 'unit') return null;
    final r = relevant(e, i);
    final base = bulkBase(e, i, r.season);
    final v = jsNumOrNull(value);
    if (v == null || v != v.truncateToDouble() || v < 0 || v > 9007199254740991) return 'Enter a valid whole unit number.';
    final quantity = m == 'last' ? v.toInt() - base : v.toInt();
    final limit = math.max(0, jsNum(r.season != null ? r.season!['total'] : i['total']).floor());
    if (quantity < 0 || quantity > 2000 || (limit > 0 && base + quantity > limit)) {
      return 'The amount is outside saved progress, title total, or the 2,000-unit safe limit.';
    }
    if (quantity == r.units.length && exactContiguous(r.units, base)) return null;
    final repeatMix = r.units.any((u) => (u['isRepeat'] == true) != (e['isRepeat'] == true));
    final previous = {for (final u in r.units) jsNum(u['number']).toInt(): u};
    final now = clock(), stamp = bulkStamp(e, m), seconds = defaultSeconds(i);
    final result = <Map<String, dynamic>>[];
    for (var k = 1; k <= quantity; k++) {
      final number = base + k;
      final old = previous[number];
      if (old != null && !repeatMix) {
        result.add(old);
        continue;
      }
      result.add(<String, dynamic>{
        'id': uid(),
        'number': number,
        'seasonId': r.season != null ? jsStr(r.season!['id']) : null,
        'seasonName': r.season != null ? jsStr(r.season!['name']) : null,
        'seasonNumber': r.season?['number'],
        'loggedAt': stamp,
        'durationSeconds': jsOut(seconds),
        'v369UpdatedAt': now,
        'isRepeat': e['isRepeat'] == true,
      });
    }
    final removed = r.units.where((u) => !result.any((x) => identical(x, u))).toList();
    if (removed.isNotEmpty) {
      final tomb = Map<String, dynamic>.from(asMap(e['v369DeletedUnits']) ?? const {});
      for (final u in removed) {
        tomb[jsStr(u['id'])] = now;
      }
      e['v369DeletedUnits'] = tomb;
    }
    e['v369Units'] = <dynamic>[
      ...units(e).where((u) => jsStr(u['seasonId']) != jsStr(r.season?['id'])),
      ...result,
    ];
    e['v369UpdatedAt'] = now;
    e.remove('v369NextNumber');
    sync369();
    return null;
  }

  /// `App.v394SetWhen`: the date/time for Progress Reached / Amount Consumed.
  String? setWhen(int index, int stamp) {
    final e = entry(index);
    if (e == null) return null;
    if (!validStamp(stamp.toDouble(), clock())) return 'Choose a valid past date and time.';
    final m = method(e);
    if (m == 'unit') return null;
    e[m == 'last' ? 'v400LastWhen' : 'v400AmountWhen'] = stamp;
    e['v369UpdatedAt'] = clock();
    return null;
  }

  /// `App.v394ToggleRuntime`.
  String? toggleRuntime(int index, bool enabled) {
    final e = entry(index);
    if (e == null) return null;
    if (enabled && units(e).isEmpty) return 'Add consumed units before customizing their total runtime.';
    if (enabled && e['v394RuntimeManual'] != true) {
      e['v394RuntimeSeconds'] = jsOut(units(e).fold<double>(0, (n, u) => n + unitSeconds(u)));
    }
    e['v394RuntimeManual'] = enabled;
    e['v369UpdatedAt'] = clock();
    sync369();
    return null;
  }

  /// `App.v394SetRuntime` (seconds).
  void setRuntime(int index, int seconds) {
    final e = entry(index);
    if (e == null || seconds < 0 || seconds > 359999999) return;
    e['v394RuntimeSeconds'] = seconds;
    e['v394RuntimeManual'] = true;
    e['v369UpdatedAt'] = clock();
    sync369();
  }

  // ---- submit validation (the website's submit guards) ---------------------------

  /// Returns why the draft can't be submitted yet, or null.
  String? validate() {
    if (itemized) {
      final all = entries;
      if (all.isEmpty || all.any((e) => units(e).isEmpty)) return 'Log at least one unit for every selected title before saving.';
      final now = clock();
      for (final e in all) {
        if (item(e['libraryId']) == null) return 'A selected Library title is missing.';
        if (units(e).any((u) => !validStamp(jsNum(u['loggedAt']), now) || !(jsNum(u['number']) > 0))) {
          return 'Correct invalid unit timestamps or numbers before saving.';
        }
      }
      for (final e in all) {
        final valid = seasonsOf(item(e['libraryId'])).map((s) => jsStr(s['id'])).toSet();
        if (units(e).any((u) => valid.isNotEmpty ? !valid.contains(jsStr(u['seasonId'])) : jsTruthy(u['seasonId']))) {
          return 'A logged season no longer matches the Library title. Restore its season before saving.';
        }
      }
      final commit = jsStr(logDraft['v369CommitId']);
      if (commit.isNotEmpty &&
          asList(state['sessions']).any((s) {
            final m = asMap(s);
            return m != null &&
                jsStr(m['sessionGroupId'] ?? m['v369CommitId']) == commit &&
                (jsTruthy(m['v369Itemized']) || jsTruthy(m['v369CommitId']));
          })) {
        return 'This per-unit session was already saved.';
      }
      return null;
    }
    if (entries.any((e) => jsNum(e['qty']) <= 0)) {
      return 'Enter consumption for added titles, or remove empty titles before submitting.';
    }
    if (mode == 'progress') {
      if (entries.isEmpty) return 'Select at least one Library title and enter its final progress.';
      for (final e in entries) {
        final i = item(e['libraryId']);
        if (i == null) {
          if (!(jsNum(e['qty']) > 0)) return 'One of the progress entries has no consumed amount.';
          continue;
        }
        final s = jsNumFromKey(e, 'v179StartProgress');
        final start = s != null && s.isFinite ? math.max(0.0, s) : startProgress(i);
        if (!(calculatedQty(i, start, e['v179EndProgress']) > 0)) {
          return '${cleanTitle(i['title'])}: final progress must be higher than ${_fmt(start)}.';
        }
      }
      return null;
    }
    if (entries.isEmpty && !(jsNum(logDraft['amount']) > 0)) return 'Add a title or enter an amount.';
    return null;
  }

  String _progressLabel(Map<String, dynamic> i) {
    final unit = jsStr(category(jsStr(i['categoryId']))['unit']);
    const singular = {
      'episodes': 'Episode', 'chapters': 'Chapter', 'issues': 'Issue', 'movies': 'Movie', 'pages': 'Page',
      'volumes': 'Volume', 'videos': 'Video', 'sessions': 'Session', 'tracks': 'Track', 'albums': 'Album',
      'levels': 'Level', 'missions': 'Mission', 'matches': 'Match', 'lessons': 'Lesson', 'items': 'Item',
    };
    return '${singular[unit] ?? 'Unit'} reached';
  }

  static String _fmt(double v) => v == v.truncateToDouble() ? v.toInt().toString() : v.toString();
}
