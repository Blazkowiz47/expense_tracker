import 'dart:async';

import 'package:expense_tracker/core/ui/app_ui.dart';
import 'package:expense_tracker/core/utils/date_formatter.dart';
import 'package:expense_tracker/features/receipts/repositories/receipt_price_repository.dart';
import 'package:flutter/material.dart';

const _priceBookCurrencies = <String>['All', 'NOK', 'INR', 'USD', 'EUR', 'GBP'];

class PriceBookPage extends StatefulWidget {
  const PriceBookPage({this.repository, super.key});

  final ReceiptPriceRepository? repository;

  @override
  State<PriceBookPage> createState() => _PriceBookPageState();
}

class _PriceBookPageState extends State<PriceBookPage> {
  late final ReceiptPriceRepository _repository;
  late final bool _ownsRepository;
  final _searchController = TextEditingController();
  var _comparison = const ReceiptPriceComparison(
    query: '',
    normalizedName: '',
    summaryByCurrency: [],
    items: [],
  );
  var _currency = 'All';
  var _loading = true;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? ReceiptPriceRepository();
    _ownsRepository = widget.repository == null;
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    if (_ownsRepository) {
      _repository.dispose();
    }
    super.dispose();
  }

  Future<void> _load({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final comparison = await _repository.compare(
        query: _searchController.text,
        currency: _currency == 'All' ? '' : _currency,
      );
      if (!mounted) return;
      setState(() {
        _comparison = comparison;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _scheduleSearch() {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(_load(showLoading: false)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Price Book')),
      body: AppPageContainer(
        maxWidth: 980,
        onRefresh: _load,
        children: [
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        decoration: const InputDecoration(
                          labelText: 'Item',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => _scheduleSearch(),
                        onSubmitted: (_) => _load(showLoading: false),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 140,
                      child: DropdownButtonFormField<String>(
                        initialValue: _currency,
                        decoration: const InputDecoration(
                          labelText: 'Currency',
                          border: OutlineInputBorder(),
                        ),
                        items: _priceBookCurrencies
                            .map(
                              (currency) => DropdownMenuItem(
                                value: currency,
                                child: Text(currency),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _currency = value);
                          unawaited(_load(showLoading: false));
                        },
                      ),
                    ),
                  ],
                ),
                if (_comparison.normalizedName.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(
                        avatar: const Icon(Icons.label_outline, size: 18),
                        label: Text(_comparison.normalizedName),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_error != null)
            AppEmptyState(
              title: 'Could not load prices',
              subtitle: _error,
              actionLabel: 'Retry',
              onAction: () => _load(),
            )
          else if (_comparison.items.isEmpty)
            const AppEmptyState(
              title: 'No receipt items yet',
              subtitle: 'Saved receipt items will appear here.',
            )
          else ...[
            if (_comparison.summaryByCurrency.isNotEmpty)
              _SummaryGrid(summaries: _comparison.summaryByCurrency),
            AppCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Purchases',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  ..._comparison.items.map(_PriceItemTile.new),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.summaries});

  final List<ReceiptPriceSummary> summaries;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760 ? 3 : 1;
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: columns == 1 ? 4.2 : 2.7,
          children: summaries.map(_SummaryCard.new).toList(growable: false),
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard(this.summary);

  final ReceiptPriceSummary summary;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const AppAvatar(icon: Icons.price_check_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${_money(summary.bestUnitPrice, summary.currency)} / ${summary.unit}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  summary.bestMerchant.isEmpty
                      ? summary.bestItemName
                      : summary.bestMerchant,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${summary.count} seen · avg ${_money(summary.averageUnitPrice, summary.currency)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceItemTile extends StatelessWidget {
  const _PriceItemTile(this.item);

  final ReceiptPriceItem item;

  @override
  Widget build(BuildContext context) {
    final unit = item.normalizedUnit.isNotEmpty
        ? item.normalizedUnit
        : item.unit;
    final unitPrice = item.unitPriceNormalized == null
        ? ''
        : '${_money(item.unitPriceNormalized!, item.currency)} / $unit';
    final scope = item.sourceType == 'group' && item.groupName.isNotEmpty
        ? item.groupName
        : item.sourceType;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const AppAvatar(icon: Icons.receipt_long_outlined),
      title: Text(item.itemName.isEmpty ? item.normalizedName : item.itemName),
      subtitle: Text(
        [
          item.merchant,
          scope,
          DateFormatter.formatDate(item.date),
          if (item.quantity != null)
            '${_compactNumber(item.quantity!)} ${item.unit}'.trim(),
        ].where((part) => part.trim().isNotEmpty).join(' · '),
      ),
      trailing: SizedBox(
        width: 132,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (unitPrice.isNotEmpty)
              Text(unitPrice, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (item.lineTotal != null)
              Text(
                _money(item.lineTotal!, item.currency),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}

String _money(double amount, String currency) {
  return '$currency ${amount.toStringAsFixed(2)}';
}

String _compactNumber(double value) {
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
}
