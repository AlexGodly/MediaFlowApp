import 'package:flutter/foundation.dart';

import '../data/mediaflow_models.dart';

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

  bool get stale => _stale;
  int get titleCount => _titles.length;
  int get logCount => _logs.length;
  bool get hasDrafts => _titles.isNotEmpty || _logs.isNotEmpty;
  int get pendingHistoryEntries => _logs.length;
  double get xpAwarded => 0; // No History or XP mutations before parity.
  List<NativeTitleIntent> get titleDrafts =>
      List.unmodifiable(_titles.values);
  List<NativeLogIntent> get logDrafts =>
      List.unmodifiable(_logs.values);

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
  }) {
    _requireFresh(catalog);
    final original = _find(catalog, titleId);
    if (!amount.isFinite || amount <= 0 || amount > 100000 ||
        !minutes.isFinite || minutes < 0 || minutes > 100000) {
      throw const FormatException('Invalid units or runtime');
    }
    if (note.length > 2000) {
      throw const FormatException('Log note exceeds 2,000 characters');
    }
    // Preview must not invent a per-season logging conversion.
    if (original.seasons.isNotEmpty) {
      throw const FormatException(
        'Per-season logging requires website-compatible conversion',
      );
    }
    final effectiveProgress = _titles[titleId]?.progress ?? original.progress;
    if (original.total != null &&
        effectiveProgress + amount > original.total!) {
      throw const FormatException('Draft would exceed title total');
    }
    _logs[titleId] = NativeLogIntent(
      titleId: titleId,
      title: original.title,
      categoryId: original.categoryId,
      units: amount,
      minutes: minutes,
      note: note.trim(),
      startingProgress: effectiveProgress,
      projectedProgress: effectiveProgress + amount,
    );
    notifyListeners();
  }

  void discardTitle(String id) {
    if (_titles.remove(id) != null) notifyListeners();
  }

  void discardLog(String id) {
    if (_logs.remove(id) != null) notifyListeners();
  }

  void discardAll() {
    _titles.clear();
    _logs.clear();
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
  });

  final String titleId, title, categoryId, note;
  final double units, minutes, startingProgress, projectedProgress;
}
