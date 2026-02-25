// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'expense_core.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ExpenseCore _$ExpenseCoreFromJson(Map<String, dynamic> json) => ExpenseCore(
  id: json['id'] as String,
  title: json['title'] as String,
  amount: (json['amount'] as num).toDouble(),
  currency: json['currency'] as String,
  category: json['category'] as String?,
  createdAt: DateTime.parse(json['createdAt'] as String),
);

Map<String, dynamic> _$ExpenseCoreToJson(ExpenseCore instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'amount': instance.amount,
      'currency': instance.currency,
      'category': instance.category,
      'createdAt': instance.createdAt.toIso8601String(),
    };
