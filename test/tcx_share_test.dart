import 'dart:io';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
import 'package:sub3/services/tcx_file_manager.dart';

/// Stands in for the real path_provider so the test controls exactly which
/// directory `getTemporaryDirectory()` hands back.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider({required this.temp, required this.documents});

  final String temp;
  final String documents;

  @override
  Future<String?> getTemporaryPath() async => temp;

  @override
  Future<String?> getApplicationDocumentsPath() async => documents;

  @override
  Future<String?> getDownloadsPath() async => null;
}

class _ShareCall {
  _ShareCall(this.paths, this.origin);
  final List<String> paths;
  final Rect? origin;
}

class _RecordingShare extends SharePlatform {
  final calls = <_ShareCall>[];

  @override
  Future<ShareResult> shareXFiles(
    List<XFile> files, {
    String? subject,
    String? text,
    Rect? sharePositionOrigin,
    List<String>? fileNameOverrides,
  }) async {
    calls.add(
        _ShareCall(files.map((f) => f.path).toList(), sharePositionOrigin));
    return const ShareResult('ok', ShareResultStatus.success);
  }
}

void main() {
  group('Share the TCX (§1)', () {
    late Directory root;
    late Directory appTemp;
    late _RecordingShare share;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      root = Directory.systemTemp.createTempSync('sub3_share_test');
      appTemp = Directory(p.join(root.path, 'cache'))..createSync();
      final docs = Directory(p.join(root.path, 'documents'))..createSync();
      PathProviderPlatform.instance =
          _FakePathProvider(temp: appTemp.path, documents: docs.path);
      share = _RecordingShare();
      SharePlatform.instance = share;
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    // Without an origin the iOS plugin builds CGRectZero and, on iPad, where
    // UIKit forces the popover style, returns a FlutterError instead of
    // presenting the sheet — and iOS has no Downloads folder to fall back on.
    test('forwards the iPad popover anchor', () async {
      await TcxFileManager.save(3, '<TrainingCenterDatabase/>');
      await TcxFileManager.shareTcx(3, 'Sub3_Hillview_2026-08-12',
          sharePositionOrigin: const Rect.fromLTWH(10, 20, 300, 400));

      expect(share.calls.single.origin, const Rect.fromLTWH(10, 20, 300, 400));
    });

    test('stages the copy under the readable export name', () async {
      await TcxFileManager.save(4, '<TrainingCenterDatabase/>');
      await TcxFileManager.shareTcx(4, 'Sub3_Hillview_2026-08-12');

      final staged = share.calls.single.paths.single;
      expect(p.isWithin(appTemp.path, staged), isTrue);
      expect(p.basename(staged), 'Sub3_Hillview_2026-08-12.tcx');
      expect(File(staged).readAsStringSync(), '<TrainingCenterDatabase/>');
    });
  });
}
