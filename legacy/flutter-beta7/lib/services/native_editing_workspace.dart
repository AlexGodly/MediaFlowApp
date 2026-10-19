import 'package:flutter/foundation.dart';

import '../data/mediaflow_models.dart';
import 'native_logging_parity_preview.dart';
import 'native_itemized_parity.dart';

/// M20 account-scoped, RAM-only edit sketches. These are deliberately NOT the
/// M19 cloud pending-review protocol and never become Supabase state_data.
/// Editing an offline/cached projection cannot produce an uploadable operation.
class NativeEditingWorkspace extends ChangeNotifier {
  NativeEditingWorkspace({required this.ownerId}) {
    if (ownerId.isEmpty) throw StateError('Authenticated owner required');
  }

  final String ownerId;
  MediaFlowCatalog? _base;
  bool _stale = false;
  final Map<String, NativeTitleIntent> _titles = {};
  final Map<String, NativeLogIntent> _logs = {};
  final Map<String, NativeItemizedPreview> _itemized = {};

  bool get stale => _stale;
  /// Identity-only source for safe, *manual* authenticated cloud review.
  MediaFlowCatalog? get baseCatalog => _base;
  int get titleCount => _titles.length;
  int get logCount => _logs.length + _itemized.length;
  int get itemizedCount => _itemized.length;
  bool get hasDrafts => _titles.isNotEmpty || _logs.isNotEmpty ||
      _itemized.isNotEmpty;
  int get pendingHistoryEntries => _logs.length + _itemized.length;
  double get xpAwarded => 0; // No History or XP mutations before parity.
  List<NativeTitleIntent> get titleDrafts =>
      List.unmodifiable(_titles.values);
  List<NativeLogIntent> get logDrafts =>
      List.unmodifiable(_logs.values);
  List<NativeItemizedPreview> get itemizedDrafts =>
      List.unmodifiable(_itemized.values);

  /// A new cloud/cached catalog invalidates old sketches rather than silently
  /// rebasing edits across revisions. User can inspect then discard manually.
  void observe(MediaFlowCatalog catalog) {
    if (identical(_base, catalog)) return;
    if (hasDrafts) {
      _stale = true;
    } else {
      _base = catalog;
      _stale = false;
    }
    notifyListeners();
  }

  void _requireFresh(MediaFlowCatalog catalog) {
    if (_stale || !identical(_base, catalog)) {
      throw StateError('Library snapshot changed; discard stale drafts first.');
    }
  }

  MediaFlowTitle _find(MediaFlowCatalog catalog, String id) {
    if (id.isEmpty) throw const FormatException('Title ID required');
    final matches = catalog.library.where((title) => title.id == id);
    if (matches.length != 1) {
      throw StateError('Missing or duplicate Library title');
    }
    return matches.single;
  }

  NativeTitleIntent? titleDraft(String id) => _titles[id];
  NativeLogIntent? logDraft(String id) => _logs[id];
  NativeItemizedPreview? itemizedDraft(String id) => _itemized[id];

  void stageTitle({
    required MediaFlowCatalog catalog,
    required String titleId,
    required String priority,
    required String status,
    required double progress,
    required double? rating,
  }) {
    _requireFresh(catalog);
    final original = _find(catalog, titleId);
    if (!const {'low', 'medium', 'high'}.contains(priority) ||
        !const {'active', 'planned', 'completed', 'paused', 'dropped'}
            .contains(status)) {
      throw const FormatException('Invalid status or priority');
    }
    if (!progress.isFinite || progress < 0 ||
        (original.total != null && progress > original.total!) ||
        (rating != null && (!rating.isFinite || rating < 0 || rating > 10))) {
      throw const FormatException('Progress or rating is out of range');
    }
    // The website's seasons feature owns aggregate progress; do not claim
    // parity by editing the aggregate while seasons are configured.
    if (original.seasons.isNotEmpty && progress != original.progress) {
      throw const FormatException(
        'Season-based progress requires per-season editing parity',
      );
    }
    if (_itemized.containsKey(titleId)) {
      throw const FormatException(
        'Discard itemized draft before editing this title',
      );
    }
    final existingLog = _logs[titleId];
    if (existingLog != null &&
        existingLog.startingProgress != progress) {
      throw const FormatException(
        'Discard logging draft before changing title progress',
      );
    }
    if (priority == original.priority && status == original.status &&
        progress == original.progress && rating == original.rating) {
      _titles.remove(titleId);
    } else {
      _titles[titleId] = NativeTitleIntent(
        titleId: titleId,
        title: original.title,
        priority: priority,
        status: status,
        progress: progress,
        rating: rating,
        statusSideEffectsUnverified: status != original.status ||
            progress != original.progress,
      );
    }
    notifyListeners();
  }

  void stageLog({
    required MediaFlowCatalog catalog,
    required String titleId,
    required double amount,
    required double minutes,
    required String note,
    NativeLogInputMode mode = NativeLogInputMode.amount,
    bool repeat = false,
    DateTime? date,
  }) {
    _requireFresh(catalog);
    final original = _find(catalog, titleId);
    if (_itemized.containsKey(titleId)) {
      throw const FormatException('Discard itemized draft first');
    }
    if (note.length > 2000) {
      throw const FormatException('Log note exceeds 2,000 characters');
    }
    final effectiveProgress = _titles[titleId]?.progress ?? original.progress;
    // No mutation of the typed cloud catalog; if a title sketch changes
    // progress, create an isolated view just for the hypothetical calculation.
    final previewTitle = MediaFlowTitle.fromJson({
      'id': original.id,
      'title': original.title,
      'categoryId': original.categoryId,
      'status': _titles[titleId]?.status ?? original.status,
      'priority': original.priority,
      'progress': effectiveProgress,
      'total': original.total,
      'rating': original.rating,
      'seasons': [
        for (final season in original.seasons)
          {'name': season.name, 'progress': season.progress,
           'total': season.total},
      ],
    });
    final projection = NativeLoggingParityPreview.calculate(
      title: previewTitle,
      existingSessions: catalog.sessions,
      mode: mode,
      value: amount,
      minutes: minutes,
      note: note,
      repeat: repeat,
      date: date,
    );
    if (!projection.repeat && original.total != null &&
        projection.projectedLibraryProgress > original.total!) {
      throw const FormatException('Draft exceeds title total');
    }
    // Keep the existing conservative M20 behavior for amount-overflow:
    // not silently dropping consumed units on a nonrepeat Library draft.
    if (mode == NativeLogInputMode.amount && !projection.repeat &&
        original.total != null &&
        effectiveProgress + projection.consumed > original.total!) {
      throw const FormatException('Draft would exceed title total');
    }
    _logs[titleId] = NativeLogIntent(
      titleId: titleId,
      title: original.title,
      categoryId: original.categoryId,
      units: projection.consumed,
      minutes: minutes,
      note: note.trim(),
      startingProgress: effectiveProgress,
      projectedProgress: projection.projectedLibraryProgress,
      mode: mode,
      repeat: repeat,
      wouldComplete: projection.wouldComplete,
      projectedStatus: projection.projectedStatus,
      prospectiveStreak: projection.prospectiveStreak,
      indicativeStreakMultiplier: projection.streakMultiplier,
      hypotheticalDate: projection.historyProjection.date,
    );
    notifyListeners();
  }

  void stageItemizedLog({
    required MediaFlowCatalog catalog,
    required String titleId,
    required String seasonId,
    required List<int> numbers,
    required int secondsPerUnit,
    bool repeat = false,
  }) {
    _requireFresh(catalog);
    if (_logs.containsKey(titleId) || _titles.containsKey(titleId)) {
      throw const FormatException(
        'Discard title/standard logging drafts before itemized logging',
      );
    }
    final original = _find(catalog, titleId);
    final preview = NativeItemizedParity.calculate(
      title: original, sessions: catalog.sessions, seasonId: seasonId,
      numbers: numbers, secondsPerUnit: secondsPerUnit, repeat: repeat,
    );
    _itemized[titleId] = preview;
    notifyListeners();
  }

  void discardItemizedLog(String id) {
    if (_itemized.remove(id) != null) notifyListeners();
  }

  void discardTitle(String id) {
    if (_titles.remove(id) != null) {
      if (_logs.containsKey(id)) _logs.remove(id);
      notifyListeners();
    }
  }

  void discardLog(String id) {
    if (_logs.remove(id) != null) notifyListeners();
  }

  void discardAll() {
    _titles.clear();
    _logs.clear();
    _itemized.clear();
    _base = null;
    _stale = false;
    notifyListeners();
  }
}

@immutable
class NativeTitleIntent {
  const NativeTitleIntent({
    required this.titleId,
    required this.title,
    required this.priority,
    required this.status,
    required this.progress,
    required this.rating,
    required this.statusSideEffectsUnverified,
  });

  final String titleId, title, priority, status;
  final double progress;
  final double? rating;
  final bool statusSideEffectsUnverified;
}

@immutable
class NativeLogIntent {
  const NativeLogIntent({
    required this.titleId,
    required this.title,
    required this.categoryId,
    required this.units,
    required this.minutes,
    required this.note,
    required this.startingProgress,
    required this.projectedProgress,
    this.mode = NativeLogInputMode.amount,
    this.repeat = false,
    this.wouldComplete = false,
    this.projectedStatus = '',
    this.prospectiveStreak = 1,
    this.indicativeStreakMultiplier = 1,
    this.hypotheticalDate = '',
  });

  final String titleId, title, categoryId, note, projectedStatus, hypotheticalDate;
  final double units, minutes, startingProgress, projectedProgress;
  final NativeLogInputMode mode;
  final bool repeat, wouldComplete;
  final int prospectiveStreak;
  final double indicativeStreakMultiplier;
  double? get hypotheticalXp => null;
}
