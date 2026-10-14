import 'dart:math';

import 'package:crypto/crypto.dart';
import 'dart:convert';

import 'native_cas_protocol.dart';
import 'native_snapshot_codec.dart';

/// Device-only, owner-bound intent. NEVER an authorized cloud operation.
/// Local IDs are non-reusable within one queue; no arbitrary JSON patches.
class NativeM33PriorityDraft {
  NativeM33PriorityDraft({
    required this.operationId,
    required this.titleId,
    required this.beforePriority,
    required this.afterPriority,
    required this.createdAt,
  }) {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(operationId) ||
        titleId.isEmpty || titleId.length > 256 ||
        !const {'low', 'medium', 'high'}.contains(beforePriority) ||
        !const {'low', 'medium', 'high'}.contains(afterPriority) ||
        beforePriority == afterPriority ||
        createdAt.isAfter(DateTime.now().toUtc().add(
          const Duration(minutes: 5)))) {
      throw const FormatException('Unsafe offline priority intent');
    }
  }

  final String operationId, titleId, beforePriority, afterPriority;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
    'operationId': operationId, 'titleId': titleId,
    'beforePriority': beforePriority, 'afterPriority': afterPriority,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  factory NativeM33PriorityDraft.fromJson(Map<String, dynamic> raw) {
    final date = DateTime.tryParse(raw['createdAt']?.toString() ?? '');
    if (date == null) throw const FormatException('Missing intent timestamp');
    return NativeM33PriorityDraft(
      operationId: raw['operationId']?.toString() ?? '',
      titleId: raw['titleId']?.toString() ?? '',
      beforePriority: raw['beforePriority']?.toString() ?? '',
      afterPriority: raw['afterPriority']?.toString() ?? '',
      createdAt: date,
    );
  }
}

class NativeM33OfflineDraftQueue {
  NativeM33OfflineDraftQueue({
    required this.ownerId,
    required this.queueId,
    required this.source,
    required this.createdAt,
    required List<NativeM33PriorityDraft> entries,
    this.fullCloudDigest,
    this.cloudUpdatedAt,
  }) : _entries = List.unmodifiable(entries) {
    if (ownerId.isEmpty ||
        !RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(queueId) ||
        !const {'cloud', 'offline', 'recoveredPrevious', 'offlineMemory'}
            .contains(source) ||
        createdAt.isAfter(DateTime.now().toUtc().add(
          const Duration(minutes: 5))) ||
        _entries.isEmpty || _entries.length > 100 ||
        (fullCloudDigest == null) != (cloudUpdatedAt == null) ||
        (fullCloudDigest != null &&
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(fullCloudDigest!)) ||
        (cloudUpdatedAt != null && cloudUpdatedAt!.isEmpty) ||
        (source != 'cloud' && fullCloudDigest != null) ||
        _entries.map((e) => e.operationId).toSet().length != _entries.length ||
        _entries.map((e) => e.titleId).toSet().length != _entries.length) {
      throw const FormatException('Unsafe or ambiguous offline draft queue');
    }
  }

  static const format = 'mediaflow-m33-offline-drafts-v1';
  final String ownerId, queueId, source;
  final DateTime createdAt;
  final String? fullCloudDigest, cloudUpdatedAt;
  final List<NativeM33PriorityDraft> _entries;
  List<NativeM33PriorityDraft> get entries =>
      List<NativeM33PriorityDraft>.unmodifiable(_entries);

  Map<String, Object?> toJson() => {
    'format': format, 'ownerId': ownerId, 'queueId': queueId,
    'source': source, 'createdAt': createdAt.toUtc().toIso8601String(),
    'fullCloudDigest': fullCloudDigest, 'cloudUpdatedAt': cloudUpdatedAt,
    'entries': _entries.map((e) => e.toJson()).toList(),
  };

  factory NativeM33OfflineDraftQueue.fromJson(
    Map<String, dynamic> raw, {required String signedInOwnerId}
  ) {
    if (signedInOwnerId.isEmpty ||
        raw['format'] != format || raw['ownerId'] != signedInOwnerId ||
        raw['entries'] is! List) {
      throw const FormatException('Foreign or invalid offline queue');
    }
    final date = DateTime.tryParse(raw['createdAt']?.toString() ?? '');
    if (date == null) throw const FormatException('Invalid queue date');
    return NativeM33OfflineDraftQueue(
      ownerId: signedInOwnerId,
      queueId: raw['queueId']?.toString() ?? '',
      source: raw['source']?.toString() ?? '',
      createdAt: date,
      fullCloudDigest: raw['fullCloudDigest'] as String?,
      cloudUpdatedAt: raw['cloudUpdatedAt'] as String?,
      entries: [
        for (final rawEntry in raw['entries'] as List)
          if (rawEntry is Map)
            NativeM33PriorityDraft.fromJson(Map<String, dynamic>.from(rawEntry))
          else
            throw const FormatException('Invalid offline queue entry'),
      ],
    );
  }

  static String freshId() {
    final secure = Random.secure();
    return 'm33_${List.generate(16,
      (_) => secure.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
  }
}

/// A manual comparison is NOT a cloud save authorization.
/// Old full-state timestamps are not a server revision; even matching title
/// priority cannot establish that a save would be safe.
enum NativeM33CheckStatus {
  needsManualCloudReview, unrelatedCloudChanges, titleConflict,
  missingOrDuplicateTitle, alreadyMatchesTarget, unavailable,
  foreignAccount, invalidCloud,
}

class NativeM33CheckResult {
  const NativeM33CheckResult(this.status, this.message, {
    this.matchedCount = 0,
  });

  final NativeM33CheckStatus status;
  final String message;
  final int matchedCount;
  bool get mayUpload => false;
}

/// No network IO, no disk and no authorized replay path. This is the
/// read-only comparison step called on a user-triggered fresh SELECT.
abstract final class NativeM33ManualReview {
  static NativeM33CheckResult inspect({
    required NativeM33OfflineDraftQueue queue,
    required NativeCloudRow current,
    required String signedInOwnerId,
  }) {
    if (signedInOwnerId.isEmpty || queue.ownerId != signedInOwnerId ||
        current.ownerId != signedInOwnerId) {
      return const NativeM33CheckResult(
        NativeM33CheckStatus.foreignAccount, 'Signed-in owner mismatch');
    }
    final Map<String, dynamic> state;
    try {
      state = NativeSnapshotCodec.decode(current.stateData);
    } on FormatException {
      return const NativeM33CheckResult(
        NativeM33CheckStatus.invalidCloud,
        'Cloud snapshot is invalid; nothing changed');
    }
    if (state['library'] is! List || state['sessions'] is! List ||
        state['categories'] is! List || state['settings'] is! Map) {
      return const NativeM33CheckResult(
        NativeM33CheckStatus.invalidCloud,
        'Incomplete cloud data; no reconciliation');
    }

    final library = state['library'] as List;
    var matching = 0;
    var already = 0;
    for (final item in queue.entries) {
      final matches = library.whereType<Map>().where(
        (title) => title['id'] == item.titleId).toList();
      if (matches.length != 1) {
        return NativeM33CheckResult(
          NativeM33CheckStatus.missingOrDuplicateTitle,
          'A referenced title is missing or duplicated; discard/review manually',
          matchedCount: matching,
        );
      }
      if (matches.single['priority'] == item.beforePriority) {
        matching++;
      } else if (matches.single['priority'] == item.afterPriority) {
        already++;
      } else {
        return NativeM33CheckResult(
          NativeM33CheckStatus.titleConflict,
          'A title priority changed on another client; no automatic merge',
          matchedCount: matching,
        );
      }
    }
    // Source is an encrypted offline projection => there was no full-cloud
    // baseline. No safe CAS plan may be inferred from title-priority matches.
    if (queue.fullCloudDigest != null &&
        (queue.cloudUpdatedAt != current.updatedAt ||
         queue.fullCloudDigest != sha256.convert(utf8.encode(
             NativeSnapshotCodec.canonicalJson(current.stateData))).toString())) {
      return NativeM33CheckResult(
        NativeM33CheckStatus.unrelatedCloudChanges,
        'Cloud data changed since this draft; review manually',
        matchedCount: matching,
      );
    }
    if (already == queue.entries.length) {
      return NativeM33CheckResult(
        NativeM33CheckStatus.alreadyMatchesTarget,
        'Current priority matches, but this does NOT prove this draft was saved',
        matchedCount: already,
      );
    }
    return NativeM33CheckResult(
      NativeM33CheckStatus.needsManualCloudReview,
      'Draft compared to fresh cloud. Production submission is disabled',
      matchedCount: matching,
    );
  }
}
