import 'package:expense_tracker/core/auth/auth_token_provider.dart';
import 'dart:convert';

import 'package:expense_tracker/core/config/api_config.dart';
import 'package:expense_tracker/features/dashboard/models/dashboard_snapshot.dart';
import 'package:expense_tracker/features/dashboard/repositories/dashboard_snapshot_repository.dart';
import 'package:http/http.dart' as http;

class ApiDashboardSnapshotRepository implements DashboardSnapshotRepository {
  ApiDashboardSnapshotRepository({
    required http.Client client,
    AuthTokenProvider? authTokenProvider,
  }) : _client = client,
       _authTokenProvider =
           authTokenProvider ?? const FirebaseAuthTokenProvider();

  final http.Client _client;
  final AuthTokenProvider _authTokenProvider;

  @override
  Future<DashboardSnapshot> fetchSnapshot() async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/v1/dashboard/snapshot');
    final token = await _authTokenProvider.getBearerToken();
    final response = await _client.get(
      uri,
      headers: <String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        'snapshot request failed (${response.statusCode}): ${response.body}',
      );
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return DashboardSnapshot.fromJson(payload);
  }
}
