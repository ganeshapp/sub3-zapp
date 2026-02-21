import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

class StravaService {
  static const _storage = FlutterSecureStorage();

  static const _keyAccessToken = 'strava_access_token';
  static const _keyRefreshToken = 'strava_refresh_token';
  static const _keyExpiresAt = 'strava_expires_at';

  static const _redirectUri = 'sub3://sub3.app/callback';
  static const _authUrl = 'https://www.strava.com/oauth/authorize';
  static const _tokenUrl = 'https://www.strava.com/oauth/token';
  static const _uploadUrl = 'https://www.strava.com/api/v3/uploads';

  static String get _clientId => dotenv.env['STRAVA_CLIENT_ID'] ?? '';
  static String get _clientSecret => dotenv.env['STRAVA_CLIENT_SECRET'] ?? '';

  // ── Token checks ──

  static Future<bool> get isLinked async {
    final token = await _storage.read(key: _keyAccessToken);
    return token != null && token.isNotEmpty;
  }

  static Future<String?> get accessToken async {
    final expiresStr = await _storage.read(key: _keyExpiresAt);
    final expiresAt = int.tryParse(expiresStr ?? '') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    if (now >= expiresAt) {
      return _refreshToken();
    }
    return _storage.read(key: _keyAccessToken);
  }

  // ── OAuth Authorization Code flow ──

  static Future<bool> launchOAuth() async {
    if (_clientId.isEmpty || _clientSecret.isEmpty) {
      throw Exception(
        'Strava credentials not configured. '
        'Set STRAVA_CLIENT_ID and STRAVA_CLIENT_SECRET in .env',
      );
    }

    final authUri = Uri.parse(_authUrl).replace(queryParameters: {
      'client_id': _clientId,
      'redirect_uri': _redirectUri,
      'response_type': 'code',
      'scope': 'activity:write,read',
      'approval_prompt': 'auto',
    });

    final resultUrl = await FlutterWebAuth2.authenticate(
      url: authUri.toString(),
      callbackUrlScheme: 'sub3',
    );

    final code = Uri.parse(resultUrl).queryParameters['code'];
    if (code == null || code.isEmpty) return false;

    return _exchangeCode(code);
  }

  static Future<bool> _exchangeCode(String code) async {
    final response = await http.post(
      Uri.parse(_tokenUrl),
      body: {
        'client_id': _clientId,
        'client_secret': _clientSecret,
        'code': code,
        'grant_type': 'authorization_code',
      },
    );

    if (response.statusCode != 200) return false;

    final json = jsonDecode(response.body);
    await _saveTokens(
      accessToken: json['access_token'],
      refreshToken: json['refresh_token'],
      expiresAt: json['expires_at'],
    );
    return true;
  }

  // ── Token refresh ──

  static Future<String?> _refreshToken() async {
    final refresh = await _storage.read(key: _keyRefreshToken);
    if (refresh == null) return null;

    final response = await http.post(
      Uri.parse(_tokenUrl),
      body: {
        'client_id': _clientId,
        'client_secret': _clientSecret,
        'refresh_token': refresh,
        'grant_type': 'refresh_token',
      },
    );

    if (response.statusCode != 200) return null;

    final json = jsonDecode(response.body);
    await _saveTokens(
      accessToken: json['access_token'],
      refreshToken: json['refresh_token'],
      expiresAt: json['expires_at'],
    );
    return json['access_token'];
  }

  // ── Token persistence (secure storage) ──

  static Future<void> _saveTokens({
    required String accessToken,
    required String refreshToken,
    required int expiresAt,
  }) async {
    await _storage.write(key: _keyAccessToken, value: accessToken);
    await _storage.write(key: _keyRefreshToken, value: refreshToken);
    await _storage.write(key: _keyExpiresAt, value: expiresAt.toString());
  }

  static Future<void> clearTokens() async {
    await _storage.delete(key: _keyAccessToken);
    await _storage.delete(key: _keyRefreshToken);
    await _storage.delete(key: _keyExpiresAt);
  }

  // ── Upload TCX ──

  static Future<int> uploadTcx({
    required String tcxContent,
    required String activityName,
  }) async {
    final token = await accessToken;
    if (token == null) {
      throw Exception('Not authenticated with Strava');
    }

    final request = http.MultipartRequest('POST', Uri.parse(_uploadUrl))
      ..headers['Authorization'] = 'Bearer $token'
      ..fields['data_type'] = 'tcx'
      ..fields['sport_type'] = 'VirtualRun'
      ..fields['name'] = activityName
      ..fields['description'] = 'Uploaded from Sub3'
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
