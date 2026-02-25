import 'dart:convert';

import 'package:expense_tracker/core/config/api_config.dart';
import 'package:expense_tracker/core/theme/theme_pack.dart';
import 'package:http/http.dart' as http;

class ThemePackRepository {
  ThemePackRepository({required http.Client client}) : _client = client;

  final http.Client _client;

  Future<List<ThemePack>> fetchRemoteThemePacks() async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/theme-packs');
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      return const [];
    }

    final data = jsonDecode(response.body);
    if (data is! List) {
      return const [];
    }

    return data
        .whereType<Map<String, dynamic>>()
        .map(ThemePack.fromJson)
        .toList(growable: false);
  }
}
