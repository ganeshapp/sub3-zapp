import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class StravaConfig {
  static const clientId = 'YOUR_STRAVA_CLIENT_ID';
  static const clientSecret = 'YOUR_STRAVA_CLIENT_SECRET';
  static const redirectUri = 'sub3://strava/callback';
  static const authUrl = 'https://www.strava.com/oauth/authorize';
  static const tokenUrl = 'https://www.strava.com/oauth/token';
  static const uploadUrl = 'https://www.strava.com/api/v3/uploads';
}

class StravaService {
  static const _keyAccessToken = 'strava_access_token';
  static const _keyRefreshToken = 'strava_refresh_token';
  static const _keyExpiresAt = 'strava_expires_at';
  static const _keyAthleteId = 'strava_athlete_id';

  // ── Token storage ──

  static Future<bool> get isLinked async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyAccessToken) != null;
  }

  static Future<String?> get accessToken async {
    final prefs = await SharedPreferences.getInstance();
    final expiresAt = prefs.getInt(_keyExpiresAt) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    if (now >= expiresAt) {
      return _refreshToken();
    }
    return prefs.getString(_keyAccessToken);
  }

  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    required int expiresAt,
    int? athleteId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAccessToken, accessToken);
    await prefs.setString(_keyRefreshToken, refreshToken);
    await prefs.setInt(_keyExpiresAt, expiresAt);
    if (athleteId != null) {
      await prefs.setInt(_keyAthleteId, athleteId);
    }
  }

  static Future<void> clearTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAccessToken);
    await prefs.remove(_keyRefreshToken);
    await prefs.remove(_keyExpiresAt);
    await prefs.remove(_keyAthleteId);
  }

  // ── OAuth flow ──

  static Future<void> launchOAuth() async {
    final uri = Uri.parse(StravaConfig.authUrl).replace(queryParameters: {
      'client_id': StravaConfig.clientId,
      'redirect_uri': StravaConfig.redirectUri,
      'response_type': 'code',
      'scope': 'activity:write',
      'approval_prompt': 'auto',
    });
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Exchange the authorization code for access + refresh tokens.
  static Future<bool> exchangeCode(String code) async {
    final response = await http.post(
      Uri.parse(StravaConfig.tokenUrl),
      body: {
        'client_id': StravaConfig.clientId,
        'client_secret': StravaConfig.clientSecret,
        'code': code,
        'grant_type': 'authorization_code',
      },
    );

    if (response.statusCode != 200) return false;

    final json = jsonDecode(response.body);
    await saveTokens(
      accessToken: json['access_token'],
      refreshToken: json['refresh_token'],
      expiresAt: json['expires_at'],
      athleteId: json['athlete']?['id'],
    );
    return true;
  }

  static Future<String?> _refreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    final refresh = prefs.getString(_keyRefreshToken);
    if (refresh == null) return null;

    final response = await http.post(
      Uri.parse(StravaConfig.tokenUrl),
      body: {
        'client_id': StravaConfig.clientId,
        'client_secret': StravaConfig.clientSecret,
        'refresh_token': refresh,
        'grant_type': 'refresh_token',
      },
    );

    if (response.statusCode != 200) return null;

    final json = jsonDecode(response.body);
    await saveTokens(
      accessToken: json['access_token'],
      refreshToken: json['refresh_token'],
      expiresAt: json['expires_at'],
    );
    return json['access_token'];
  }

  // ── Upload TCX ──

  /// Uploads a TCX string to Strava.
  /// Returns the upload ID on success, throws on failure.
  static Future<int> uploadTcx({
    required String tcxContent,
    required String activityName,
  }) async {
    final token = await accessToken;
    if (token == null) {
      throw Exception('Not authenticated with Strava');
    }

    final request = http.MultipartRequest('POST', Uri.parse(StravaConfig.uploadUrl))
      ..headers['Authorization'] = 'Bearer $token'
      ..fields['data_type'] = 'tcx'
      ..fields['trainer'] = '1'
      ..fields['sport_type'] = 'VirtualRun'
      ..fields['name'] = activityName
      ..fields['description'] = 'Uploaded from Sub3 App'
      ..files.add(http.MultipartFile.fromString(
        'file',
        tcxContent,
        filename: '${activityName.replaceAll(' ', '_')}.tcx',
      ));

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode == 201) {
      final json = jsonDecode(response.body);
      return json['id'] as int;
    }

    throw Exception(
        'Strava upload failed (${response.statusCode}): ${response.body}');
  }
}
