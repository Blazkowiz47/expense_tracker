import 'package:expense_tracker/features/expenses/repositories/bill_ai_repository.dart';
import 'package:flutter/material.dart';

class ReceiptLineItemsReview extends StatelessWidget {
  const ReceiptLineItemsReview({
    required this.items,
    required this.currency,
    required this.onChanged,
    super.key,
  });

  final List<BillLineItem> items;
  final String currency;
  final ValueChanged<List<BillLineItem>> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Receipt items', style: theme.textTheme.labelLarge),
            ),
            TextButton.icon(
              onPressed: () => onChanged([
                ...items,
                const BillLineItem(name: '', normalizedName: ''),
              ]),
              icon: const Icon(Icons.add),
              label: const Text('Item'),
            ),
          ],
        ),
        if (items.isEmpty)
          Text(
            'No items detected yet.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          ...items.asMap().entries.map(
            (entry) => _ReceiptLineItemEditor(
              index: entry.key,
              item: entry.value,
              currency: currency,
              onChanged: (item) => _replace(entry.key, item),
              onRemove: () => _remove(entry.key),
            ),
          ),
      ],
    );
  }

  void _replace(int index, BillLineItem item) {
    final updated = [...items];
    updated[index] = item;
    onChanged(updated);
  }

  void _remove(int index) {
    final updated = [...items]..removeAt(index);
    onChanged(updated);
  }
}

class _ReceiptLineItemEditor extends StatelessWidget {
  const _ReceiptLineItemEditor({
    required this.index,
    required this.item,
    required this.currency,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final BillLineItem item;
  final String currency;
  final ValueChanged<BillLineItem> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final confidence = (item.confidence * 100).round();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.originalText.trim().isEmpty
                          ? 'Item ${index + 1}'
                          : item.originalText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (confidence > 0)
                    Text('$confidence%', style: theme.textTheme.labelSmall),
                  IconButton(
                    tooltip: 'Remove item',
                    onPressed: onRemove,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 560;
                  final fields = [
                    _FieldSpec(
                      flex: 3,
                      child: TextFormField(
                        key: ValueKey('receipt-name-$index'),
                        initialValue: item.name,
                        decoration: const InputDecoration(
                          labelText: 'Item',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) =>
                            onChanged(item.copyWith(name: value)),
                      ),
                    ),
                    _FieldSpec(
                      flex: 3,
                      child: TextFormField(
                        key: ValueKey('receipt-normalized-$index'),
                        initialValue: item.normalizedName,
                        decoration: const InputDecoration(
                          labelText: 'Compare as',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) =>
                            onChanged(item.copyWith(normalizedName: value)),
                      ),
                    ),
                    _FieldSpec(
                      flex: 2,
                      child: TextFormField(
                        key: ValueKey('receipt-quantity-$index'),
                        initialValue: item.quantity?.toString() ?? '',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Qty',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) => onChanged(
                          item.copyWith(quantity: _parseNumber(value)),
                        ),
                      ),
                    ),
                    _FieldSpec(
                      flex: 2,
                      child: TextFormField(
                        key: ValueKey('receipt-unit-$index'),
                        initialValue: item.unit,
                        decoration: const InputDecoration(
                          labelText: 'Unit',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) =>
                            onChanged(item.copyWith(unit: value)),
                      ),
                    ),
                    _FieldSpec(
                      flex: 2,
                      child: TextFormField(
                        key: ValueKey('receipt-total-$index'),
                        initialValue: item.lineTotal?.toStringAsFixed(2) ?? '',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Total',
                          prefixText: '$currency ',
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (value) => onChanged(
                          item.copyWith(lineTotal: _parseNumber(value)),
                        ),
                      ),
                    ),
                  ];
                  if (compact) {
                    return Column(
                      children: fields
                          .map(
                            (field) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: field.child,
                            ),
                          )
                          .toList(growable: false),
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: fields
                        .map(
                          (field) => Expanded(
                            flex: field.flex,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: field.child,
                            ),
                          ),
                        )
                        .toList(growable: false),
                  );
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: ValueKey('receipt-tags-$index'),
                initialValue: item.tags.join(', '),
                decoration: const InputDecoration(
                  labelText: 'Tags',
                  hintText: 'chocolate, guilty pleasure',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) =>
                    onChanged(item.copyWith(tags: _parseTags(value))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldSpec {
  const _FieldSpec({required this.flex, required this.child});

  final int flex;
  final Widget child;
}

double? _parseNumber(String value) {
  final cleaned = value.trim().replaceAll(',', '.');
  if (cleaned.isEmpty) {
    return null;
  }
  return double.tryParse(cleaned);
}

List<String> _parseTags(String value) {
  final tags = <String>[];
  final seen = <String>{};
  for (final raw in value.split(RegExp(r'[,;#\n]'))) {
    final tag = raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    if (tag.isEmpty || seen.contains(tag)) continue;
    tags.add(tag);
    seen.add(tag);
  }
  return tags;
}
