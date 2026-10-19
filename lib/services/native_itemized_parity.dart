// ignore_for_file: prefer_interpolation_to_compose_strings
import '../data/mediaflow_models.dart';
import 'native_logging_parity_preview.dart';

/// v252/v369/v394 source-grounded read-only *diagnostic* for explicit unit
/// numbers. Never creates or modifies a website session, XP ledger or cloud row.
class NativeItemizedPreview {
  const NativeItemizedPreview({
    required this.titleId,
    required this.seasonId,
    required this.seasonName,
    required this.repeat,
    required this.unitNumbers,
    required this.consumed,
    required this.elapsedSeconds,
    required this.knownArchivedUnitCount,
    required this.beforeSeasonProgress,
    required this.afterSeasonProgress,
    required this.beforeTitleProgress,
    required this.afterTitleProgress,
    required this.status,
    required this.completionCandidate,
  });

  final String titleId, seasonId, seasonName, status;
  final bool repeat, completionCandidate;
  final List<int> unitNumbers;
  final int consumed, elapsedSeconds, knownArchivedUnitCount;
  final double beforeSeasonProgress, afterSeasonProgress;
  final double beforeTitleProgress, afterTitleProgress;
  bool get cloudWritable => false;
  bool get historyWritable => false;
  double? get exactXp => null;
}

abstract final class NativeItemizedParity {
  static NativeItemizedPreview calculate({
    required MediaFlowTitle title,
    required Iterable<MediaFlowSession> sessions,
    required String seasonId,
    required Iterable<int> numbers,
    required int secondsPerUnit,
    bool repeat = false,
  }) {
    if (title.id.isEmpty || secondsPerUnit < 0 ||
        secondsPerUnit > 86400) {
      throw const FormatException('Invalid title or unit duration');
    }
    final incoming = List<int>.unmodifiable(numbers);
    if (incoming.isEmpty || incoming.length > 10000 ||
        incoming.any((n) => n < 1 || n > 999999) ||
        incoming.toSet().length != incoming.length) {
      throw const FormatException('Invalid or duplicate unit numbers');
    }
    if (title.seasons.isNotEmpty) {
      final ids = <String>{};
      for (final season in title.seasons) {
        if (season.id.isEmpty || !ids.add(season.id)) {
          throw const FormatException('Stable unique season IDs required');
        }
        if (!season.progress.isFinite || season.progress < 0 ||
            (season.total != null && season.total! > 0 &&
             season.progress > season.total!)) {
          throw const FormatException('Invalid season progress');
        }
      }
      final sum = title.seasons.fold<double>(
        0, (value, season) => value + season.progress,
      );
      if ((sum - title.progress).abs() > 0.000001) {
        throw const FormatException(
          'Stored title progress differs from its season aggregate',
        );
      }
    }
    if (repeat && !NativeLoggingParityPreview.isCompleted(title)) {
      throw const FormatException(
        'Global repeat requires a completed title',
      );
    }
    if (!repeat && NativeLoggingParityPreview.isCompleted(title)) {
      throw const FormatException('Completed title requires repeat mode');
    }

    MediaFlowSeason? chosen;
    if (title.seasons.isNotEmpty) {
      for (final season in title.seasons) {
        if (season.id == seasonId) chosen = season;
      }
      if (chosen == null) {
        throw const FormatException('Select an actual title season ID');
      }
    } else if (seasonId.isNotEmpty) {
      throw const FormatException('Unseasoned title cannot select a season');
    }

    final starting = chosen?.progress ?? title.progress;
    final total = chosen?.total ?? title.total;
    final safeStart = starting.floor();
    final limit = total != null && total > 0 ? total.floor() : null;
    if (limit != null && incoming.any((unit) => unit > limit)) {
      throw const FormatException('Unit exceeds its season/title limit');
    }

    // v369 refuses previously confirmed non-repeat unit numbers.
    if (!repeat && incoming.any((unit) => unit <= safeStart)) {
      throw const FormatException(
        'Previously confirmed unit requires explicit repeat handling',
      );
    }

    final archived = <int>[];
    var archivedCount = 0;
    for (final record in sessions) {
      for (final entry in record.titles) {
        if (entry.libraryId != title.id || entry.repeat) continue;
        for (final unit in entry.units) {
          if (unit.isRepeat) continue;
          if (title.seasons.isNotEmpty &&
              unit.seasonId.isEmpty) {
            // We cannot safely attribute unscoped archived unit numbers to
            // one of several seasons, so quarantine the calculation.
            throw const FormatException(
              'Archived itemized unit missing season ownership',
            );
          }
          if (unit.seasonId != seasonId) continue;
          if (unit.number < 1) {
            throw const FormatException('Invalid archived unit number');
          }
          archived.add(unit.number);
          archivedCount++;
        }
      }
    }
    final newProgress = repeat ? starting :
        NativeLoggingParityPreview.contiguousProgress(
          start: safeStart,
          unitNumbers: [...archived, ...incoming],
          total: limit,
        ).toDouble();
    final aggregate = repeat ? title.progress :
        title.progress + (newProgress - starting);
    final completeCandidate = !repeat &&
        !NativeLoggingParityPreview.isCompleted(title) &&
        title.status != 'dropped' &&
        title.total != null && title.total! > 0 &&
        aggregate >= title.total!;
    final status = repeat ? title.status :
        completeCandidate ? 'completed' :
        title.status == 'planned' ? 'active' : title.status;

    return NativeItemizedPreview(
      titleId: title.id,
      seasonId: chosen?.id ?? '',
      seasonName: chosen?.name ?? 'Main title',
      repeat: repeat,
      unitNumbers: incoming,
      consumed: incoming.length,
      elapsedSeconds: incoming.length * secondsPerUnit,
      knownArchivedUnitCount: archivedCount,
      beforeSeasonProgress: starting,
      afterSeasonProgress: newProgress,
      beforeTitleProgress: title.progress,
      afterTitleProgress: aggregate,
      status: status,
      completionCandidate: completeCandidate,
    );
  }
}
