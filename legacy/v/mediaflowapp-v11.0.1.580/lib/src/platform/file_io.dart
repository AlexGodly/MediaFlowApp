// Opening and saving the files the website's imports and exports use.

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

bool get _desktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// Asks for a file and returns its text (null: cancelled or unreadable).
Future<({String name, String text})?> pickTextFile({List<String> extensions = const ['json']}) async {
  final res = await FilePicker.platform.pickFiles(
    // Android maps custom extensions to MIME types badly; any file works there.
    type: _desktop ? FileType.custom : FileType.any,
    allowedExtensions: _desktop ? extensions : null,
    withData: true,
  );
  final f = res?.files.singleOrNull;
  if (f == null) return null;
  final bytes = f.bytes ?? (f.path == null ? null : await File(f.path!).readAsBytes());
  if (bytes == null) return null;
  return (name: f.name, text: utf8.decode(bytes, allowMalformed: true));
}

/// Saves [content] as [name] where the user chooses. Returns where it went
/// (null: cancelled or failed).
Future<String?> saveTextFile(String name, String content) async {
  final bytes = utf8.encode(content);
  try {
    final path = await FilePicker.platform.saveFile(fileName: name, bytes: bytes);
    if (path == null) return null;
    if (_desktop) await File(path).writeAsBytes(bytes, flush: true);
    return path;
  } catch (_) {
    // No system dialog: keep it in Downloads / Documents.
    try {
      Directory? dir;
      try {
        dir = await getDownloadsDirectory();
      } catch (_) {}
      dir ??= await getApplicationDocumentsDirectory();
      final f = File('${dir.path}${Platform.pathSeparator}$name');
      await f.writeAsBytes(bytes, flush: true);
      return f.path;
    } catch (_) {
      return null;
    }
  }
}

/// Asks for a folder (null: cancelled or not supported here).
Future<String?> pickFolder() async {
  try {
    return await FilePicker.platform.getDirectoryPath();
  } catch (_) {
    return null;
  }
}
