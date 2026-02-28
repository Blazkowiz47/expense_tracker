import 'package:expense_tracker/core/constants/app_spacing.dart';
import 'package:expense_tracker/core/utils/platform_page_route.dart';
import 'package:expense_tracker/core/utils/platform_widget.dart';
import 'package:expense_tracker/data/models/group.dart';
import 'package:expense_tracker/features/expenses/bloc/expenses_bloc.dart';
import 'package:expense_tracker/features/expenses/view/add_expense_page.dart';
import 'package:expense_tracker/features/groups/models/group_summary.dart';
import 'package:expense_tracker/features/groups/repositories/api_groups_repository.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;

class AddExpenseSelectorPage extends StatefulWidget {
  const AddExpenseSelectorPage({super.key});

  @override
  State<AddExpenseSelectorPage> createState() => _AddExpenseSelectorPageState();
}

class _AddExpenseSelectorPageState extends State<AddExpenseSelectorPage> {
  late final http.Client _client;
  late final ApiGroupsRepository _groupsRepository;
  List<GroupSummary> _groups = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _client = http.Client();
    _groupsRepository = ApiGroupsRepository(client: _client);
    _loadGroups();
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  Future<void> _loadGroups() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final groups = await _groupsRepository.fetchGroups();
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _openPersonalExpense() async {
    final expensesBloc = context.read<ExpensesBloc>();
    final created = await Navigator.of(context).push<bool>(
      platformPageRoute(
        builder: (_) => BlocProvider.value(
          value: expensesBloc,
          child: const AddExpensePage(),
        ),
      ),
    );
    if (!mounted) return;
    if (created == true) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _openGroupExpense(GroupSummary group) async {
    final created = await Navigator.of(context).push<bool>(
      platformPageRoute(
        builder: (_) =>
            AddGroupExpensePage(group: group, repository: _groupsRepository),
      ),
    );
    if (!mounted) return;
    if (created == true) {
      Navigator.of(context).pop(true);
    }
  }

  IconData _iconForGroupType(GroupType type) {
    return switch (type) {
      GroupType.family => Icons.family_restroom,
      GroupType.split => Icons.group,
    };
  }

  Widget _buildGroupList(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.sm),
              FilledButton(onPressed: _loadGroups, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Personal expense'),
            subtitle: const Text('Track your own spending'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openPersonalExpense,
          ),
        ),
        const SizedBox(height: 8),
        Text('Groups', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_groups.isEmpty)
          const Card(
            child: ListTile(
              title: Text('No groups yet'),
              subtitle: Text('Create a group to add shared expenses.'),
            ),
          )
        else
          ..._groups.map(
            (group) => Card(
              child: ListTile(
                leading: Icon(_iconForGroupType(group.groupType)),
                title: Text(group.name),
                subtitle: Text(
                  '${group.groupType.name} • ${group.memberCount} member(s)',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openGroupExpense(group),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMaterial(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add an expense')),
      body: _buildGroupList(context),
    );
  }

  Widget _buildCupertino(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Add an expense'),
      ),
      child: SafeArea(
        child: Material(
          color: Colors.transparent,
          child: _buildGroupList(context),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PlatformWidget(
      ios: _buildCupertino(context),
      android: _buildMaterial(context),
      web: _buildMaterial(context),
    );
  }
}

class AddGroupExpensePage extends StatefulWidget {
  const AddGroupExpensePage({
    required this.group,
    required this.repository,
    super.key,
  });

  final GroupSummary group;
  final ApiGroupsRepository repository;

  @override
  State<AddGroupExpensePage> createState() => _AddGroupExpensePageState();
}

class _AddGroupExpensePageState extends State<AddGroupExpensePage> {
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final description = _descriptionController.text.trim();
    final amount = double.tryParse(_amountController.text.trim());
    if (description.isEmpty) {
      setState(() => _error = 'Description is required.');
      return;
    }
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid amount greater than 0.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.addExpense(
        groupId: widget.group.id,
        description: description,
        amount: amount,
        date: DateTime.now(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  Widget _form(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.group.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Amount',
                        prefixText: 'INR ',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check),
              label: const Text('Save expense'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMaterial(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add group expense')),
      body: Stack(
        children: [
          _form(context),
          if (_saving) const LinearProgressIndicator(minHeight: 2),
        ],
      ),
    );
  }

  Widget _buildCupertino(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Add group expense'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(30, 30),
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ),
      child: SafeArea(
        child: Stack(
          children: [
            Material(color: Colors.transparent, child: _form(context)),
            if (_saving) const LinearProgressIndicator(minHeight: 2),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PlatformWidget(
      ios: _buildCupertino(context),
      android: _buildMaterial(context),
      web: _buildMaterial(context),
    );
  }
}
