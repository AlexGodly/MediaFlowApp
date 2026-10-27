import 'dart:convert';
import 'dart:io';

/// The v410 website stores the entire account in one JSONB row.
/// Its state_data is either a plain JSON object or a JSONB gzip envelope.
/// This codec is used for *offline previews only*. It never writes to cloud.
abstract final class NativeSnapshotCodec {
  static Map<String, dynamic> decode(Object? raw) {
    if (raw == null) {
      throw const FormatException('Missing cloud snapshot; write blocked');
    }
    Object? value = raw;
    if (raw is Map) {
      final envelope = Map<String, dynamic>.from(raw);
      if (envelope.containsKey('__mediaflowCompressed')) {
        if (envelope['__mediaflowCompressed'] != 'gzip' ||
            envelope['data'] is! String) {
          throw const FormatException('Unsupported MediaFlow cloud envelope');
        }
        try {
          final decoded = gzip.decode(
            base64Decode(envelope['data'] as String),
          );
          value = jsonDecode(utf8.decode(decoded));
        } catch (_) {
          throw const FormatException('Corrupt MediaFlow cloud snapshot');
        }
      }
    } else if (raw is String) {
      value = jsonDecode(raw);
    }
    if (value is! Map) {
      throw const FormatException('Cloud snapshot is not an object');
    }
    return deepClone(Map<String, dynamic>.from(value));
  }

  static Map<String, dynamic> encodeLike(
    Map<String, dynamic> state,
    Object? original,
  ) {
    final serialized = jsonEncode(state);
    if (original is Map &&
        original['__mediaflowCompressed'] == 'gzip') {
      // Keep the same on-wire *format*, not the same compressed bytes.
      // Unknown v410 fields survive because the full state was cloned.
      final envelope = Map<String, dynamic>.from(original);
      envelope['data'] = base64Encode(gzip.encode(utf8.encode(serialized)));
      return envelope;
    }
    if (original is Map && original.containsKey('__mediaflowCompressed')) {
      throw const FormatException('Unsupported original cloud envelope');
    }
    return Map<String, dynamic>.from(jsonDecode(serialized) as Map);
  }

  static Map<String, dynamic> deepClone(Map<String, dynamic> source) =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(source)) as Map);

  /// Equivalent key ordering for JSONB object equality in *local tests*.
  /// Arrays retain their order; string/base64 fields are compared verbatim.
  static String canonicalJson(Object? value) =>
      jsonEncode(_canonical(value));

  static Object? _canonical(Object? value) {
    if (value is Map) {
      final entries = value.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      return {
        for (final entry in entries)
          entry.key.toString(): _canonical(entry.value),
      };
    }
    if (value is List) {
      return value.map(_canonical).toList(growable: false);
    }
    return value;
  }

  static bool equivalent(Object? first, Object? second) =>
      canonicalJson(first) == canonicalJson(second);
}
