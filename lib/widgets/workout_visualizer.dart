import 'dart:math';
import 'package:flutter/material.dart';
import '../models/workout_file.dart';

/// Renders a progress-tracked visualizer:
/// - JSON workouts: bar chart of interval speeds with red progress dot (time-based).
/// - GPX routes: 2D elevation profile with red progress dot (distance-based).
class WorkoutVisualizer extends StatelessWidget {
  final WorkoutFile workoutFile;

  /// 0.0–1.0 progress fraction.
  final double progress;

  const WorkoutVisualizer({
    super.key,
    required this.workoutFile,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        size: Size.infinite,
        painter: workoutFile.isGpx
            ? _GpxRoutePainter(
                points: workoutFile.gpxPoints ?? [],
                progress: progress,
              )
            : _IntervalBarPainter(
                intervals: workoutFile.intervals ?? [],
                progress: progress,
              ),
      ),
    );
  }
}

// ── JSON Interval Bar Chart ──

class _IntervalBarPainter extends CustomPainter {
  final List<WorkoutInterval> intervals;
  final double progress;

  _IntervalBarPainter({required this.intervals, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (intervals.isEmpty) return;

    final totalDuration =
        intervals.fold(0, (sum, i) => sum + i.durationSeconds);
    if (totalDuration == 0) return;

    final maxSpeed =
        intervals.map((i) => i.speedKmh).reduce(max).clamp(1.0, 100.0);
    const hPad = 8.0;
    const vPad = 16.0;
    final drawW = size.width - hPad * 2;
    final drawH = size.height - vPad * 2;

    final barPaint = Paint();
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.08);

    double x = hPad;
    for (final interval in intervals) {
      final w = (interval.durationSeconds / totalDuration) * drawW;
      final h = (interval.speedKmh / maxSpeed) * drawH;
      final rect = Rect.fromLTWH(x, size.height - vPad - h, w, h);

      barPaint.color = Colors.white.withValues(alpha: 0.12);
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(3)), barPaint);
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(3)), borderPaint);

      x += w;
    }

    // Progress dot
    final dotX = hPad + progress.clamp(0.0, 1.0) * drawW;
    _drawProgressDot(canvas, size, dotX, vPad);
  }

  @override
  bool shouldRepaint(covariant _IntervalBarPainter old) =>
      old.progress != progress;
}

// ── GPX Top-Down Route Map ──

class _GpxRoutePainter extends CustomPainter {
  final List<GpxPoint> points;
  final double progress;

  _GpxRoutePainter({required this.points, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    const pad = 14.0;
    final drawW = size.width - pad * 2;
    final drawH = size.height - pad * 2;

    // Compute bounding box of lat/lon
    double minLat = points.first.lat, maxLat = points.first.lat;
    double minLon = points.first.lon, maxLon = points.first.lon;
    for (final p in points) {
      if (p.lat < minLat) minLat = p.lat;
      if (p.lat > maxLat) maxLat = p.lat;
      if (p.lon < minLon) minLon = p.lon;
      if (p.lon > maxLon) maxLon = p.lon;
    }

    final latRange = (maxLat - minLat).clamp(1e-6, double.infinity);
    final lonRange = (maxLon - minLon).clamp(1e-6, double.infinity);

    // Aspect-ratio-correct scaling
    final scaleX = drawW / lonRange;
    final scaleY = drawH / latRange;
    final scale = min(scaleX, scaleY);
    final offsetX = pad + (drawW - lonRange * scale) / 2;
    final offsetY = pad + (drawH - latRange * scale) / 2;

    Offset toCanvas(GpxPoint p) => Offset(
          offsetX + (p.lon - minLon) * scale,
          offsetY + (maxLat - p.lat) * scale, // flip Y so north is up
        );

    // Draw the full route (dim)
    final routePath = Path();
    routePath.moveTo(toCanvas(points.first).dx, toCanvas(points.first).dy);
    for (var i = 1; i < points.length; i++) {
      final c = toCanvas(points[i]);
      routePath.lineTo(c.dx, c.dy);
    }

    final dimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white.withValues(alpha: 0.15);
    canvas.drawPath(routePath, dimPaint);

    // Draw the completed portion (bright red glow)
    final totalDist = points.last.cumulativeDistanceM;
    final progressDist = progress.clamp(0.0, 1.0) * totalDist;

    final activePath = Path();
    activePath.moveTo(toCanvas(points.first).dx, toCanvas(points.first).dy);
    Offset dotPos = toCanvas(points.first);

    for (var i = 1; i < points.length; i++) {
      if (points[i].cumulativeDistanceM <= progressDist) {
        final c = toCanvas(points[i]);
        activePath.lineTo(c.dx, c.dy);
        dotPos = c;
      } else {
        // Interpolate the final segment
        final prev = points[i - 1];
        final segLen =
            points[i].cumulativeDistanceM - prev.cumulativeDistanceM;
        if (segLen > 0) {
          final t = (progressDist - prev.cumulativeDistanceM) / segLen;
          final from = toCanvas(prev);
          final to = toCanvas(points[i]);
          dotPos = Offset.lerp(from, to, t.clamp(0.0, 1.0))!;
          activePath.lineTo(dotPos.dx, dotPos.dy);
        }
        break;
      }
    }

    // Glow under the active path
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.red.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawPath(activePath, glowPaint);

    // Active path line
    final activePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.red;
    canvas.drawPath(activePath, activePaint);

    // Progress dot
    canvas.drawCircle(dotPos, 5, Paint()..color = Colors.red);
    canvas.drawCircle(
      dotPos,
      8,
      Paint()
        ..color = Colors.red.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
  }

  @override
  bool shouldRepaint(covariant _GpxRoutePainter old) =>
      old.progress != progress;
}

// ── Shared progress dot ──

void _drawProgressDot(Canvas canvas, Size size, double x, double vPad) {
  // Vertical guide line
  final guidePaint = Paint()
    ..color = Colors.red.withValues(alpha: 0.25)
    ..strokeWidth = 1;
  canvas.drawLine(
    Offset(x, vPad),
    Offset(x, size.height - vPad),
    guidePaint,
  );

  // Red dot
  final dotPaint = Paint()..color = Colors.red;
  canvas.drawCircle(Offset(x, size.height - vPad), 5, dotPaint);

  // Glow
  final glowPaint = Paint()
    ..color = Colors.red.withValues(alpha: 0.3)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
  canvas.drawCircle(Offset(x, size.height - vPad), 7, glowPaint);
}
