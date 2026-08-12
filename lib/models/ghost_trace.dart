import 'dart:convert';
import 'dart:math';

/// The distance trace of the best-ever run on a route — the "ghost" a runner
/// races against.
///
/// Stored as JSON in `library_items.pr_trace`:
/// `{"v":1,"step":3,"total":5000,"m":[0,8.2, ...]}` — cumulative metres, one
/// sample per second, thinned to at most [maxSamples] points by keeping every
/// `step`-th second. The last sample is always the real finish, and `total`
/// is the run's elapsed seconds, so the final segment is timed correctly even
/// when the run length is not a whole number of steps.
class GhostTrace {
  /// A trace never holds more than this many points, so an hours-long run
  /// still costs only a few kilobytes in the library row.
  static const maxSamples = 1800;

  /// Seconds between consecutive samples.
  final int stepSeconds;

  /// Elapsed seconds of the final sample — the PR time.
  final int totalSeconds;

  /// Cumulative metres, sample `i` taken at [timeOf] `i`.
  final List<double> metres;

  const GhostTrace({
    required this.stepSeconds,
    required this.totalSeconds,
    required this.metres,
  });

  /// Total metres the ghost covered.
  double get totalMetres => metres.last;

  /// Seconds at which sample [i] was taken.
  double timeOf(int i) =>
      i >= metres.length - 1 ? totalSeconds.toDouble() : (i * stepSeconds).toDouble();

  // ── Build / encode / decode ──

  /// Build a trace from a finished run's per-second cumulative distances in
  /// metres, index `i` being second `i`. Returns null for a run too short to
  /// race against.
  static GhostTrace? fromDistances(List<double> perSecondMetres) {
    if (perSecondMetres.length < 2) return null;
    final lastIndex = perSecondMetres.length - 1;
    final step = max(1, (lastIndex / (maxSamples - 1)).ceil());

    final samples = <double>[];
    for (var i = 0; i < lastIndex; i += step) {
      samples.add(_round1(perSecondMetres[i]));
    }
    // The finish is always kept, whatever the step works out to.
    samples.add(_round1(perSecondMetres[lastIndex]));

    return GhostTrace(
      stepSeconds: step,
      totalSeconds: lastIndex,
      metres: samples,
    );
  }

  String toJson() => jsonEncode({
        'v': 1,
        'step': stepSeconds,
        'total': totalSeconds,
        'm': metres,
      });

  /// Decode a stored trace. Returns null for anything unusable — a missing
  /// column, corrupt JSON, or a trace too short to race — so a broken value
  /// can never take a run down with it.
  static GhostTrace? decode(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final decoded = jsonDecode(json);

      // A bare array is read as one sample per second (step 1).
      if (decoded is List) {
        final m = _metresOf(decoded);
        if (m == null) return null;
        return GhostTrace(
          stepSeconds: 1,
          totalSeconds: m.length - 1,
          metres: m,
        );
      }

      if (decoded is! Map) return null;
      final m = _metresOf(decoded['m']);
      if (m == null) return null;
      final step = (decoded['step'] as num?)?.toInt() ?? 1;
      if (step < 1) return null;
      final total =
          (decoded['total'] as num?)?.toInt() ?? (m.length - 1) * step;
      if (total < 1) return null;
      return GhostTrace(stepSeconds: step, totalSeconds: total, metres: m);
    } catch (_) {
      return null;
    }
  }

  static List<double>? _metresOf(dynamic raw) {
    if (raw is! List || raw.length < 2) return null;
    final out = <double>[];
    for (final v in raw) {
      if (v is! num) return null;
      out.add(v.toDouble());
    }
    return out;
  }

  static double _round1(double v) => (v * 10).roundToDouble() / 10;

  // ── Lookup ──

  /// How far the ghost had run at [elapsedSeconds]. Once its trace ends the
  /// ghost freezes at the finish line.
  double distanceAt(num elapsedSeconds) {
    if (elapsedSeconds <= 0) return metres.first;
    if (elapsedSeconds >= totalSeconds) return metres.last;

    final i = min(elapsedSeconds ~/ stepSeconds, metres.length - 2);
    final t0 = timeOf(i);
    final t1 = timeOf(i + 1);
    if (t1 <= t0) return metres[i];
    final f = ((elapsedSeconds - t0) / (t1 - t0)).clamp(0.0, 1.0);
    return metres[i] + (metres[i + 1] - metres[i]) * f;
  }

  /// The second at which the ghost passed [distanceM]. Null once you are
  /// further along the route than the ghost ever got.
  double? timeAtDistance(double distanceM) {
    if (distanceM <= metres.first) return 0;
    if (distanceM > metres.last) return null;

    for (var i = 1; i < metres.length; i++) {
      if (metres[i] >= distanceM) {
        final segM = metres[i] - metres[i - 1];
        final t0 = timeOf(i - 1);
        if (segM <= 0) return t0;
        final f = ((distanceM - metres[i - 1]) / segM).clamp(0.0, 1.0);
        return t0 + (timeOf(i) - t0) * f;
      }
    }
    return timeOf(metres.length - 1);
  }

  /// Seconds you are ahead (positive) or behind (negative) the ghost, judged
  /// at the distance you have covered — the ghost passed here at
  /// [timeAtDistance], you passed it at [elapsedSeconds]. Null once you are
  /// past the ghost's furthest point.
  double? deltaAt({required int elapsedSeconds, required double distanceM}) {
    final ghostTime = timeAtDistance(distanceM);
    if (ghostTime == null) return null;
    return ghostTime - elapsedSeconds;
  }

  /// True once the ghost has run out of trace at [elapsedSeconds] — it has
  /// finished the route and is standing at the line.
  bool hasFinishedBy(int elapsedSeconds) => elapsedSeconds >= totalSeconds;
}
