import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:isolate';

/// The website stores `state_data` either as plain JSON or, in current versions,
/// as `{"__mediaflowCompressed":"gzip","data":"<base64 of gzipped JSON>"}`.
Map<String, dynamic> decodeStateData(Object? value) {
  if (value is Map && value['__mediaflowCompressed'] == 'gzip') {
    final data = value['data'];
    if (data is! String) throw const FormatException('Compressed MediaFlow state has no data');
    final text = utf8.decode(gzip.decode(base64.decode(data)));
    final decoded = jsonDecode(text);
    if (decoded is! Map) throw const FormatException('MediaFlow state is not an object');
    return decoded.cast<String, dynamic>();
  }
  if (value is Map) {
    // Deep, mutable copy.
    return (jsonDecode(jsonEncode(value)) as Map).cast<String, dynamic>();
  }
  if (value is String && value.trim().startsWith('{')) {
    return decodeStateData(jsonDecode(value));
  }
  throw const FormatException('Unrecognised MediaFlow state format');
}

/// Same format the website writes (gzip + base64), so either side can read it.
Map<String, dynamic> encodeStateData(Map<String, dynamic> state) {
  final bytes = gzip.encode(utf8.encode(jsonEncode(state)));
  return {'__mediaflowCompressed': 'gzip', 'data': base64.encode(bytes)};
}

Map<String, dynamic> deepCopyState(Map<String, dynamic> state) =>
    (jsonDecode(jsonEncode(state)) as Map).cast<String, dynamic>();

// Background helpers. Kept top-level so the isolate closure captures only its
// arguments (a closure inside a class method could capture unsendable objects).
Future<Map<String, dynamic>> decodeStateDataInBackground(Object? raw) => Isolate.run(() => decodeStateData(raw));

Future<Map<String, dynamic>> encodeStateDataInBackground(Map<String, dynamic> state) =>
    Isolate.run(() => encodeStateData(state));

Future<String> jsonEncodeInBackground(Object? value) => Isolate.run(() => jsonEncode(value));

Future<Object?> jsonDecodeInBackground(String text) => Isolate.run(() => jsonDecode(text));

Future<Map<String, dynamic>> deepCopyStateInBackground(Map<String, dynamic> state) =>
    Isolate.run(() => deepCopyState(state));
