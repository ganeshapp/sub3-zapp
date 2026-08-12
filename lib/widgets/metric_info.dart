import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Plain-language explanations of the numbers Sub3 puts on screen, so a
/// runner never has to guess what a metric means.
///
/// One glossary, shared by the summary tiles, the live dashboard and
/// anything added later. Keys are stable; the copy is deliberately jargon
/// free.
class MetricInfo {
  const MetricInfo._();

  static const pace = 'pace';
  static const avgPace = 'avgPace';
  static const avgSpeed = 'avgSpeed';
  static const cadence = 'cadence';
  static const elevationGain = 'elevationGain';
  static const incline = 'incline';
  static const heartRate = 'hr';

  static const Map<String, (String title, String body)> glossary = {
    pace: (
      'Pace',
      'How long it takes you to cover one kilometre. Lower is faster.',
    ),
    avgPace: (
      'Avg Pace',
      'Your pace across the whole run. Paused time is left out.',
    ),
    avgSpeed: (
      'Avg Speed',
      'Your average belt speed in km/h. Pace says the same thing the other '
          'way round.',
    ),
    cadence: (
      'Cadence',
      'Steps per minute, counting both feet. Most runners land between 160 '
          'and 180.',
    ),
    elevationGain: (
      'Elev. Gain',
      "Total metres climbed, from the route's hills or the treadmill's "
          'incline.',
    ),
    incline: (
      'Incline',
      'How steep the belt is, as a percentage. About 1% matches the effort '
          'of running outdoors.',
    ),
    heartRate: (
      'Avg / Max HR',
      'Your average and highest heart rate for the run.',
    ),
  };

  static bool has(String? key) => key != null && glossary.containsKey(key);
}

/// Open the plain-language explanation of [key]. Does nothing for a metric
/// with no glossary entry, so call sites can pass a key unconditionally.
Future<void> showMetricInfo(BuildContext context, String? key) async {
  final entry = key == null ? null : MetricInfo.glossary[key];
  if (entry == null) return;

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF2C2C2C),
      title: Text(
        entry.$1,
        style: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      content: Text(
        entry.$2,
        style: GoogleFonts.inter(
          fontSize: 14,
          height: 1.45,
          color: Colors.white70,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
}

/// The small `(?)` next to a metric label — the visual cue that tapping
/// explains what the number means.
class MetricInfoCue extends StatelessWidget {
  final double size;

  const MetricInfoCue({super.key, this.size = 12});

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.help_outline,
      size: size,
      color: Colors.white24,
    );
  }
}
