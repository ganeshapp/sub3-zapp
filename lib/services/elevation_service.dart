import 'dart:convert';
import 'package:http/http.dart' as http;

/// Fetches elevation data for lat/lon coordinates using the
/// Open-Elevation API (free, no API key required).
class ElevationService {
  static const _url = 'https://api.open-elevation.com/api/v1/lookup';
  static const _batchSize = 100;

  /// Returns a list of elevations (meters) for the given coordinates.
  /// Falls back to null if the API is unreachable.
  static Future<List<double>?> fetchElevations(
      List<({double lat, double lon})> coords) async {
    if (coords.isEmpty) return [];

    final results = List<double>.filled(coords.length, 0);

    for (var start = 0; start < coords.length; start += _batchSize) {
      final end =
          (start + _batchSize).clamp(0, coords.length);
      final batch = coords.sublist(start, end);

      final body = jsonEncode({
        'locations': batch
            .map((c) => {'latitude': c.lat, 'longitude': c.lon})
            .toList(),
      });

      try {
        final resp = await http
            .post(Uri.parse(_url),
                headers: {'Content-Type': 'application/json'}, body: body)
            .timeout(const Duration(seconds: 30));

        if (resp.statusCode != 200) return null;

        final json = jsonDecode(resp.body);
        final apiResults = json['results'] as List<dynamic>;

        for (var i = 0; i < apiResults.length; i++) {
          results[start + i] =
              (apiResults[i]['elevation'] as num).toDouble();
        }
      } catch (_) {
        return null;
      }
    }

    return results;
  }
}
