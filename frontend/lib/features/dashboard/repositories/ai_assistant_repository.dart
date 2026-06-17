import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:expense_tracker/core/auth/auth_token_provider.dart';
import 'package:expense_tracker/core/config/api_config.dart';
import 'package:http/http.dart' as http;

class AiPlanResult extends Equatable {
  const AiPlanResult({
    required this.question,
    required this.title,
    required this.answer,
    required this.steps,
    required this.suggestions,
    required this.warnings,
  });

  final String question;
  final String title;
  final String answer;
  final List<String> steps;
  final List<String> suggestions;
  final List<String> warnings;

  factory AiPlanResult.fromJson(Map<String, dynamic> json) {
    List<String> readList(String key) {
      final raw = json[key];
      if (raw is! List) return const [];
      return raw
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }

    return AiPlanResult(
      question: (json['question'] ?? '').toString(),
      title: (json['title'] ?? 'AI plan').toString(),
      answer: (json['answer'] ?? '').toString(),
      steps: readList('steps'),
      suggestions: readList('suggestions'),
      warnings: readList('warnings'),
    );
  }

  @override
  List<Object?> get props => [
    question,
    title,
    answer,
    steps,
    suggestions,
    warnings,
  ];
}

class AiAssistantRepository {
  AiAssistantRepository({
    http.Client? client,
    AuthTokenProvider? authTokenProvider,
  }) : _client = client ?? http.Client(),
       _authTokenProvider =
           authTokenProvider ?? const SessionAuthTokenProvider();

  final http.Client _client;
  final AuthTokenProvider _authTokenProvider;

  Future<AiPlanResult> ask(String question) async {
    final token = await _authTokenProvider.getBearerToken();
    final response = await _client.post(
      Uri.parse('${ApiConfig.baseUrl}/api/v1/ai/chat'),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'question': question}),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'AI request failed (${response.statusCode}): ${response.body}',
      );
    }
    return AiPlanResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }
}
