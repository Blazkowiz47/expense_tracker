import 'package:json_annotation/json_annotation.dart';

part 'expense_core.g.dart';

@JsonSerializable()
class ExpenseCore {
  final String id;
  final String title;
  final double amount;
  final String currency;
  final String? category;
  final DateTime createdAt;

  ExpenseCore({
    required this.id,
    required this.title,
    required this.amount,
    required this.currency,
    this.category,
    required this.createdAt,
  });

  factory ExpenseCore.fromJson(Map<String, dynamic> json) =>
      _$ExpenseCoreFromJson(json);

  Map<String, dynamic> toJson() => _$ExpenseCoreToJson(this);

  ExpenseCore copyWith({
    String? id,
    String? title,
    double? amount,
    String? currency,
    String? category,
    DateTime? createdAt,
  }) {
    return ExpenseCore(
      id: id ?? this.id,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      category: category ?? this.category,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
