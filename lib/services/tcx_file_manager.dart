import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

/// Keeps each session's exported activity files — a FIT (the one Strava tags
/// as a Virtual Run) and a TCX (the proven fallback) — and hands them to
/// Downloads or the share sheet.
class TcxFileManager {
  /// Kotlin side writes into the phone's public Downloads folder
  /// (MediaStore on API 29+, the public directory below that).
  static const _exportsChannel = MethodChannel('com.gapp.sub3/exports');

  static const _fitMimeType = 'application/octet-stream';
  static const _tcxMimeType = 'application/vnd.garmin.tcx+xml';

  static Future<String> _tcxDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'tcx'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  static Future<String> _fitDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'fit'));
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

  /// Save FIT bytes and return the file path.
  static Future<String> saveFit(int sessionId, Uint8List fitBytes) async {
    final dir = await _fitDir();
    final path = p.join(dir, '$sessionId.fit');
    await File(path).writeAsBytes(fitBytes);
    return path;
  }

  /// Check if a TCX file exists for a session.
  static Future<bool> hasTcx(int sessionId) async {
    final dir = await _tcxDir();
    return File(p.join(dir, '$sessionId.tcx')).existsSync();
  }

  /// Check if a FIT file exists for a session. Legacy sessions and sessions
  /// whose FIT generation failed have only a TCX.
  static Future<bool> hasFit(int sessionId) async {
    final dir = await _fitDir();
    return File(p.join(dir, '$sessionId.fit')).existsSync();
  }

  /// Read a saved TCX file. Returns null if not found.
  static Future<String?> read(int sessionId) async {
    final dir = await _tcxDir();
    final file = File(p.join(dir, '$sessionId.tcx'));
    if (!file.existsSync()) return null;
    return file.readAsString();
  }

  /// Read a saved FIT file. Returns null if not found.
  static Future<Uint8List?> readFit(int sessionId) async {
    final dir = await _fitDir();
    final file = File(p.join(dir, '$sessionId.fit'));
    if (!file.existsSync()) return null;
    return file.readAsBytes();
  }

  /// Delete whichever of the session's exported files exist (called when a
  /// session is deleted).
  static Future<void> delete(int sessionId) async {
    final tcx = File(p.join(await _tcxDir(), '$sessionId.tcx'));
    if (tcx.existsSync()) await tcx.delete();
    final fit = File(p.join(await _fitDir(), '$sessionId.fit'));
    if (fit.existsSync()) await fit.delete();
  }

  /// False on iOS, which has no shared Downloads folder — share instead.
  static bool get supportsDownloads => !Platform.isIOS;

  /// Turn a display name into a safe export file name (no extension).
  static String safeFileName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[^\w\-. ]'), '_').trim();
    final hasContent = cleaned.replaceAll(RegExp(r'[_\s.-]'), '').isNotEmpty;
    return hasContent ? cleaned : 'Sub3_run';
  }

  /// Save the session's TCX into the phone's Downloads folder.
  /// Returns the user-facing location, e.g. `Download/Sub3_Hillview.tcx`.
  /// Callers typically pass a name like `Sub3_<displayName>_<yyyy-MM-dd>`.
  static Future<String> exportTcxToDownloads(
      int sessionId, String fileName) async {
    final content = await _requireTcx(sessionId);
    return _exportToDownloads('${safeFileName(fileName)}.tcx', _tcxMimeType,
        Uint8List.fromList(utf8.encode(content)));
  }

  /// Save the session's FIT into the phone's Downloads folder.
  /// Returns the user-facing location, e.g. `Download/Sub3_Hillview.fit`.
  static Future<String> exportFitToDownloads(
      int sessionId, String fileName) async {
    final bytes = await _requireFit(sessionId);
    return _exportToDownloads(
        '${safeFileName(fileName)}.fit', _fitMimeType, bytes);
  }

  static Future<String> _exportToDownloads(
      String name, String mimeType, Uint8List bytes) async {
    if (Platform.isAndroid) {
      final saved = await _exportsChannel.invokeMethod<String>(
        'saveToDownloads',
        {
          'fileName': name,
          'mimeType': mimeType,
          'bytes': bytes,
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
    await file.writeAsBytes(bytes);
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
    final content = await _requireTcx(sessionId);
    await _share('${safeFileName(fileName)}.tcx', _tcxMimeType,
        Uint8List.fromList(utf8.encode(content)), sharePositionOrigin);
  }

  /// Hand the session's FIT to the system share sheet.
  static Future<void> shareFit(
    int sessionId,
    String fileName, {
    Rect? sharePositionOrigin,
  }) async {
    final bytes = await _requireFit(sessionId);
    await _share(
        '${safeFileName(fileName)}.fit', _fitMimeType, bytes, sharePositionOrigin);
  }

  static Future<void> _share(
      String name, String mimeType, Uint8List bytes, Rect? origin) async {
    // Share from a temp copy so the sheet shows a friendly file name
    // instead of the internal `<sessionId>.fit` / `.tcx`.
    final tmp = await getTemporaryDirectory();
    final file = File(p.join(tmp.path, name));
    await file.writeAsBytes(bytes);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: mimeType)],
      subject: name,
      sharePositionOrigin: origin,
    );
  }

  static Future<String> _requireTcx(int sessionId) async {
    final content = await read(sessionId);
    if (content == null) {
      throw Exception('TCX file not found for session $sessionId');
    }
    return content;
  }

  static Future<Uint8List> _requireFit(int sessionId) async {
    final bytes = await readFit(sessionId);
    if (bytes == null) {
      throw Exception('FIT file not found for session $sessionId');
    }
    return bytes;
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
