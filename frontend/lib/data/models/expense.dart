import 'package:json_annotation/json_annotation.dart';
import 'package:expense_tracker/data/models/expense_core.dart';

part 'expense.g.dart';

@JsonSerializable()
class Expense {
  final ExpenseCore core;
  final String? description;
  final DateTime? updatedAt;
  final String? paymentMethod;
  final String? sourceType;
  final String? sourceAccountId;
  final String? sourceAccountName;
  final String? sourcePaymentType;
  final String? sourcePeriod;
  final String? sourceSetupKey;
  final bool isSynced;
  final bool deleted;

  Expense({
    required this.core,
    this.description,
    this.updatedAt,
    this.paymentMethod,
    this.sourceType,
    this.sourceAccountId,
    this.sourceAccountName,
    this.sourcePaymentType,
    this.sourcePeriod,
    this.sourceSetupKey,
    this.isSynced = true,
    this.deleted = false,
  });

  // Convenience getters for easy access
  String get id => core.id;
  String get title => core.title;
  double get amount => core.amount;
  String get currency => core.currency;
  String? get category => core.category;
  DateTime get createdAt => core.createdAt;
  bool get isIncome => sourcePaymentType?.trim().toLowerCase() == 'income';

  factory Expense.fromJson(Map<String, dynamic> json) =>
      _$ExpenseFromJson(json);

  factory Expense.fromBackendJson(Map<String, dynamic> json) {
    final description = (json['description'] as String?)?.trim();
    final category = (json['category'] as String?)?.trim();
    final currency = (json['currency'] as String?)?.trim();
    final paymentMethod = (json['paymentMethod'] as String?)?.trim();
    final sourceType = (json['sourceType'] as String?)?.trim();
    final sourceAccountId = (json['sourceAccountId'] as String?)?.trim();
    final sourceAccountName = (json['sourceAccountName'] as String?)?.trim();
    final sourcePaymentType = (json['sourcePaymentType'] as String?)?.trim();
    final sourcePeriod = (json['sourcePeriod'] as String?)?.trim();
    final sourceSetupKey = (json['sourceSetupKey'] as String?)?.trim();
    final dateRaw = (json['date'] as String?) ?? '';
    final createdAt = DateTime.tryParse(dateRaw)?.toLocal() ?? DateTime.now();
    final updatedRaw = json['updatedAt'] as String?;

    return Expense(
      core: ExpenseCore(
        id: (json['id'] as String?) ?? '',
        title: (description != null && description.isNotEmpty)
            ? description
            : (category != null && category.isNotEmpty ? category : 'Expense'),
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        currency: currency?.isNotEmpty == true ? currency! : 'INR',
        category: category,
        createdAt: createdAt,
      ),
      description: description,
      updatedAt: updatedRaw != null ? DateTime.tryParse(updatedRaw) : null,
      paymentMethod: paymentMethod?.isNotEmpty == true ? paymentMethod : null,
      sourceType: sourceType?.isNotEmpty == true ? sourceType : null,
      sourceAccountId: sourceAccountId?.isNotEmpty == true
          ? sourceAccountId
          : null,
      sourceAccountName: sourceAccountName?.isNotEmpty == true
          ? sourceAccountName
          : null,
      sourcePaymentType: sourcePaymentType?.isNotEmpty == true
          ? sourcePaymentType
          : null,
      sourcePeriod: sourcePeriod?.isNotEmpty == true ? sourcePeriod : null,
      sourceSetupKey: sourceSetupKey?.isNotEmpty == true
          ? sourceSetupKey
          : null,
      isSynced: true,
      deleted: false,
    );
  }

  Map<String, dynamic> toJson() {
    final json = _$ExpenseToJson(this);
    json['core'] = core.toJson();
    return json;
  }

  Expense copyWith({
    ExpenseCore? core,
    String? description,
    DateTime? updatedAt,
    String? paymentMethod,
    String? sourceType,
    String? sourceAccountId,
    String? sourceAccountName,
    String? sourcePaymentType,
    String? sourcePeriod,
    String? sourceSetupKey,
    bool? isSynced,
    bool? deleted,
  }) {
    return Expense(
      core: core ?? this.core,
      description: description ?? this.description,
      updatedAt: updatedAt ?? this.updatedAt,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      sourceType: sourceType ?? this.sourceType,
      sourceAccountId: sourceAccountId ?? this.sourceAccountId,
      sourceAccountName: sourceAccountName ?? this.sourceAccountName,
      sourcePaymentType: sourcePaymentType ?? this.sourcePaymentType,
      sourcePeriod: sourcePeriod ?? this.sourcePeriod,
      sourceSetupKey: sourceSetupKey ?? this.sourceSetupKey,
      isSynced: isSynced ?? this.isSynced,
      deleted: deleted ?? this.deleted,
    );
  }
}
