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
    final tagChoices = _tagChoicesFor(item);
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
                      child: _ReceiptItemTagsField(
                        key: ValueKey('receipt-tags-$index'),
                        selectedTags: item.tags,
                        suggestions: tagChoices,
                        onChanged: (tags) =>
                            onChanged(item.copyWith(tags: tags)),
                      ),
                    ),
                    _FieldSpec(
                      flex: 2,
                      child: TextFormField(
                        key: ValueKey('receipt-quantity-unit-$index'),
                        initialValue: _formatQuantityUnit(item),
                        decoration: const InputDecoration(
                          labelText: 'Qty / unit',
                          hintText: '1 U',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          final parsed = _parseQuantityUnit(value);
                          onChanged(
                            item.copyWith(
                              quantity: parsed.quantity,
                              unit: parsed.unit,
                            ),
                          );
                        },
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
            ],
          ),
        ),
      ),
    );
  }
}

class _ReceiptItemTagsField extends StatelessWidget {
  const _ReceiptItemTagsField({
    required this.selectedTags,
    required this.suggestions,
    required this.onChanged,
    super.key,
  });

  final List<String> selectedTags;
  final List<String> suggestions;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _normalizeTags(selectedTags);
    final available = suggestions
        .where((tag) => !selected.contains(tag))
        .toList(growable: false);
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Tags',
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.fromLTRB(12, 8, 8, 8),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (selected.isEmpty)
            Text(
              'Choose tags',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            ...selected.map(
              (tag) => InputChip(
                label: Text(tag),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onDeleted: () => onChanged(
                  selected.where((item) => item != tag).toList(growable: false),
                ),
              ),
            ),
          PopupMenuButton<String>(
            tooltip: 'Add tag',
            onSelected: (value) async {
              if (value == _addTagAction) {
                final tag = await _showAddTagDialog(context);
                if (tag == null) return;
                onChanged(_normalizeTags([...selected, tag]));
                return;
              }
              onChanged(_normalizeTags([...selected, value]));
            },
            itemBuilder: (context) => [
              ...available.map(
                (tag) => PopupMenuItem<String>(value: tag, child: Text(tag)),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: _addTagAction,
                child: Text('Add new tag...'),
              ),
            ],
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outline),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.arrow_drop_down,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      'Add',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _showAddTagDialog(BuildContext context) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add tag'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Tag',
            hintText: 'guilty pleasure',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) =>
              Navigator.of(context).pop(_normalizeTag(value)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(_normalizeTag(controller.text)),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) return null;
    return result;
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

String _formatQuantityUnit(BillLineItem item) {
  final quantity = item.quantity;
  final unit = item.unit.trim();
  if (quantity == null && unit.isEmpty) return '';
  final quantityText = quantity == null
      ? ''
      : quantity % 1 == 0
      ? quantity.toStringAsFixed(0)
      : quantity.toString();
  return [quantityText, unit].where((part) => part.isNotEmpty).join(' ');
}

({double? quantity, String unit}) _parseQuantityUnit(String value) {
  final cleaned = value.trim();
  if (cleaned.isEmpty) {
    return (quantity: null, unit: '');
  }
  final match = RegExp(
    r'^([0-9]+(?:[,.][0-9]+)?)(?:\s*(.*))?$',
  ).firstMatch(cleaned);
  if (match == null) {
    return (quantity: null, unit: cleaned);
  }
  return (
    quantity: _parseNumber(match.group(1) ?? ''),
    unit: (match.group(2) ?? '').trim(),
  );
}

List<String> _tagChoicesFor(BillLineItem item) {
  return _normalizeTags([
    ...item.tags,
    item.category,
    item.normalizedName,
    'grocery',
    'vegetables',
    'fruit',
    'snacks',
    'chocolate',
    'dessert',
    'guilty pleasure',
    'household',
    'personal',
    'essentials',
  ]);
}

List<String> _normalizeTags(Iterable<String> values) {
  final tags = <String>[];
  final seen = <String>{};
  for (final raw in values) {
    final tag = _normalizeTag(raw);
    if (tag.isEmpty || seen.contains(tag)) continue;
    tags.add(tag);
    seen.add(tag);
  }
  return tags;
}

String _normalizeTag(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

const _addTagAction = '__add_tag__';
