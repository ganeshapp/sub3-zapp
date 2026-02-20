import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class TcxFileManager {
  static Future<String> _tcxDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'tcx'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  /// Save a TCX string and return the file path.
  static Future<String> save(int sessionId, String tcxContent) async {
    final dir = await _tcxDir();
    final path = p.join(dir, '$sessionId.tcx');
    await File(path).writeAsString(tcxContent);
    return path;
  }

  /// Check if a TCX file exists for a session.
  static Future<bool> exists(int sessionId) async {
    final dir = await _tcxDir();
    return File(p.join(dir, '$sessionId.tcx')).existsSync();
  }

  /// Read a saved TCX file. Returns null if not found.
  static Future<String?> read(int sessionId) async {
    final dir = await _tcxDir();
    final file = File(p.join(dir, '$sessionId.tcx'));
    if (!file.existsSync()) return null;
    return file.readAsString();
  }

  /// Export a TCX file to the device's accessible storage.
  /// Returns the exported file path.
  static Future<String> exportToDownloads(
      int sessionId, String fileName) async {
    final content = await read(sessionId);
    if (content == null) {
      throw Exception('TCX file not found for session $sessionId');
    }

    // Use external storage on Android, documents on iOS
    Directory exportDir;
    try {
      final ext = await getExternalStorageDirectory();
      exportDir = ext ?? await getApplicationDocumentsDirectory();
    } catch (_) {
      exportDir = await getApplicationDocumentsDirectory();
    }

    final exportPath = p.join(
      exportDir.path,
      '${fileName.replaceAll(RegExp(r'[^\w\-.]'), '_')}.tcx',
    );
    await File(exportPath).writeAsString(content);
    return exportPath;
  }
}
