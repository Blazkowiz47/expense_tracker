import 'package:expense_tracker/core/constants/app_spacing.dart';
import 'package:expense_tracker/core/ui/app_ui.dart';
import 'package:expense_tracker/core/utils/platform_page_route.dart';
import 'package:expense_tracker/core/utils/platform_widget.dart';
import 'package:expense_tracker/data/models/group.dart';
import 'package:expense_tracker/features/expenses/bloc/expenses_bloc.dart';
import 'package:expense_tracker/features/expenses/view/add_expense_page.dart';
import 'package:expense_tracker/features/groups/models/group_summary.dart';
import 'package:expense_tracker/features/groups/repositories/api_groups_repository.dart';
import 'package:expense_tracker/features/groups/view/groups_page.dart';
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
    await Navigator.of(context).push<void>(
      platformPageRoute(
        builder: (_) =>
            GroupDetailsPage(group: group, repository: _groupsRepository),
      ),
    );
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
        AppBalanceTile(
          title: 'Personal expense',
          subtitle: const Text('Track your own spending'),
          leadingIcon: Icons.person_outline,
          trailing: const Icon(Icons.chevron_right),
          onTap: _openPersonalExpense,
        ),
        const SizedBox(height: 8),
        const AppSectionHeader(title: 'Groups'),
        if (_groups.isEmpty)
          const AppEmptyState(
            title: 'No groups yet',
            subtitle: 'Create a group to add shared expenses.',
          )
        else
          ..._groups.map(
            (group) => AppBalanceTile(
              title: group.name,
              subtitle: Text(
                '${group.groupType.name} • ${group.memberCount} member(s)',
              ),
              leadingIcon: _iconForGroupType(group.groupType),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openGroupExpense(group),
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
