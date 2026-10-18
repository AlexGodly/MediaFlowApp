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

  int startFor(MediaFlowTitle title) {
    if (seasonId.isEmpty) return title.progress.floor().clamp(0, 100000000);
    for (var i = 0; i < title.seasons.length; i++) {
      final season = title.seasons[i];
      final key = season.id.isNotEmpty ? season.id : 'season_$i';
      if (key == seasonId) return season.progress.floor().clamp(0, 100000000);
    }
    return title.progress.floor().clamp(0, 100000000);
  }

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
    return remaining.clamp(0, 2000);
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
  }

  void setLastUnit(MediaFlowTitle title, int last) {
    setAmount(title, last - startFor(title));
  }

  void toggleUnit(MediaFlowTitle title, int number, {DateTime? at}) {
    final first = startFor(title) + 1;
    if (number < first || number > first + allowedQuantity(title) - 1) return;
    if (currentUnits.containsKey(number)) {
      currentUnits.remove(number);
    } else {
      currentUnits[number] = at ?? DateTime.now();
    }
  }

  void setUnitTime(int number, DateTime timestamp) {
    if (currentUnits.containsKey(number)) currentUnits[number] = timestamp;
  }

  int previewProgress(MediaFlowTitle title) =>
      title.progress.floor() + (isRepeat ? 0 : quantity);

  Map<String, Object?> toLocalReview() => {
    'titleId': titleId,
    'method': method.name,
    'seasonId': seasonId,
    'repeat': isRepeat,
    'whenWatched': whenWatched.toIso8601String(),
    'runtimeMinutes': runtimeMinutes,
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
    _entries[title.id] = R2DraftTitle(title.id);
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

  void setKeepTitles(bool value) {
    keepTitles = value;
    notifyListeners();
  }

  /// Exportable preview only; never passed to Supabase or History writers.
  List<Map<String, Object?>> review() =>
      entries.map((entry) => entry.toLocalReview()).toList(growable: false);
}
