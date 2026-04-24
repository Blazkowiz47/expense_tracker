import 'package:expense_tracker/core/ui/app_ui.dart';
import 'package:expense_tracker/core/widgets/selectable_error_message.dart';
import 'package:expense_tracker/data/repositories/expenses_repository.dart';
import 'package:expense_tracker/features/dashboard/bloc/dashboard_snapshot_cubit.dart';
import 'package:expense_tracker/features/dashboard/models/dashboard_snapshot.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key});

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

enum _ActivityTypeFilter { all, spent, incoming }

enum _ActivityWindowFilter { all, last7Days, last30Days }

class _ActivityPageState extends State<ActivityPage> {
  final _searchController = TextEditingController();
  String _query = '';
  _ActivityTypeFilter _typeFilter = _ActivityTypeFilter.all;
  _ActivityWindowFilter _windowFilter = _ActivityWindowFilter.all;
  bool _exporting = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ActivityItem> _filteredItems(List<ActivityItem> source) {
    final q = _query.trim().toLowerCase();
    final now = DateTime.now();
    final start = switch (_windowFilter) {
      _ActivityWindowFilter.all => null,
      _ActivityWindowFilter.last7Days => now.subtract(const Duration(days: 7)),
      _ActivityWindowFilter.last30Days => now.subtract(
        const Duration(days: 30),
      ),
    };

    return source
        .where((item) {
          final isSpending = item.amountText.toLowerCase().startsWith(
            'you spent',
          );
          final matchesType = switch (_typeFilter) {
            _ActivityTypeFilter.all => true,
            _ActivityTypeFilter.spent => isSpending,
            _ActivityTypeFilter.incoming => !isSpending,
          };
          if (!matchesType) return false;

          if (start != null) {
            final date = DateTime.tryParse(item.subtitle)?.toLocal();
            if (date == null || date.isBefore(start)) {
              return false;
            }
          }

          if (q.isEmpty) {
            return true;
          }
          final haystack = '${item.title} ${item.subtitle} ${item.amountText}'
              .toLowerCase();
          return haystack.contains(q);
        })
        .toList(growable: false);
  }

  Future<void> _exportCsv() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final repository = context.read<ExpenseRepository>();
      final now = DateTime.now();
      final from = switch (_windowFilter) {
        _ActivityWindowFilter.all => null,
        _ActivityWindowFilter.last7Days => now.subtract(
          const Duration(days: 7),
        ),
        _ActivityWindowFilter.last30Days => now.subtract(
          const Duration(days: 30),
        ),
      };
      final csv = await repository.exportExpensesCsv(query: _query, from: from);
      if (!mounted) return;
      await Clipboard.setData(ClipboardData(text: csv));
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('CSV exported'),
          content: SizedBox(
            width: 700,
            child: SingleChildScrollView(
              child: Text(
                csv,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DashboardSnapshotCubit, DashboardSnapshotState>(
      builder: (context, state) {
        if (state is DashboardSnapshotFailure) {
          return SelectableErrorMessage(state.message);
        }
        if (state is! DashboardSnapshotLoaded) {
          return const Center(child: CircularProgressIndicator());
        }

        final filtered = _filteredItems(state.snapshot.activityItems);
        return AppPageContainer(
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search activity',
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _exporting ? null : _exportCsv,
                  icon: _exporting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_outlined),
                  label: const Text('Export CSV'),
                ),
                ChoiceChip(
                  label: const Text('All'),
                  selected: _typeFilter == _ActivityTypeFilter.all,
                  onSelected: (_) {
                    setState(() => _typeFilter = _ActivityTypeFilter.all);
                  },
                ),
                ChoiceChip(
                  label: const Text('Spent'),
                  selected: _typeFilter == _ActivityTypeFilter.spent,
                  onSelected: (_) {
                    setState(() => _typeFilter = _ActivityTypeFilter.spent);
                  },
                ),
                ChoiceChip(
                  label: const Text('Incoming'),
                  selected: _typeFilter == _ActivityTypeFilter.incoming,
                  onSelected: (_) {
                    setState(() => _typeFilter = _ActivityTypeFilter.incoming);
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Any time'),
                  selected: _windowFilter == _ActivityWindowFilter.all,
                  onSelected: (_) {
                    setState(() => _windowFilter = _ActivityWindowFilter.all);
                  },
                ),
                ChoiceChip(
                  label: const Text('Last 7d'),
                  selected: _windowFilter == _ActivityWindowFilter.last7Days,
                  onSelected: (_) {
                    setState(
                      () => _windowFilter = _ActivityWindowFilter.last7Days,
                    );
                  },
                ),
                ChoiceChip(
                  label: const Text('Last 30d'),
                  selected: _windowFilter == _ActivityWindowFilter.last30Days,
                  onSelected: (_) {
                    setState(
                      () => _windowFilter = _ActivityWindowFilter.last30Days,
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (filtered.isEmpty)
              const AppEmptyState(title: 'No activity matches your filters')
            else
              ...filtered.map((item) {
                final isSpending = item.amountText.toLowerCase().startsWith(
                  'you spent',
                );
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    child: ListTile(
                      leading: const AppAvatar(
                        icon: Icons.receipt_long_outlined,
                      ),
                      title: Text(item.title),
                      subtitle: Text(
                        AppMoney.normalizeDisplayText(item.subtitle),
                      ),
                      trailing: AppMoneyLabel(
                        text: item.amountText,
                        positive: item.positive,
                        neutral: isSpending,
                      ),
                    ),
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}
