import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'mediaflow_models.dart';

/// v410 cloud state_data is either a JSON object or a gzip/base64 envelope.
/// The codec is intentionally read-only: other snapshot fields aren't changed.
MediaFlowCatalog decodeMediaFlowState(
  Object? raw, {bool requireCoreCollections = false}
) {
  if (raw == null) {
    return const MediaFlowCatalog(categories: [], library: []);
  }
  Object? decoded = raw;
  if (raw is Map) {
    final envelope = Map<String, dynamic>.from(raw);
    if (envelope['__mediaflowCompressed'] == 'gzip') {
      final payload = envelope['data'];
      if (payload is! String || payload.isEmpty) {
        throw const FormatException('Invalid MediaFlow gzip envelope');
      }
      try {
        decoded = jsonDecode(utf8.decode(gzip.decode(base64Decode(payload))));
      } catch (_) {
        throw const FormatException('Unable to decode MediaFlow cloud state');
      }
    } else if (envelope.containsKey('__mediaflowCompressed')) {
      throw const FormatException('Unsupported MediaFlow compression');
    }
  } else if (raw is String) {
    decoded = jsonDecode(raw);
  }
  if (decoded is! Map) {
    throw const FormatException('MediaFlow cloud state is not an object');
  }
  final state = Map<String, dynamic>.from(decoded);
  if (requireCoreCollections &&
      (state['library'] is! List || state['categories'] is! List)) {
    throw const FormatException('Incomplete cloud Library/categories snapshot');
  }
  final rawLibrary = state['library'];
  final rawCategories = state['categories'];
  final rawSessions = state['sessions'];
  final rawCollections = state['collections'];
  final rawOrderPlan = state['orderPlan'];
  final orderPlan = rawOrderPlan is Map ? Map<String, dynamic>.from(rawOrderPlan) : const <String, dynamic>{};
  final rawOrderIds = orderPlan['titleIds'];
  final rawTask = state['currentTask'];
  final rawSettings = state['settings'];
  if (rawLibrary != null && rawLibrary is! List) {
    throw const FormatException('MediaFlow library must be an array');
  }
  if (rawCategories != null && rawCategories is! List) {
    throw const FormatException('MediaFlow categories must be an array');
  }
  if (rawSessions != null && rawSessions is! List) {
    throw const FormatException('MediaFlow sessions must be an array');
  }
  if (rawCollections != null && rawCollections is! List) {
    throw const FormatException('MediaFlow collections must be an array');
  }
  if (rawOrderIds != null && rawOrderIds is! List) {
    throw const FormatException('MediaFlow Personal Order titleIds must be an array');
  }
  final settings = rawSettings is Map
      ? Map<String, dynamic>.from(rawSettings)
      : const <String, dynamic>{};
  return MediaFlowCatalog(
    personalOrderIds: (rawOrderIds as List? ?? const []).map((id) => id.toString()).toSet().toList(growable: false),
    collections: (rawCollections as List? ?? const [])
        .whereType<Map>()
        .map((item) => MediaFlowCollection.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false),
    sessions: (rawSessions as List? ?? const [])
        .whereType<Map>()
        .map((item) => MediaFlowSession.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false),
    currentTask: rawTask is Map
        ? MediaFlowTask.fromJson(Map<String, dynamic>.from(rawTask))
        : null,
    sessionActive: state['sessionActive'] == true,
    tasksPerDay: mediaFlowNumber(settings['tasksPerDay']),
    dailyMinutes: mediaFlowNumber(settings['dailyMinutes']),
    xpEvidence: state['nativeXpEvidence'] is Map
      ? MediaFlowXpEvidence.fromProjection(
          Map<String, dynamic>.from(state['nativeXpEvidence'] as Map),
        )
      : MediaFlowXpEvidence.fromState(state),
    library: (rawLibrary as List? ?? const [])
        .whereType<Map>()
        .map((item) => MediaFlowTitle.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false),
    categories: (rawCategories as List? ?? const [])
        .whereType<Map>()
        .map((item) => MediaFlowCategory.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false),
  );
}

/// Isolate-backed parsing avoids blocking the UI while inflating large states.
Future<MediaFlowCatalog> decodeMediaFlowStateAsync(Object? raw) =>
    compute(_decodeCloudForReadOnly, raw);

MediaFlowCatalog _decodeCloudForReadOnly(Object? raw) =>
    decodeMediaFlowState(raw, requireCoreCollections: true);
