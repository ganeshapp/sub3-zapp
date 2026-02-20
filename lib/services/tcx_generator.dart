import '../models/telemetry.dart';

/// Generates a strict TCX XML string from the 1-second telemetry array.
///
/// Follows the Garmin TrainingCenterDatabase/v2 schema with the
/// ActivityExtension/v2 namespace for Speed and RunCadence.
/// Creator Name includes "with barometer" to force Strava to trust
/// the app's elevation data.
class TcxGenerator {
  static String generate({
    required DateTime startTime,
    required List<TelemetryPoint> telemetry,
    required double totalDistanceM,
    required int totalTimeSeconds,
  }) {
    final startUtc = startTime.toUtc();
    final buf = StringBuffer();

    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buf.writeln('<TrainingCenterDatabase');
    buf.writeln(
        '  xsi:schemaLocation="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2'
        ' http://www.garmin.com/xmlschemas/TrainingCenterDatabasev2.xsd'
        ' http://www.garmin.com/xmlschemas/ActivityExtension/v2'
        ' http://www.garmin.com/xmlschemas/ActivityExtensionv2.xsd"');
    buf.writeln(
        '  xmlns:ns5="http://www.garmin.com/xmlschemas/ActivityExtension/v2"');
    buf.writeln(
        '  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"');
    buf.writeln(
        '  xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">');

    buf.writeln('  <Activities>');
    buf.writeln('    <Activity Sport="Running">');
    buf.writeln('      <Id>${_fmtTime(startUtc)}</Id>');
    buf.writeln('      <Creator xsi:type="Device_t">');
    buf.writeln('        <Name>Sub3 App with barometer</Name>');
    buf.writeln('      </Creator>');

    buf.writeln(
        '      <Lap StartTime="${_fmtTime(startUtc)}">');
    buf.writeln(
        '        <TotalTimeSeconds>${totalTimeSeconds.toDouble()}</TotalTimeSeconds>');
    buf.writeln(
        '        <DistanceMeters>${totalDistanceM.toStringAsFixed(1)}</DistanceMeters>');
    buf.writeln('        <Intensity>Active</Intensity>');
    buf.writeln('        <TriggerMethod>Manual</TriggerMethod>');
    buf.writeln('        <Track>');

    for (final tp in telemetry) {
      final pointTime =
          startUtc.add(Duration(seconds: tp.elapsedSeconds));
      final distM = tp.cumulativeDistanceKm * 1000;
      final speedMs = tp.speedKmh / 3.6; // km/h → m/s

      buf.writeln('          <Trackpoint>');
      buf.writeln(
          '            <Time>${_fmtTime(pointTime)}</Time>');
      buf.writeln(
          '            <DistanceMeters>${distM.toStringAsFixed(1)}</DistanceMeters>');

      if (tp.heartRate != null && tp.heartRate! > 0) {
        buf.writeln('            <HeartRateBpm>');
        buf.writeln(
            '              <Value>${tp.heartRate!.round()}</Value>');
        buf.writeln('            </HeartRateBpm>');
      }

      buf.writeln('            <Extensions>');
      buf.writeln(
          '              <TPX xmlns="http://www.garmin.com/xmlschemas/ActivityExtension/v2">');
      buf.writeln(
          '                <Speed>${speedMs.toStringAsFixed(2)}</Speed>');
      if (tp.cadence != null && tp.cadence! > 0) {
        buf.writeln(
            '                <RunCadence>${tp.cadence}</RunCadence>');
      }
      buf.writeln('              </TPX>');
      buf.writeln('            </Extensions>');
      buf.writeln('          </Trackpoint>');
    }

    buf.writeln('        </Track>');
    buf.writeln('      </Lap>');
    buf.writeln('    </Activity>');
    buf.writeln('  </Activities>');
    buf.writeln('</TrainingCenterDatabase>');

    return buf.toString();
  }

  /// ISO 8601 UTC with milliseconds: `2024-01-01T12:00:00.000Z`
  static String _fmtTime(DateTime utc) {
    return '${utc.year.toString().padLeft(4, '0')}'
        '-${utc.month.toString().padLeft(2, '0')}'
        '-${utc.day.toString().padLeft(2, '0')}'
        'T${utc.hour.toString().padLeft(2, '0')}'
        ':${utc.minute.toString().padLeft(2, '0')}'
        ':${utc.second.toString().padLeft(2, '0')}'
        '.${utc.millisecond.toString().padLeft(3, '0')}Z';
  }
}
