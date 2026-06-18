// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'expense.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Expense _$ExpenseFromJson(Map<String, dynamic> json) => Expense(
  core: ExpenseCore.fromJson(json['core'] as Map<String, dynamic>),
  description: json['description'] as String?,
  updatedAt: json['updatedAt'] == null
      ? null
      : DateTime.parse(json['updatedAt'] as String),
  paymentMethod: json['paymentMethod'] as String?,
  sourceType: json['sourceType'] as String?,
  sourceAccountId: json['sourceAccountId'] as String?,
  sourceAccountName: json['sourceAccountName'] as String?,
  sourceDestinationAccountId: json['sourceDestinationAccountId'] as String?,
  sourceDestinationAccountName: json['sourceDestinationAccountName'] as String?,
  sourcePaymentType: json['sourcePaymentType'] as String?,
  sourcePeriod: json['sourcePeriod'] as String?,
  sourceSetupKey: json['sourceSetupKey'] as String?,
  tags:
      (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const [],
  isSynced: json['isSynced'] as bool? ?? true,
  deleted: json['deleted'] as bool? ?? false,
);

Map<String, dynamic> _$ExpenseToJson(Expense instance) => <String, dynamic>{
  'core': instance.core,
  'description': instance.description,
  'updatedAt': instance.updatedAt?.toIso8601String(),
  'paymentMethod': instance.paymentMethod,
  'sourceType': instance.sourceType,
  'sourceAccountId': instance.sourceAccountId,
  'sourceAccountName': instance.sourceAccountName,
  'sourceDestinationAccountId': instance.sourceDestinationAccountId,
  'sourceDestinationAccountName': instance.sourceDestinationAccountName,
  'sourcePaymentType': instance.sourcePaymentType,
  'sourcePeriod': instance.sourcePeriod,
  'sourceSetupKey': instance.sourceSetupKey,
  'tags': instance.tags,
  'isSynced': instance.isSynced,
  'deleted': instance.deleted,
};
