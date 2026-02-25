import 'package:json_annotation/json_annotation.dart';
import 'package:expense_tracker/data/models/expense_core.dart';

part 'expense.g.dart';

@JsonSerializable()
class Expense {
  final ExpenseCore core;
  final String? description;
  final DateTime? updatedAt;
  final String? paymentMethod;
  final bool isSynced;
  final bool deleted;

  Expense({
    required this.core,
    this.description,
    this.updatedAt,
    this.paymentMethod,
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

  factory Expense.fromJson(Map<String, dynamic> json) =>
      _$ExpenseFromJson(json);

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
    bool? isSynced,
    bool? deleted,
  }) {
    return Expense(
      core: core ?? this.core,
      description: description ?? this.description,
      updatedAt: updatedAt ?? this.updatedAt,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      isSynced: isSynced ?? this.isSynced,
      deleted: deleted ?? this.deleted,
    );
  }
}
