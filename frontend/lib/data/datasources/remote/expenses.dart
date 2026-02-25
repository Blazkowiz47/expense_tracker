import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:expense_tracker/data/datasources/expenses.dart';
import 'package:expense_tracker/data/models/expense.dart';

/// Firebase Firestore implementation of ExpensesDatasource for remote storage
class ExpensesRemoteDatasource implements ExpensesDatasource {
  static const String collectionName = 'expenses';

  final FirebaseFirestore _firestore;
  final String _userId;

  ExpensesRemoteDatasource({
    required FirebaseFirestore firestore,
    required String userId,
  }) : _firestore = firestore,
       _userId = userId;

  /// Get the user's expenses subcollection reference
  CollectionReference<Map<String, dynamic>> get _userExpensesRef =>
      _firestore.collection('users').doc(_userId).collection(collectionName);

  @override
  Future<void> initialize() async {
    // Firebase doesn't require explicit initialization for Firestore
    // Connection is established on first use
  }

  @override
  Future<void> close() async {
    // Firebase doesn't require explicit cleanup for Firestore
    // Connection will be cleaned up automatically
  }

  @override
  Future<List<Expense>> getExpenses() async {
    try {
      final snapshot = await _userExpensesRef.get();
      return snapshot.docs
          .map((doc) => Expense.fromJson({...doc.data(), 'id': doc.id}))
          .toList();
    } catch (e) {
      throw Exception('Failed to fetch expenses from remote: $e');
    }
  }

  @override
  Future<bool> createExpense(Expense expense) async {
    try {
      await _userExpensesRef.doc(expense.id).set(expense.toJson());
      return true;
    } catch (e) {
      throw Exception('Failed to create expense remotely: $e');
    }
  }

  @override
  Future<bool> updateExpense(Expense expense) async {
    try {
      final doc = await _userExpensesRef.doc(expense.id).get();
      if (!doc.exists) {
        return false;
      }
      await _userExpensesRef.doc(expense.id).update(expense.toJson());
      return true;
    } catch (e) {
      throw Exception('Failed to update expense remotely: $e');
    }
  }

  @override
  Future<Expense?> getExpenseById(String id) async {
    try {
      final doc = await _userExpensesRef.doc(id).get();
      if (!doc.exists) {
        return null;
      }
      return Expense.fromJson({...doc.data() ?? {}, 'id': doc.id});
    } catch (e) {
      throw Exception('Failed to get expense by id from remote: $e');
    }
  }
}
