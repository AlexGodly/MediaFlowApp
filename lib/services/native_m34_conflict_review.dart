import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'native_cas_protocol.dart';
import 'native_m33_offline_queue.dart';
import 'native_snapshot_codec.dart';

/// A comparison is a snapshot of an authenticated SELECT, NEVER permission
/// to update the server. Every resolution rechecks this snapshot or is
/// restricted to removing a device-local intent.
enum NativeM34ItemStatus {
  unchanged, alreadyDesired, changedElsewhere, missing, duplicated,
  invalidCloudPriority, unknownOffline,
}

class NativeM34ConflictItem {
  const NativeM34ConflictItem({
    required this.operationId,
    required this.titleId,
    required this.title,
    required this.beforePriority,
    required this.desiredPriority,
    required this.cloudPriority,
    required this.status,
  });

  final String operationId, titleId, title;
  final String beforePriority, desiredPriority;
  final String? cloudPriority;
  final NativeM34ItemStatus status;
  bool get mayRecreate => status == NativeM34ItemStatus.unchanged ||
      status == NativeM34ItemStatus.changedElsewhere;
}

class NativeM34ReviewReport {
  NativeM34ReviewReport({
    required this.ownerId,
    required this.queueId,
    required this.queueDigest,
    required List<NativeM34ConflictItem> items,
    required this.message,
    this.cloudUpdatedAt,
    this.cloudDigest,
    this.anchorChanged = false,
  }) : items = List.unmodifiable(items);

  final String ownerId, queueId, queueDigest, message;
  final String? cloudUpdatedAt, cloudDigest;
  final bool anchorChanged;
  final List<NativeM34ConflictItem> items;

  bool get hasFreshCloud => cloudUpdatedAt != null && cloudDigest != null;
  bool get mayUpload => false;
  int get conflicts => items.where((e) =>
      e.status == NativeM34ItemStatus.changedElsewhere ||
      e.status == NativeM34ItemStatus.missing ||
      e.status == NativeM34ItemStatus.duplicated ||
      e.status == NativeM34ItemStatus.invalidCloudPriority).length;

  NativeM34ConflictItem? byOperation(String id) {
    for (final item in items) {
      if (item.operationId == id) return item;
    }
    return null;
  }
}

abstract final class NativeM34ReviewEngine {
  static String queueDigest(NativeM33OfflineDraftQueue queue) =>
      sha256.convert(utf8.encode(
        NativeSnapshotCodec.canonicalJson(queue.toJson()),
      )).toString();

  static String cloudDigest(NativeCloudRow row) => sha256.convert(
    utf8.encode(NativeSnapshotCodec.canonicalJson(row.stateData)),
  ).toString();

  static NativeM34ReviewReport unavailable({
    required NativeM33OfflineDraftQueue queue,
    required String signedInOwnerId,
  }) {
    if (signedInOwnerId.isEmpty || queue.ownerId != signedInOwnerId) {
      throw StateError('Wrong owner for offline review');
    }
    return NativeM34ReviewReport(
      ownerId: signedInOwnerId, queueId: queue.queueId,
      queueDigest: queueDigest(queue),
      message: 'Cloud unavailable. Saved intents remain device-only.',
      items: [
        for (final entry in queue.entries)
          NativeM34ConflictItem(
            operationId: entry.operationId, titleId: entry.titleId,
            title: entry.titleId, beforePriority: entry.beforePriority,
            desiredPriority: entry.afterPriority, cloudPriority: null,
            status: NativeM34ItemStatus.unknownOffline,
          ),
      ],
    );
  }

  static NativeM34ReviewReport inspect({
    required NativeM33OfflineDraftQueue queue,
    required NativeCloudRow current,
    required String signedInOwnerId,
  }) {
    if (signedInOwnerId.isEmpty || queue.ownerId != signedInOwnerId ||
        current.ownerId != signedInOwnerId) {
      throw StateError('Foreign account in conflict review');
    }
    if (current.updatedAt.isEmpty) {
      throw const FormatException('No authenticated cloud timestamp');
    }
    final Map<String, dynamic> state;
    try {
      state = NativeSnapshotCodec.decode(current.stateData);
    } catch (_) {
      throw const FormatException('Invalid full cloud snapshot');
    }
    if (state['library'] is! List || state['sessions'] is! List ||
        state['categories'] is! List || state['settings'] is! Map) {
      throw const FormatException('Incomplete authenticated cloud data');
    }
    final library = state['library'] as List;
    final items = <NativeM34ConflictItem>[];
    for (final intent in queue.entries) {
      final matches = library.whereType<Map>().where(
        (v) => v['id'] == intent.titleId).toList();
      NativeM34ItemStatus kind;
      String? currentPriority;
      String title = intent.titleId;
      if (matches.isEmpty) {
        kind = NativeM34ItemStatus.missing;
      } else if (matches.length != 1) {
        kind = NativeM34ItemStatus.duplicated;
      } else {
        final entry = matches.single;
        final label = entry['title'];
        if (label is String && label.trim().isNotEmpty) {
          title = label.length > 160 ? label.substring(0, 160) : label;
        }
        currentPriority = entry['priority'] is String
            ? entry['priority'] as String : null;
        if (!const {'low', 'medium', 'high'}.contains(currentPriority)) {
          kind = NativeM34ItemStatus.invalidCloudPriority;
        } else if (currentPriority == intent.beforePriority) {
          kind = NativeM34ItemStatus.unchanged;
        } else if (currentPriority == intent.afterPriority) {
          kind = NativeM34ItemStatus.alreadyDesired;
        } else {
          kind = NativeM34ItemStatus.changedElsewhere;
        }
      }
      items.add(NativeM34ConflictItem(
        operationId: intent.operationId, titleId: intent.titleId,
        title: title, beforePriority: intent.beforePriority,
        desiredPriority: intent.afterPriority,
        cloudPriority: currentPriority, status: kind,
      ));
    }
    final digest = cloudDigest(current);
    final changed = queue.fullCloudDigest != null &&
        (queue.cloudUpdatedAt != current.updatedAt ||
         queue.fullCloudDigest != digest);
    return NativeM34ReviewReport(
      ownerId: signedInOwnerId, queueId: queue.queueId,
      queueDigest: queueDigest(queue), items: items,
      cloudUpdatedAt: current.updatedAt, cloudDigest: digest,
      anchorChanged: changed,
      message: changed
          ? 'The complete cloud snapshot changed. Recreate only after review.'
          : 'Per-title comparison complete. No cloud update was performed.',
    );
  }
}
