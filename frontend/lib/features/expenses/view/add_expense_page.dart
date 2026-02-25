import 'package:expense_tracker/core/constants/app_spacing.dart';
import 'package:expense_tracker/core/utils/platform_widget.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class AddExpensePage extends StatelessWidget {
  const AddExpensePage({super.key});

  @override
  Widget build(BuildContext context) {
    return PlatformWidget(
      ios: _buildCupertino(context),
      android: _buildMaterial(context),
      web: _buildMaterial(context),
    );
  }

  Widget _buildMaterial(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add an expense')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'With you and',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: const [
                          Chip(label: Text('All of this group')),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const TextField(
                        decoration: InputDecoration(
                          labelText: 'Description',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const TextField(
                        keyboardType: TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Amount',
                          prefixText: 'INR ',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownMenu<String>(
                              initialSelection: 'You',
                              label: const Text('Paid by'),
                              dropdownMenuEntries: const [
                                DropdownMenuEntry(value: 'You', label: 'You'),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownMenu<String>(
                              initialSelection: 'Equally',
                              label: const Text('Split'),
                              dropdownMenuEntries: const [
                                DropdownMenuEntry(
                                  value: 'Equally',
                                  label: 'Equally',
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.check),
                label: const Text('Save expense'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCupertino(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Add an expense'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(30, 30),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Save'),
        ),
      ),
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                const Text(
                  'With you and',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: AppSpacing.sm),
                const Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [_CupertinoPill(label: 'All of this group')],
                ),
                const SizedBox(height: AppSpacing.md),
                CupertinoFormSection.insetGrouped(
                  children: [
                    CupertinoFormRow(
                      prefix: const Text('Description'),
                      child: const CupertinoTextField(
                        placeholder: 'Enter a description',
                        textAlign: TextAlign.end,
                      ),
                    ),
                    CupertinoFormRow(
                      prefix: const Text('Amount'),
                      child: const CupertinoTextField(
                        placeholder: 'INR 0.00',
                        keyboardType: TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textAlign: TextAlign.end,
                      ),
                    ),
                    CupertinoFormRow(
                      prefix: const Text('Paid by'),
                      child: const Text('You'),
                    ),
                    CupertinoFormRow(
                      prefix: const Text('Split'),
                      child: const Text('Equally'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                CupertinoButton.filled(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Save expense'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CupertinoPill extends StatelessWidget {
  const _CupertinoPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey5.resolveFrom(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(label, style: const TextStyle(fontSize: 14)),
      ),
    );
  }
}
