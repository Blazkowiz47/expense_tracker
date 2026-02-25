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
  isSynced: json['isSynced'] as bool? ?? true,
  deleted: json['deleted'] as bool? ?? false,
);

Map<String, dynamic> _$ExpenseToJson(Expense instance) => <String, dynamic>{
  'core': instance.core,
  'description': instance.description,
  'updatedAt': instance.updatedAt?.toIso8601String(),
  'paymentMethod': instance.paymentMethod,
  'isSynced': instance.isSynced,
  'deleted': instance.deleted,
};
