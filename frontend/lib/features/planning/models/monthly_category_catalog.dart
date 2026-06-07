const householdMonthlyCategories = <String>[
  'Groceries',
  'Utilities',
  'Rent and housing',
  'School and kids',
  'Food',
  'Transport',
  'Shopping',
  'Bills',
  'Travel',
  'Health',
  'Personal',
];

List<String> mergeMonthlyCategories(Iterable<String> extraCategories) {
  final seen = <String>{};
  final categories = <String>[];

  void add(String value) {
    final label = value.trim();
    if (label.isEmpty) return;
    final key = label.toLowerCase();
    if (seen.add(key)) {
      categories.add(label);
    }
  }

  for (final category in householdMonthlyCategories) {
    add(category);
  }
  for (final category in extraCategories) {
    add(category);
  }
  return List.unmodifiable(categories);
}

String normalizeMonthlyCategory(String value) {
  final lower = value.trim().toLowerCase();
  for (final category in householdMonthlyCategories) {
    if (category.toLowerCase() == lower) {
      return category;
    }
  }
  return householdMonthlyCategories.first;
}
