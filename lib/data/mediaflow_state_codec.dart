import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'mediaflow_models.dart';

/// v410 cloud state_data is either a JSON object or a gzip/base64 envelope.
/// The codec is intentionally read-only: other snapshot fields aren't changed.
MediaFlowCatalog decodeMediaFlowState(Object? raw) {
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
  final rawLibrary = state['library'];
  final rawCategories = state['categories'];
  if (rawLibrary != null && rawLibrary is! List) {
    throw const FormatException('MediaFlow library must be an array');
  }
  if (rawCategories != null && rawCategories is! List) {
    throw const FormatException('MediaFlow categories must be an array');
  }
  return MediaFlowCatalog(
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
    compute(decodeMediaFlowState, raw);
