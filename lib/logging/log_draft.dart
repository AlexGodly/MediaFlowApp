import 'dart:collection';
import 'package:flutter/foundation.dart';
import '../cloud/mediaflow_cloud.dart';

enum LoggingMethod { perUnit, lastUnit, amount }

class TitleLogDraft {
  TitleLogDraft(this.title);
  final CloudTitle title;
  LoggingMethod method = LoggingMethod.perUnit;
  String seasonId = '';
  bool repeat = false;
  DateTime consumedAt = DateTime.now();
  String note = '';
  final Map<String, SplayTreeMap<int, DateTime>> _units = {};

  String get key => seasonId.isEmpty ? '_title' : seasonId;
  SplayTreeMap<int, DateTime> get selected =>
      _units.putIfAbsent(key, SplayTreeMap<int, DateTime>.new);

  CloudSeason? get season {
    for (final candidate in title.seasons) {
      if (candidate.id == seasonId) return candidate;
    }
    return null;
  }

  int get base => repeat ? 0 : (season?.progress ?? title.progress);
  int? get total => season?.total ?? title.total;
  int get maximum {
    final limit = total;
    if (limit == null || limit <= 0) return 2000;
    return (limit - base).clamp(0, 2000).toInt();
  }
  int get quantity => _units.values.fold<int>(0,
      (sum, item) => sum + item.length);
  int get selectedQuantity => selected.length;

  void toggle(int number) {
    if (number <= base || number > base + maximum) return;
    if (selected.containsKey(number)) {
      selected.remove(number);
    } else {
      selected[number] = DateTime.now();
    }
  }

  void setQuantity(int amount) {
    final capped = amount.clamp(0, maximum).toInt();
    final previous = Map<int, DateTime>.from(selected);
    final replacement = SplayTreeMap<int, DateTime>();
    for (var i = 1; i <= capped; i++) {
      final number = base + i;
      replacement[number] = previous[number] ?? consumedAt;
    }
    _units[key] = replacement;
  }

  void setLast(int last) => setQuantity(last - base);

  int get projectedProgress {
    if (repeat) return title.progress;
    int contiguous(int progress, Iterable<int> units) {
      final numbers = units.toSet();
      var next = progress;
      while (numbers.contains(next + 1)) { next++; }
      return next - progress;
    }
    if (title.seasons.isEmpty) {
      return title.progress + contiguous(title.progress,
          _units['_title']?.keys ?? const <int>[]);
    }
    final hasSpecific = title.seasons.any((part) =>
        _units[part.id]?.isNotEmpty == true);
    if (!hasSpecific) {
      return title.progress + contiguous(title.progress,
          _units['_title']?.keys ?? const <int>[]);
    }
    var sum = 0;
    for (final part in title.seasons) {
      sum += part.progress + contiguous(part.progress,
          _units[part.id]?.keys ?? const <int>[]);
    }
    return sum;
  }

  Map<String, Object?> review() => {
    'libraryId': title.id,
    'title': title.title,
    'method': method.name,
    'isRepeat': repeat,
    'timestamp': consumedAt.toIso8601String(),
    'note': note,
    'quantity': quantity,
    'projectedProgress': projectedProgress,
    'seasons': {
      for (final part in _units.entries) part.key: {
        for (final unit in part.value.entries)
          unit.key.toString(): unit.value.toIso8601String(),
      },
    },
  };
}

class LoggingDraftController extends ChangeNotifier {
  final LinkedHashMap<String, TitleLogDraft> _drafts = LinkedHashMap();
  List<TitleLogDraft> get titles => List.unmodifiable(_drafts.values);
  int get length => _drafts.length;
  int get units => _drafts.values.fold<int>(
      0, (sum, draft) => sum + draft.quantity);
  bool includes(String id) => _drafts.containsKey(id);

  void add(CloudTitle title) {
    if (title.id.isEmpty || _drafts.containsKey(title.id)) return;
    _drafts[title.id] = TitleLogDraft(title);
    notifyListeners();
  }

  void edit(String id, void Function(TitleLogDraft) change) {
    final title = _drafts[id];
    if (title == null) return;
    change(title);
    notifyListeners();
  }

  void remove(String id) {
    if (_drafts.remove(id) != null) notifyListeners();
  }

  void clear() {
    _drafts.clear();
    notifyListeners();
  }
}
