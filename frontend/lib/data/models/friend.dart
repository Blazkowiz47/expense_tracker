import 'package:equatable/equatable.dart';

/// Represents a friend/contact in the expense tracker
/// Derived from expenses where this person is involved
class Friend extends Equatable {
  final String id;
  final String name;
  final int expenseCount; // Number of expenses involving this friend
  final double totalAmount; // Total amount in expenses with this friend

  const Friend({
    required this.id,
    required this.name,
    this.expenseCount = 0,
    this.totalAmount = 0.0,
  });

  Friend copyWith({
    String? id,
    String? name,
    int? expenseCount,
    double? totalAmount,
  }) {
    return Friend(
      id: id ?? this.id,
      name: name ?? this.name,
      expenseCount: expenseCount ?? this.expenseCount,
      totalAmount: totalAmount ?? this.totalAmount,
    );
  }

  @override
  List<Object?> get props => [id, name, expenseCount, totalAmount];

  @override
  String toString() =>
      'Friend(id: $id, name: $name, expenses: $expenseCount, total: $totalAmount)';
}
