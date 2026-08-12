import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

class TcxFileManager {
  /// Kotlin side writes into the phone's public Downloads folder
  /// (MediaStore on API 29+, the public directory below that).
  static const _exportsChannel = MethodChannel('com.gapp.sub3/exports');

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

  /// Delete a saved TCX file (called when a session is deleted).
  static Future<void> delete(int sessionId) async {
    final dir = await _tcxDir();
    final file = File(p.join(dir, '$sessionId.tcx'));
    if (file.existsSync()) await file.delete();
  }

  /// False on iOS, which has no shared Downloads folder — share instead.
  static bool get supportsDownloads => !Platform.isIOS;

  /// Turn a display name into a safe TCX file name (no extension).
  static String safeFileName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[^\w\-. ]'), '_').trim();
    final hasContent = cleaned.replaceAll(RegExp(r'[_\s.-]'), '').isNotEmpty;
    return hasContent ? cleaned : 'Sub3_run';
  }

  /// Save the session's TCX into the phone's Downloads folder.
  /// Returns the user-facing location, e.g. `Download/Sub3_Hillview.tcx`.
  /// Callers typically pass a name like `Sub3_<displayName>_<yyyy-MM-dd>`.
  static Future<String> exportToDownloads(
      int sessionId, String fileName) async {
    final content = await _requireContent(sessionId);
    final name = '${safeFileName(fileName)}.tcx';

    if (Platform.isAndroid) {
      final saved = await _exportsChannel.invokeMethod<String>(
        'saveToDownloads',
        {
          'fileName': name,
          'mimeType': 'application/vnd.garmin.tcx+xml',
          'content': content,
        },
      );
      if (saved == null || saved.isEmpty) {
        throw Exception('Could not save to the Downloads folder');
      }
      return saved;
    }

    // Desktop and anything else: write straight into the Downloads folder,
    // falling back to the documents directory when there isn't one.
    final dir = await _downloadsDirectory();
    final file = _withoutCollision(dir, name);
    await file.writeAsString(content);
    return p.join(p.basename(dir.path), p.basename(file.path));
  }

  /// Hand the session's TCX to the system share sheet.
  /// [sharePositionOrigin] anchors the popover on iPad, where share_plus
  /// refuses to present a sheet without one.
  static Future<void> shareTcx(
    int sessionId,
    String fileName, {
    Rect? sharePositionOrigin,
  }) async {
    final content = await _requireContent(sessionId);
    final name = '${safeFileName(fileName)}.tcx';

    // Share from a temp copy so the sheet shows a friendly file name
    // instead of the internal `<sessionId>.tcx`.
    final tmp = await getTemporaryDirectory();
    final file = File(p.join(tmp.path, name));
    await file.writeAsString(content);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/vnd.garmin.tcx+xml')],
      subject: name,
      sharePositionOrigin: sharePositionOrigin,
    );
  }

  static Future<String> _requireContent(int sessionId) async {
    final content = await read(sessionId);
    if (content == null) {
      throw Exception('TCX file not found for session $sessionId');
    }
    return content;
  }

  static Future<Directory> _downloadsDirectory() async {
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) {
        if (!downloads.existsSync()) downloads.createSync(recursive: true);
        return downloads;
      }
    } catch (_) {
      // Platform has no Downloads folder; fall through to documents.
    }
    return getApplicationDocumentsDirectory();
  }

  /// `run.tcx` → `run (1).tcx` → `run (2).tcx` … when the name is taken.
  static File _withoutCollision(Directory dir, String fileName) {
    var file = File(p.join(dir.path, fileName));
    if (!file.existsSync()) return file;

    final stem = p.basenameWithoutExtension(fileName);
    final ext = p.extension(fileName);
    var n = 1;
    while (file.existsSync()) {
      file = File(p.join(dir.path, '$stem ($n)$ext'));
      n++;
    }
    return file;
  }
}
