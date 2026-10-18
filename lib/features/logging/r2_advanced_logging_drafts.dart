import 'dart:collection';
import 'package:flutter/foundation.dart';
import '../../data/mediaflow_models.dart';

/// A local, owner-session-only advanced logging plan. This is deliberately
/// NOT a MediaFlow History serializer and cannot upload account state.
enum R2LoggingMethod { perUnit, lastUnit, amount }

class R2DraftTitle {
  R2DraftTitle(this.titleId);
  final String titleId;
  R2LoggingMethod method = R2LoggingMethod.perUnit;
  String seasonId = '';
  bool isRepeat = false;
  DateTime whenWatched = DateTime.now();
  int runtimeMinutes = 24;
  String note = '';
  bool manualRuntime = false;
  int customTotalRuntimeSeconds = 0;
  final Map<String, Map<int, int>> _durations = {};
  final Map<String, SplayTreeMap<int, DateTime>> _seasonUnits = {};

  String get seasonKey => seasonId.isEmpty ? '_whole_title' : seasonId;

  SplayTreeMap<int, DateTime> get currentUnits =>
      _seasonUnits.putIfAbsent(seasonKey, SplayTreeMap<int, DateTime>.new);

  int get quantity => _seasonUnits.values.fold<int>(
    0, (sum, units) => sum + units.length,
  );

  int quantityForSeason(String key) => _seasonUnits[key]?.length ?? 0;

  List<int> get selectedNumbers => currentUnits.keys.toList(growable: false);

  /// Switching methods never discards per-unit numbers or timestamps.
  void chooseMethod(R2LoggingMethod value) => method = value;

  void chooseSeason(String id) => seasonId = id;

  int savedStartFor(MediaFlowTitle title) {
    if (seasonId.isEmpty) return title.progress.floor().clamp(0, 100000000).toInt();
    for (var i = 0; i < title.seasons.length; i++) {
      final season = title.seasons[i];
      final key = season.id.isNotEmpty ? season.id : 'season_$i';
      if (key == seasonId) return season.progress.floor().clamp(0, 100000000).toInt();
    }
    return title.progress.floor().clamp(0, 100000000).toInt();
  }

  int startFor(MediaFlowTitle title) =>
      isRepeat ? 0 : savedStartFor(title);

  int? totalFor(MediaFlowTitle title) {
    if (seasonId.isEmpty) {
      return title.total == null || title.total! <= 0
          ? null : title.total!.floor();
    }
    for (var i = 0; i < title.seasons.length; i++) {
      final season = title.seasons[i];
      final key = season.id.isNotEmpty ? season.id : 'season_$i';
      if (key == seasonId) {
        return season.total == null || season.total! <= 0
            ? null : season.total!.floor();
      }
    }
    return null;
  }

  int allowedQuantity(MediaFlowTitle title) {
    final cap = totalFor(title);
    final remaining = cap == null ? 2000 : cap - startFor(title);
    return remaining.clamp(0, 2000).toInt();
  }

  /// Keep timestamps for all surviving unit numbers (v400-style behavior).
  /// Only the active season is changed; other season selections survive.
  void setAmount(MediaFlowTitle title, int requested) {
    final start = startFor(title);
    final amount = requested.clamp(0, allowedQuantity(title));
    final existing = currentUnits;
    final replacement = SplayTreeMap<int, DateTime>();
    for (var i = 1; i <= amount; i++) {
      final number = start + i;
      replacement[number] = existing[number] ?? whenWatched;
    }
    _seasonUnits[seasonKey] = replacement;
    _durations[seasonKey]?.removeWhere((number, _) =>
        !replacement.containsKey(number));
  }

  void setLastUnit(MediaFlowTitle title, int last) {
    setAmount(title, last - startFor(title));
  }

  void toggleUnit(MediaFlowTitle title, int number, {DateTime? at}) {
    final first = startFor(title) + 1;
    if (number < first || number > first + allowedQuantity(title) - 1) return;
    if (currentUnits.containsKey(number)) {
      currentUnits.remove(number);
      _durations[seasonKey]?.remove(number);
    } else {
      currentUnits[number] = at ?? DateTime.now();
    }
  }

  void setUnitTime(int number, DateTime timestamp) {
    if (currentUnits.containsKey(number)) currentUnits[number] = timestamp;
  }

  /// Per-unit durations are attached to season+unit, not the selected method.
  int secondsForUnit(int number) =>
      _durations[seasonKey]?[number] ?? runtimeMinutes * 60;

  void setUnitSeconds(int number, int seconds) {
    if (!currentUnits.containsKey(number)) return;
    if (seconds < 0 || seconds > 86400 * 7) return;
    _durations.putIfAbsent(seasonKey, () => {})[number] = seconds;
  }

  int get automaticRuntimeSeconds {
    var sum = 0;
    for (final row in _seasonUnits.entries) {
      for (final number in row.value.keys) {
        sum += _durations[row.key]?[number] ?? runtimeMinutes * 60;
      }
    }
    return sum;
  }

  int get effectiveRuntimeSeconds =>
      manualRuntime ? customTotalRuntimeSeconds : automaticRuntimeSeconds;

  /// A sparse Per Unit selection counts as consumption but cannot magically
  /// advance progress over unwatched/unread gaps (MediaFlow v369 rule).
  int previewProgress(MediaFlowTitle title) {
    if (isRepeat) return title.progress.floor();
    int contiguous(int base, Iterable<int> numbers) {
      final selected = numbers.toSet();
      var end = base;
      while (selected.contains(end + 1)) { end++; }
      return end - base;
    }
    if (title.seasons.isEmpty) {
      return title.progress.floor() + contiguous(title.progress.floor(),
          _seasonUnits['_whole_title']?.keys ?? const <int>[]);
    }
    var sum = title.seasons.fold<int>(0, (result, season) =>
        result + season.progress.floor());
    var hasSeasonUnits = false;
    for (var i = 0; i < title.seasons.length; i++) {
      final season = title.seasons[i];
      final key = season.id.isNotEmpty ? season.id : 'season_$i';
      final units = _seasonUnits[key];
      if (units != null && units.isNotEmpty) hasSeasonUnits = true;
      sum += contiguous(season.progress.floor(), units?.keys ?? const <int>[]);
    }
    if (!hasSeasonUnits) {
      sum += contiguous(title.progress.floor(),
          _seasonUnits['_whole_title']?.keys ?? const <int>[]);
    }
    return sum;
  }

  bool willReplaceDetailedUnits(MediaFlowTitle title, int amount) {
    final numbers = currentUnits.keys.toList();
    final start = startFor(title);
    final contiguous = numbers.asMap().entries.every(
      (value) => value.value == start + value.key + 1);
    final times = currentUnits.values.toSet().length > 1;
    final runtimes = (_durations[seasonKey] ?? const <int, int>{}).isNotEmpty;
    return !contiguous || times || runtimes;
  }

  Map<String, Object?> toLocalReview() => {
    'titleId': titleId,
    'method': method.name,
    'seasonId': seasonId,
    'repeat': isRepeat,
    'whenWatched': whenWatched.toIso8601String(),
    'runtimeMinutes': runtimeMinutes,
    'manualRuntime': manualRuntime,
    'customTotalRuntimeSeconds': customTotalRuntimeSeconds,
    'effectiveRuntimeSeconds': effectiveRuntimeSeconds,
    'unitDurations': {
      for (final row in _durations.entries)
        row.key: {for (final unit in row.value.entries)
          unit.key.toString(): unit.value},
    },
    'note': note,
    'units': {
      for (final row in _seasonUnits.entries)
        row.key: {
          for (final stamp in row.value.entries)
            stamp.key.toString(): stamp.value.toIso8601String(),
        },
    },
  };
}

class R2AdvancedLoggingDrafts extends ChangeNotifier {
  final LinkedHashMap<String, R2DraftTitle> _entries = LinkedHashMap();
  bool keepTitles = true;

  List<R2DraftTitle> get entries => List.unmodifiable(_entries.values);
  int get titleCount => _entries.length;
  int get totalUnits => _entries.values.fold<int>(
    0, (sum, entry) => sum + entry.quantity,
  );

  bool contains(String id) => _entries.containsKey(id);
  R2DraftTitle? find(String id) => _entries[id];

  void add(MediaFlowTitle title) {
    if (title.id.isEmpty || _entries.containsKey(title.id)) return;
    final next = R2DraftTitle(title.id);
    if (title.seasons.isNotEmpty) {
      next.seasonId = title.seasons.first.id.isNotEmpty
          ? title.seasons.first.id : 'season_0';
    }
    _entries[title.id] = next;
    notifyListeners();
  }

  void remove(String id) {
    if (_entries.remove(id) != null) notifyListeners();
  }

  void clear() {
    if (_entries.isEmpty) return;
    _entries.clear();
    notifyListeners();
  }

  void update(String id, void Function(R2DraftTitle) edit) {
    final entry = _entries[id];
    if (entry == null) return;
    edit(entry);
    notifyListeners();
  }

  void sortBy(String criterion, Map<String, MediaFlowTitle> library,
      {bool descending = false}) {
    if (_entries.length < 2) return;
    final ordered = _entries.keys.toList();
    final originalPositions = <String, int>{
      for (var i = 0; i < ordered.length; i++) ordered[i]: i,
    };
    int priority(String value) =>
        const {'low': 0, 'medium': 1, 'high': 2}[value] ?? 1;
    int compare(String aid, String bid) {
      final a = library[aid], b = library[bid];
      if (a == null || b == null) return 0;
      final diff = switch (criterion) {
        'title' => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        'progress' => a.progress.compareTo(b.progress),
        'total' => (a.total ?? 0).compareTo(b.total ?? 0),
        'priority' => priority(a.priority).compareTo(priority(b.priority)),
        'added' => (a.addedAt ?? DateTime(1970))
            .compareTo(b.addedAt ?? DateTime(1970)),
        'logAdded' => (originalPositions[aid] ?? 0)
            .compareTo(originalPositions[bid] ?? 0),
        _ => 0,
      };
      return diff == 0 ? (originalPositions[aid] ?? 0)
          .compareTo(originalPositions[bid] ?? 0)
          : (descending ? -diff : diff);
    }
    ordered.sort(compare);
    final previous = Map<String, R2DraftTitle>.from(_entries);
    _entries
      ..clear()
      ..addEntries(ordered.map((id) => MapEntry(id, previous[id]!)));
    notifyListeners();
  }

  void move(String id, int shift) {
    final ids = _entries.keys.toList();
    final from = ids.indexOf(id), to = from + shift;
    if (from < 0 || to < 0 || to >= ids.length) return;
    ids.removeAt(from);
    ids.insert(to, id);
    final previous = Map<String, R2DraftTitle>.from(_entries);
    _entries
      ..clear()
      ..addEntries(ids.map((key) => MapEntry(key, previous[key]!)));
    notifyListeners();
  }

  void setNote(String id, String value) {
    final entry = _entries[id];
    if (entry != null) entry.note = value;
  }

  void setKeepTitles(bool value) {
    keepTitles = value;
    notifyListeners();
  }

  /// Exportable preview only; never passed to Supabase or History writers.
  List<Map<String, Object?>> review() =>
      entries.map((entry) => entry.toLocalReview()).toList(growable: false);
}
