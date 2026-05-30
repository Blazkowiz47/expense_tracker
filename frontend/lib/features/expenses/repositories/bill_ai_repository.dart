import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:expense_tracker/core/auth/auth_token_provider.dart';
import 'package:expense_tracker/core/config/api_config.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class BillExtractionResult {
  const BillExtractionResult({
    required this.merchant,
    required this.amount,
    required this.date,
    required this.category,
    required this.notes,
    required this.confidence,
    required this.warnings,
  });

  final String merchant;
  final double amount;
  final DateTime date;
  final String category;
  final String notes;
  final double confidence;
  final List<String> warnings;

  factory BillExtractionResult.fromJson(Map<String, dynamic> json) {
    return BillExtractionResult(
      merchant: (json['merchant'] as String?) ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      date:
          DateTime.tryParse((json['date'] as String?) ?? '') ?? DateTime.now(),
      category: (json['category'] as String?) ?? 'Personal',
      notes: (json['notes'] as String?) ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      warnings: (json['warnings'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(growable: false),
    );
  }
}

class BillAiRepository {
  BillAiRepository({http.Client? client, AuthTokenProvider? authTokenProvider})
    : _client = client ?? http.Client(),
      _authTokenProvider =
          authTokenProvider ?? const SessionAuthTokenProvider();

  final http.Client _client;
  final AuthTokenProvider _authTokenProvider;

  Future<BillExtractionResult> uploadAndWait({
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  }) async {
    final token = await _authTokenProvider.getBearerToken();
    final request =
        http.MultipartRequest(
            'POST',
            Uri.parse('${ApiConfig.baseUrl}/api/v1/bills'),
          )
          ..headers['Accept'] = 'application/json'
          ..headers['Authorization'] = 'Bearer $token'
          ..files.add(
            http.MultipartFile.fromBytes(
              'file',
              bytes,
              filename: fileName,
              contentType: MediaType.parse(contentType),
            ),
          );
    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 201) {
      throw Exception(
        'Bill upload failed (${response.statusCode}): ${response.body}',
      );
    }
    final job = jsonDecode(response.body) as Map<String, dynamic>;
    final jobId = job['id'] as String;
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      final poll = await _client.get(
        Uri.parse('${ApiConfig.baseUrl}/api/v1/bills/$jobId'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (poll.statusCode != 200) {
        throw Exception(
          'Bill extraction status failed (${poll.statusCode}): ${poll.body}',
        );
      }
      final payload = jsonDecode(poll.body) as Map<String, dynamic>;
      if (payload['status'] == 'completed') {
        return BillExtractionResult.fromJson(
          payload['result'] as Map<String, dynamic>,
        );
      }
      if (payload['status'] == 'failed') {
        throw Exception(payload['error'] ?? 'Bill extraction failed');
      }
    }
    throw TimeoutException('Bill extraction timed out.');
  }
}
