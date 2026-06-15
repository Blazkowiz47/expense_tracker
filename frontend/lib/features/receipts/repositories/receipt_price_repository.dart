import 'dart:convert';

import 'package:expense_tracker/core/auth/auth_token_provider.dart';
import 'package:expense_tracker/core/config/api_config.dart';
import 'package:http/http.dart' as http;

class ReceiptPriceComparison {
  const ReceiptPriceComparison({
    required this.query,
    required this.normalizedName,
    required this.summaryByCurrency,
    required this.items,
  });

  final String query;
  final String normalizedName;
  final List<ReceiptPriceSummary> summaryByCurrency;
  final List<ReceiptPriceItem> items;

  factory ReceiptPriceComparison.fromJson(Map<String, dynamic> json) {
    return ReceiptPriceComparison(
      query: (json['query'] as String?) ?? '',
      normalizedName: (json['normalizedName'] as String?) ?? '',
      summaryByCurrency:
          (json['summaryByCurrency'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(ReceiptPriceSummary.fromJson)
              .toList(growable: false),
      items: (json['items'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ReceiptPriceItem.fromJson)
          .toList(growable: false),
    );
  }
}

class ReceiptPriceSummary {
  const ReceiptPriceSummary({
    required this.currency,
    required this.unit,
    required this.count,
    required this.minUnitPrice,
    required this.maxUnitPrice,
    required this.averageUnitPrice,
    required this.bestMerchant,
    required this.bestItemName,
    required this.bestUnitPrice,
  });

  final String currency;
  final String unit;
  final int count;
  final double minUnitPrice;
  final double maxUnitPrice;
  final double averageUnitPrice;
  final String bestMerchant;
  final String bestItemName;
  final double bestUnitPrice;

  factory ReceiptPriceSummary.fromJson(Map<String, dynamic> json) {
    return ReceiptPriceSummary(
      currency: (json['currency'] as String?) ?? 'INR',
      unit: (json['unit'] as String?) ?? 'each',
      count: (json['count'] as num?)?.toInt() ?? 0,
      minUnitPrice: (json['minUnitPrice'] as num?)?.toDouble() ?? 0,
      maxUnitPrice: (json['maxUnitPrice'] as num?)?.toDouble() ?? 0,
      averageUnitPrice: (json['averageUnitPrice'] as num?)?.toDouble() ?? 0,
      bestMerchant: (json['bestMerchant'] as String?) ?? '',
      bestItemName: (json['bestItemName'] as String?) ?? '',
      bestUnitPrice: (json['bestUnitPrice'] as num?)?.toDouble() ?? 0,
    );
  }
}

class ReceiptPriceItem {
  const ReceiptPriceItem({
    required this.id,
    required this.sourceType,
    required this.expenseId,
    required this.groupName,
    required this.merchant,
    required this.date,
    required this.currency,
    required this.itemName,
    required this.normalizedName,
    required this.originalText,
    required this.quantity,
    required this.unit,
    required this.normalizedUnit,
    required this.lineTotal,
    required this.unitPriceNormalized,
    required this.confidence,
  });

  final String id;
  final String sourceType;
  final String expenseId;
  final String groupName;
  final String merchant;
  final DateTime date;
  final String currency;
  final String itemName;
  final String normalizedName;
  final String originalText;
  final double? quantity;
  final String unit;
  final String normalizedUnit;
  final double? lineTotal;
  final double? unitPriceNormalized;
  final double confidence;

  factory ReceiptPriceItem.fromJson(Map<String, dynamic> json) {
    return ReceiptPriceItem(
      id: (json['id'] as String?) ?? '',
      sourceType: (json['sourceType'] as String?) ?? 'personal',
      expenseId: (json['expenseId'] as String?) ?? '',
      groupName: (json['groupName'] as String?) ?? '',
      merchant: (json['merchant'] as String?) ?? '',
      date:
          DateTime.tryParse((json['date'] as String?) ?? '') ?? DateTime.now(),
      currency: (json['currency'] as String?) ?? 'INR',
      itemName: (json['itemName'] as String?) ?? '',
      normalizedName: (json['normalizedName'] as String?) ?? '',
      originalText: (json['originalText'] as String?) ?? '',
      quantity: (json['quantity'] as num?)?.toDouble(),
      unit: (json['unit'] as String?) ?? '',
      normalizedUnit: (json['normalizedUnit'] as String?) ?? '',
      lineTotal: (json['lineTotal'] as num?)?.toDouble(),
      unitPriceNormalized: (json['unitPriceNormalized'] as num?)?.toDouble(),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
    );
  }
}

class ReceiptPriceRepository {
  ReceiptPriceRepository({
    http.Client? client,
    AuthTokenProvider? authTokenProvider,
  }) : _client = client ?? http.Client(),
       _authTokenProvider =
           authTokenProvider ?? const SessionAuthTokenProvider();

  final http.Client _client;
  final AuthTokenProvider _authTokenProvider;
  static const _requestTimeout = Duration(seconds: 20);

  Future<ReceiptPriceComparison> compare({
    String query = '',
    String currency = '',
    int limit = 80,
  }) async {
    final params = <String, String>{'limit': '$limit'};
    if (query.trim().isNotEmpty) {
      params['q'] = query.trim();
    }
    if (currency.trim().isNotEmpty) {
      params['currency'] = currency.trim().toUpperCase();
    }
    final token = await _authTokenProvider.getBearerToken();
    final response = await _client
        .get(
          Uri.parse(
            '${ApiConfig.baseUrl}/api/v1/receipt-items/compare',
          ).replace(queryParameters: params),
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
        )
        .timeout(_requestTimeout);
    if (response.statusCode != 200) {
      throw Exception(
        'receipt comparison failed (${response.statusCode}): ${response.body}',
      );
    }
    return ReceiptPriceComparison.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  void dispose() {
    _client.close();
  }
}
