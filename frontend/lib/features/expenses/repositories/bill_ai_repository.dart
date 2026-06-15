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
    required this.dateExtracted,
    required this.currency,
    required this.category,
    required this.notes,
    required this.lineItems,
    required this.confidence,
    required this.warnings,
  });

  final String merchant;
  final double amount;
  final DateTime date;
  final bool dateExtracted;
  final String currency;
  final String category;
  final String notes;
  final List<BillLineItem> lineItems;
  final double confidence;
  final List<String> warnings;

  factory BillExtractionResult.fromJson(Map<String, dynamic> json) {
    final parsedDate = DateTime.tryParse((json['date'] as String?) ?? '');
    return BillExtractionResult(
      merchant: (json['merchant'] as String?) ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      date: parsedDate ?? DateTime.now(),
      dateExtracted: parsedDate != null,
      currency: (json['currency'] as String?) ?? 'INR',
      category: (json['category'] as String?) ?? 'Personal',
      notes: (json['notes'] as String?) ?? '',
      lineItems: (json['lineItems'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(BillLineItem.fromJson)
          .toList(growable: false),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      warnings: (json['warnings'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(growable: false),
    );
  }
}

class BillLineItem {
  const BillLineItem({
    required this.name,
    this.originalText = '',
    this.detectedLanguage = '',
    this.normalizedName = '',
    this.brand = '',
    this.quantity,
    this.unit = '',
    this.unitPrice,
    this.lineTotal,
    this.discount,
    this.normalizedQuantity,
    this.normalizedUnit = '',
    this.unitPriceNormalized,
    this.category = '',
    this.confidence = 0,
  });

  final String name;
  final String originalText;
  final String detectedLanguage;
  final String normalizedName;
  final String brand;
  final double? quantity;
  final String unit;
  final double? unitPrice;
  final double? lineTotal;
  final double? discount;
  final double? normalizedQuantity;
  final String normalizedUnit;
  final double? unitPriceNormalized;
  final String category;
  final double confidence;

  double? get amount => lineTotal;

  factory BillLineItem.fromJson(Map<String, dynamic> json) {
    final name = (json['itemName'] ?? json['name'] ?? json['title'] ?? '')
        .toString();
    final originalText = (json['originalText'] ?? json['rawText'] ?? name)
        .toString();
    return BillLineItem(
      name: name,
      originalText: originalText,
      detectedLanguage: (json['detectedLanguage'] ?? json['language'] ?? '')
          .toString(),
      normalizedName: (json['normalizedName'] ?? '').toString(),
      brand: (json['brand'] ?? '').toString(),
      quantity: _readDouble(json['quantity']),
      unit: (json['unit'] ?? '').toString(),
      unitPrice: _readDouble(json['unitPrice']),
      lineTotal: _readDouble(json['lineTotal'] ?? json['amount']),
      discount: _readDouble(json['discount']),
      normalizedQuantity: _readDouble(json['normalizedQuantity']),
      normalizedUnit: (json['normalizedUnit'] ?? '').toString(),
      unitPriceNormalized: _readDouble(json['unitPriceNormalized']),
      category: (json['category'] ?? '').toString(),
      confidence: _readDouble(json['confidence']) ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'originalText': originalText.trim().isEmpty ? name : originalText,
      'detectedLanguage': detectedLanguage,
      'itemName': name,
      'normalizedName': normalizedName,
      'brand': brand,
      'quantity': quantity,
      'unit': unit,
      'unitPrice': unitPrice,
      'lineTotal': lineTotal,
      'discount': discount,
      'normalizedQuantity': normalizedQuantity,
      'normalizedUnit': normalizedUnit,
      'unitPriceNormalized': unitPriceNormalized,
      'category': category,
      'confidence': confidence,
    };
  }

  BillLineItem copyWith({
    String? name,
    String? originalText,
    String? detectedLanguage,
    String? normalizedName,
    String? brand,
    Object? quantity = _unset,
    String? unit,
    Object? unitPrice = _unset,
    Object? lineTotal = _unset,
    Object? discount = _unset,
    Object? normalizedQuantity = _unset,
    String? normalizedUnit,
    Object? unitPriceNormalized = _unset,
    String? category,
    double? confidence,
  }) {
    return BillLineItem(
      name: name ?? this.name,
      originalText: originalText ?? this.originalText,
      detectedLanguage: detectedLanguage ?? this.detectedLanguage,
      normalizedName: normalizedName ?? this.normalizedName,
      brand: brand ?? this.brand,
      quantity: identical(quantity, _unset)
          ? this.quantity
          : quantity as double?,
      unit: unit ?? this.unit,
      unitPrice: identical(unitPrice, _unset)
          ? this.unitPrice
          : unitPrice as double?,
      lineTotal: identical(lineTotal, _unset)
          ? this.lineTotal
          : lineTotal as double?,
      discount: identical(discount, _unset)
          ? this.discount
          : discount as double?,
      normalizedQuantity: identical(normalizedQuantity, _unset)
          ? this.normalizedQuantity
          : normalizedQuantity as double?,
      normalizedUnit: normalizedUnit ?? this.normalizedUnit,
      unitPriceNormalized: identical(unitPriceNormalized, _unset)
          ? this.unitPriceNormalized
          : unitPriceNormalized as double?,
      category: category ?? this.category,
      confidence: confidence ?? this.confidence,
    );
  }
}

const _unset = Object();

double? _readDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value.trim().replaceAll(',', '.'));
  }
  return null;
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
