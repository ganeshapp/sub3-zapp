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
            ? _GpxProfilePainter(
                points: workoutFile.gpxPoints ?? [],
                smoothed: workoutFile.smoothedElevations ?? [],
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

// ── GPX Elevation Profile ──

class _GpxProfilePainter extends CustomPainter {
  final List<GpxPoint> points;
  final List<double> smoothed;
  final double progress;

  _GpxProfilePainter({
    required this.points,
    required this.smoothed,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2 || smoothed.length < 2) return;

    const hPad = 8.0;
    const vPad = 16.0;
    final drawW = size.width - hPad * 2;
    final drawH = size.height - vPad * 2;

    final totalDist = points.last.cumulativeDistanceM;
    if (totalDist <= 0) return;

    final minEle = smoothed.reduce(min);
    final maxEle = smoothed.reduce(max);
    final eleRange = (maxEle - minEle).clamp(1.0, double.infinity);

    // Build path
    final path = Path();
    final fillPath = Path();

    for (var i = 0; i < points.length; i++) {
      final x = hPad +
          (points[i].cumulativeDistanceM / totalDist) * drawW;
      final y = size.height -
          vPad -
          ((smoothed[i] - minEle) / eleRange) * drawH;

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height - vPad);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    // Close fill
    fillPath.lineTo(hPad + drawW, size.height - vPad);
    fillPath.close();

    // Draw fill
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.12),
          Colors.white.withValues(alpha: 0.02),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    // Draw line
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white.withValues(alpha: 0.35);
    canvas.drawPath(path, linePaint);

    // Progress dot
    final dotX = hPad + progress.clamp(0.0, 1.0) * drawW;
    _drawProgressDot(canvas, size, dotX, vPad);
  }

  @override
  bool shouldRepaint(covariant _GpxProfilePainter old) =>
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
