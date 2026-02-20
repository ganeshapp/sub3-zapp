import 'dart:convert';
import 'package:http/http.dart' as http;

class GitHubFile {
  final String name;
  final String downloadUrl;
  final String sha;

  const GitHubFile({
    required this.name,
    required this.downloadUrl,
    required this.sha,
  });

  factory GitHubFile.fromJson(Map<String, dynamic> json) {
    return GitHubFile(
      name: json['name'] as String,
      downloadUrl: json['download_url'] as String,
      sha: json['sha'] as String? ?? '',
    );
  }
}

class GitHubService {
  static const _baseUrl =
      'https://api.github.com/repos/ganeshapp/sub3/contents/contents';

  static Future<List<GitHubFile>> fetchWorkouts() async {
    return _fetchDirectory('$_baseUrl/workouts');
  }

  static Future<List<GitHubFile>> fetchVirtualRuns() async {
    return _fetchDirectory('$_baseUrl/virtualrun');
  }

  static Future<List<GitHubFile>> _fetchDirectory(String url) async {
    final response = await http.get(
      Uri.parse(url),
      headers: {'Accept': 'application/vnd.github.v3+json'},
    );

    if (response.statusCode != 200) {
      throw Exception('GitHub API error: ${response.statusCode}');
    }

    final List<dynamic> items = jsonDecode(response.body);
    return items
        .where((item) => item['type'] == 'file')
        .map((item) => GitHubFile.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  static Future<String> downloadFileContent(String downloadUrl) async {
    final response = await http.get(Uri.parse(downloadUrl));
    if (response.statusCode != 200) {
      throw Exception('Download failed: ${response.statusCode}');
    }
    return response.body;
  }
}
