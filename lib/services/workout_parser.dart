import 'dart:convert';
import 'dart:io';
import 'package:xml/xml.dart';
import '../models/workout_file.dart';

class WorkoutParser {
  /// Parse a local file as either JSON workout or GPX route.
  static Future<WorkoutFile> parseFile(String filePath) async {
    final content = await File(filePath).readAsString();
    final name = filePath.split('/').last;

    if (filePath.endsWith('.gpx')) {
      return _parseGpx(name, content);
    }
    return _parseJson(name, content);
  }

  /// Parse raw content by filename extension.
  static WorkoutFile parseContent(String fileName, String content) {
    if (fileName.endsWith('.gpx')) {
      return _parseGpx(fileName, content);
    }
    return _parseJson(fileName, content);
  }

  /// Extract the display name from JSON metadata or GPX name element.
  static String extractDisplayName(String fileName, String content) {
    try {
      if (fileName.endsWith('.gpx')) {
        final doc = XmlDocument.parse(content);
        final nameEl = doc.findAllElements('name').firstOrNull;
        if (nameEl != null && nameEl.innerText.isNotEmpty) {
          return nameEl.innerText;
        }
      } else {
        final json = jsonDecode(content);
        final meta = json['metadata'];
        if (meta != null && meta['name'] != null) return meta['name'];
        if (json['name'] != null) return json['name'];
      }
    } catch (_) {}
    return fileName.replaceAll(RegExp(r'\.(json|gpx)$'), '');
  }

  // ── JSON Structured Workout ──

  static WorkoutFile _parseJson(String name, String content) {
    final json = jsonDecode(content);
    final List<dynamic> rawIntervals = json['intervals'] ?? json['blocks'] ?? [];

    final displayName = extractDisplayName(name, content);

    final intervals = rawIntervals.map((block) {
      final startSpeed = (block['speed'] as num?)?.toDouble() ??
          (block['speed_kmh'] as num?)?.toDouble() ??
          (block['start_speed_kmh'] as num?)?.toDouble() ??
          (block['pace'] as num?)?.toDouble() ??
          0.0;
      final endSpeed = (block['end_speed_kmh'] as num?)?.toDouble();
      final startIncline = (block['incline'] as num?)?.toDouble() ??
          (block['incline_pct'] as num?)?.toDouble() ??
          (block['start_incline_pct'] as num?)?.toDouble() ??
          (block['gradient'] as num?)?.toDouble() ??
          0.0;
      final endIncline = (block['end_incline_pct'] as num?)?.toDouble();

      return WorkoutInterval(
        durationSeconds: (block['duration'] as num?)?.toInt() ??
            (block['duration_seconds'] as num?)?.toInt() ??
            (block['time'] as num?)?.toInt() ??
            0,
        speedKmh: startSpeed,
        endSpeedKmh: endSpeed,
        inclinePct: startIncline,
        endInclinePct: endIncline,
        type: (block['type'] as String?) ?? 'active',
      );
    }).where((i) => i.durationSeconds > 0).toList();

    return WorkoutFile(
      name: name,
      displayName: displayName,
      isGpx: false,
      intervals: intervals,
    );
  }

  // ── GPX Virtual Run ──

  static WorkoutFile _parseGpx(String name, String content) {
    final doc = XmlDocument.parse(content);
    final displayName = extractDisplayName(name, content);
    final trkpts = doc.findAllElements('trkpt');

    final points = <GpxPoint>[];
    double cumDist = 0;

    GpxPoint? prev;
    for (final pt in trkpts) {
      final lat = double.parse(pt.getAttribute('lat')!);
      final lon = double.parse(pt.getAttribute('lon')!);
      final eleNode = pt.findElements('ele').firstOrNull;
      final ele = eleNode != null ? double.parse(eleNode.innerText) : 0.0;

      if (prev != null) {
        cumDist += WorkoutFile.haversine(prev.lat, prev.lon, lat, lon);
      }

      final point = GpxPoint(
        lat: lat,
        lon: lon,
        elevation: ele,
        cumulativeDistanceM: cumDist,
      );
      points.add(point);
      prev = point;
    }

    final smoothed = _smoothElevations(points, windowSize: 5);

    return WorkoutFile(
      name: name,
      displayName: displayName,
      isGpx: true,
      gpxPoints: points,
      smoothedElevations: smoothed,
    );
  }

  /// Moving-average filter to prevent jumpy incline commands.
  static List<double> _smoothElevations(List<GpxPoint> points,
      {int windowSize = 5}) {
    final raw = points.map((p) => p.elevation).toList();
    final smoothed = <double>[];
    for (var i = 0; i < raw.length; i++) {
      final start = (i - windowSize ~/ 2).clamp(0, raw.length - 1);
      final end = (i + windowSize ~/ 2 + 1).clamp(0, raw.length);
      final window = raw.sublist(start, end);
      smoothed.add(window.reduce((a, b) => a + b) / window.length);
    }
    return smoothed;
  }
}
