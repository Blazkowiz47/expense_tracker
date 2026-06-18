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
  final String? sourceDestinationAccountId;
  final String? sourceDestinationAccountName;
  final String? sourcePaymentType;
  final String? sourcePeriod;
  final String? sourceSetupKey;
  final String? sourceExpenseId;
  final List<String> tags;
  final ReimbursementInfo? reimbursement;
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
    this.sourceDestinationAccountId,
    this.sourceDestinationAccountName,
    this.sourcePaymentType,
    this.sourcePeriod,
    this.sourceSetupKey,
    this.sourceExpenseId,
    this.tags = const [],
    this.reimbursement,
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
    final sourceDestinationAccountId =
        (json['sourceDestinationAccountId'] as String?)?.trim();
    final sourceDestinationAccountName =
        (json['sourceDestinationAccountName'] as String?)?.trim();
    final sourcePaymentType = (json['sourcePaymentType'] as String?)?.trim();
    final sourcePeriod = (json['sourcePeriod'] as String?)?.trim();
    final sourceSetupKey = (json['sourceSetupKey'] as String?)?.trim();
    final sourceExpenseId = (json['sourceExpenseId'] as String?)?.trim();
    final tags = _readTags(json['tags']);
    final reimbursement = json['reimbursement'] is Map<String, dynamic>
        ? ReimbursementInfo.fromJson(
            json['reimbursement'] as Map<String, dynamic>,
          )
        : null;
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
      sourceDestinationAccountId: sourceDestinationAccountId?.isNotEmpty == true
          ? sourceDestinationAccountId
          : null,
      sourceDestinationAccountName:
          sourceDestinationAccountName?.isNotEmpty == true
          ? sourceDestinationAccountName
          : null,
      sourcePaymentType: sourcePaymentType?.isNotEmpty == true
          ? sourcePaymentType
          : null,
      sourcePeriod: sourcePeriod?.isNotEmpty == true ? sourcePeriod : null,
      sourceSetupKey: sourceSetupKey?.isNotEmpty == true
          ? sourceSetupKey
          : null,
      sourceExpenseId: sourceExpenseId?.isNotEmpty == true
          ? sourceExpenseId
          : null,
      tags: tags,
      reimbursement: reimbursement?.isActive == true ? reimbursement : null,
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
    String? sourceDestinationAccountId,
    String? sourceDestinationAccountName,
    String? sourcePaymentType,
    String? sourcePeriod,
    String? sourceSetupKey,
    String? sourceExpenseId,
    List<String>? tags,
    ReimbursementInfo? reimbursement,
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
      sourceDestinationAccountId:
          sourceDestinationAccountId ?? this.sourceDestinationAccountId,
      sourceDestinationAccountName:
          sourceDestinationAccountName ?? this.sourceDestinationAccountName,
      sourcePaymentType: sourcePaymentType ?? this.sourcePaymentType,
      sourcePeriod: sourcePeriod ?? this.sourcePeriod,
      sourceSetupKey: sourceSetupKey ?? this.sourceSetupKey,
      sourceExpenseId: sourceExpenseId ?? this.sourceExpenseId,
      tags: tags ?? this.tags,
      reimbursement: reimbursement ?? this.reimbursement,
      isSynced: isSynced ?? this.isSynced,
      deleted: deleted ?? this.deleted,
    );
  }
}

class ReimbursementInfo {
  const ReimbursementInfo({
    this.status = 'expected',
    this.payer = 'Company',
    this.expectedAmount = 0,
    this.receivedAmount = 0,
    this.currency = '',
    this.linkedIncomeIds = const [],
  });

  final String status;
  final String payer;
  final double expectedAmount;
  final double receivedAmount;
  final String currency;
  final List<String> linkedIncomeIds;

  bool get isActive => status.trim().toLowerCase() != 'none';
  bool get isReimbursed => status.trim().toLowerCase() == 'reimbursed';

  factory ReimbursementInfo.fromJson(Map<String, dynamic> json) {
    return ReimbursementInfo(
      status: (json['status'] ?? 'expected').toString(),
      payer: (json['payer'] ?? 'Company').toString(),
      expectedAmount: (json['expectedAmount'] as num?)?.toDouble() ?? 0,
      receivedAmount: (json['receivedAmount'] as num?)?.toDouble() ?? 0,
      currency: (json['currency'] ?? '').toString(),
      linkedIncomeIds:
          (json['linkedIncomeIds'] as List<dynamic>?)
              ?.map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList(growable: false) ??
          const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status,
      'payer': payer,
      'expectedAmount': expectedAmount,
      'receivedAmount': receivedAmount,
      'currency': currency,
      'linkedIncomeIds': linkedIncomeIds,
    };
  }
}

List<String> _readTags(Object? value) {
  final raw = value is List
      ? value
      : value is String
      ? value.split(RegExp(r'[,;#\n]'))
      : const [];
  final tags = <String>[];
  final seen = <String>{};
  for (final item in raw) {
    final tag = item.toString().trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    if (tag.isEmpty || seen.contains(tag)) continue;
    tags.add(tag);
    seen.add(tag);
  }
  return tags;
}
