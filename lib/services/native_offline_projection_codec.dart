import '../data/mediaflow_models.dart';
import '../data/mediaflow_state_codec.dart';

/// A deliberately lossy, read-only projection for private device recovery.
/// It cannot be converted back into a complete v410 state_data cloud write.
abstract final class NativeOfflineProjectionCodec {
  static const format = 'mediaflow-native-readonly-projection-v1';

  static Map<String, dynamic> encode(MediaFlowCatalog catalog) => {
    'format': format,
    'cloudUpdatedAt': catalog.updatedAt?.toUtc().toIso8601String(),
    'snapshot': {
      'categories': [
        for (final c in catalog.categories)
          {'id': c.id, 'name': c.name, 'icon': c.icon,
           'iconUrl': c.iconUrl, 'color': c.color},
      ],
      'library': [
        for (final t in catalog.library)
          {'id': t.id, 'title': t.title, 'categoryId': t.categoryId,
           'status': t.status, 'priority': t.priority, 'progress': t.progress,
           'total': t.total, 'rating': t.rating, 'coverUrl': t.coverUrl,
           'description': t.description, 'tags': t.tags,
           'completedAt': t.completedAt?.toUtc().toIso8601String(),
           'createdAt': t.addedAt?.toUtc().toIso8601String(),
           'seasons': [
             for (final s in t.seasons)
               {'id': s.id, 'name': s.name, 'number': s.number,
                'synthetic': s.synthetic,
                'progress': s.progress, 'total': s.total},
           ]},
      ],
      'sessions': [
        for (final s in catalog.sessions)
          {'id': s.id, 'categoryId': s.categoryId, 'status': s.status,
           'date': s.date, 'timestamp': s.timestamp?.toUtc().toIso8601String(),
           'actualAmount': s.actualAmount, 'minutes': s.minutes,
           'xp': s.xp, 'unit': s.unit, 'note': s.note, 'source': s.source,
           'sessionGroupId': s.sessionGroupId,
           'batchGroupId': s.batchGroupId,
           'healthStatus': s.healthStatus,
           'assignedCategoryId': s.assignedCategoryId,
           'titles': [
             for (final t in s.titles)
               {'title': t.title, 'libraryId': t.libraryId,
                'qty': t.quantity,
                'loggedAt': t.loggedAt?.toUtc().toIso8601String(),
                'repeat': t.repeat,
                'v369Units': [
                  for (final u in t.units)
                    {'id': u.id, 'number': u.number,
                     'seasonId': u.seasonId, 'isRepeat': u.isRepeat,
                     'durationSeconds': u.durationSeconds,
                     'loggedAt': u.loggedAt?.toUtc().toIso8601String()},
                ]},
           ]},
      ],
      'collections': [
        for (final c in catalog.collections)
          {'id': c.id, 'title': c.title, 'description': c.description,
           'coverUrl': c.coverUrl, 'titleIds': c.titleIds},
      ],
      'orderPlan': {'titleIds': catalog.personalOrderIds},
      'currentTask': catalog.currentTask == null ? null : {
        'categoryId': catalog.currentTask!.categoryId,
        'title': catalog.currentTask!.title,
        'low': catalog.currentTask!.low,
        'high': catalog.currentTask!.high,
        'unit': catalog.currentTask!.unit,
        'reasons': catalog.currentTask!.reasons,
      },
      'sessionActive': catalog.sessionActive,
      'settings': {
        'tasksPerDay': catalog.tasksPerDay,
        'dailyMinutes': catalog.dailyMinutes,
      },
    },
  };

  static MediaFlowCatalog decode(Object? raw) {
    if (raw is! Map ||
        raw['format'] != format ||
        raw['snapshot'] is! Map) {
      throw const FormatException('Unsupported offline projection');
    }
    final date = raw['cloudUpdatedAt'];
    if (date != null && (date is! String || DateTime.tryParse(date) == null)) {
      throw const FormatException('Invalid offline cloud revision');
    }
    final value = decodeMediaFlowState(raw['snapshot']);
    return MediaFlowCatalog(
      categories: value.categories,
      library: value.library,
      sessions: value.sessions,
      collections: value.collections,
      personalOrderIds: value.personalOrderIds,
      currentTask: value.currentTask,
      sessionActive: value.sessionActive,
      tasksPerDay: value.tasksPerDay,
      dailyMinutes: value.dailyMinutes,
      updatedAt: date == null ? null : DateTime.parse(date as String),
    );
  }
}
