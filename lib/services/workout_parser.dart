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

  // ── JSON Structured Workout ──

  static WorkoutFile _parseJson(String name, String content) {
    final json = jsonDecode(content);
    final List<dynamic> rawIntervals = json['intervals'] ?? json['blocks'] ?? [];

    final intervals = rawIntervals.map((block) {
      return WorkoutInterval(
        durationSeconds: (block['duration'] as num).toInt(),
        speedKmh: (block['speed'] as num).toDouble(),
        inclinePct: ((block['incline'] ?? 0) as num).toDouble(),
      );
    }).toList();

    return WorkoutFile(name: name, isGpx: false, intervals: intervals);
  }

  // ── GPX Virtual Run ──

  static WorkoutFile _parseGpx(String name, String content) {
    final doc = XmlDocument.parse(content);
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
