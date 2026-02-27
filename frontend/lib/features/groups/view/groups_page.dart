import 'package:expense_tracker/core/widgets/selectable_error_message.dart';
import 'package:expense_tracker/data/models/group.dart';
import 'package:expense_tracker/features/groups/models/group_summary.dart';
import 'package:expense_tracker/features/groups/repositories/api_groups_repository.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class GroupsPage extends StatefulWidget {
  const GroupsPage({super.key});

  @override
  State<GroupsPage> createState() => _GroupsPageState();
}

class _GroupsPageState extends State<GroupsPage> {
  late final http.Client _client;
  late final ApiGroupsRepository _repository;
  List<GroupSummary> _groups = const [];
  bool _loading = true;
  bool _creating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _client = http.Client();
    _repository = ApiGroupsRepository(client: _client);
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
      final groups = await _repository.fetchGroups();
      if (!mounted) return;
      setState(() => _groups = groups);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openCreateGroupDialog() async {
    if (_creating) return;
    final created = await showDialog<_CreateGroupInput>(
      context: context,
      builder: (context) => const _CreateGroupDialog(),
    );
    if (created == null) return;

    setState(() => _creating = true);
    try {
      await _repository.createGroup(
        name: created.name,
        groupType: created.type,
      );
      if (!mounted) return;
      await _loadGroups();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Group created.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _creating = false);
      }
    }
  }

  void _openGroupDetails(GroupSummary group) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => _GroupDetailsPage(group: group)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SummaryCard(
              title: 'Your groups',
              amount: '${_groups.length}',
              amountColor: const Color(0xFF1B8C67),
            ),
            const SizedBox(height: 16),
            _GroupsHeader(
              onCreateGroup: _creating ? null : _openCreateGroupDialog,
            ),
            if (_loading)
              const Card(child: ListTile(title: Text('Loading groups...')))
            else if (_error != null)
              SelectableErrorMessage(_error!)
            else if (_groups.isEmpty)
              const _GroupTile(
                group: GroupSummary(
                  id: '',
                  name: 'No groups yet',
                  groupType: GroupType.split,
                  memberCount: 1,
                ),
                subtitle: 'Create a split or family group to get started.',
                amountText: '',
              )
            else
              ..._groups.map(
                (group) => _GroupTile(
                  group: group,
                  onTap: () => _openGroupDetails(group),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GroupsHeader extends StatelessWidget {
  const _GroupsHeader({required this.onCreateGroup});

  final VoidCallback? onCreateGroup;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Text('Groups', style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          TextButton(
            onPressed: onCreateGroup,
            child: const Text('Create group'),
          ),
        ],
      ),
    );
  }
}

class _CreateGroupDialog extends StatefulWidget {
  const _CreateGroupDialog();

  @override
  State<_CreateGroupDialog> createState() => _CreateGroupDialogState();
}

class _CreateGroupDialogState extends State<_CreateGroupDialog> {
  final _nameController = TextEditingController();
  GroupType _type = GroupType.split;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final input = _CreateGroupInput(name: name, type: _type);
    Navigator.of(context).pop(input);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create group'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Group name'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<GroupType>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Group type'),
            items: const [
              DropdownMenuItem(
                value: GroupType.split,
                child: Text('Split (owes/owed)'),
              ),
              DropdownMenuItem(
                value: GroupType.family,
                child: Text('Family (tracking only)'),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _type = value);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Create')),
      ],
    );
  }
}

class _GroupDetailsPage extends StatelessWidget {
  const _GroupDetailsPage({required this.group});

  final GroupSummary group;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(group.name)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: group.groupType == GroupType.family
            ? _FamilyGroupBody(group: group)
            : _SplitGroupBody(group: group),
      ),
    );
  }
}

class _FamilyGroupBody extends StatelessWidget {
  const _FamilyGroupBody({required this.group});

  final GroupSummary group;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Card(
          child: ListTile(
            title: const Text('Monthly spend'),
            subtitle: const Text(
              'Family tracking mode (no settlement balances)',
            ),
            trailing: Text(
              'INR 0.00',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Card(
          child: ListTile(
            title: Text('Recent expenses'),
            subtitle: Text(
              'No expenses yet. Add monthly household spend here.',
            ),
          ),
        ),
      ],
    );
  }
}

class _SplitGroupBody extends StatelessWidget {
  const _SplitGroupBody({required this.group});

  final GroupSummary group;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Card(
          child: ListTile(
            title: const Text('Settlement status'),
            subtitle: const Text('Split expenses with members'),
            trailing: Text(
              'No balances yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Card(
          child: ListTile(
            title: Text('Balances'),
            subtitle: Text(
              'Per-member owes/owed breakdown will be shown here.',
            ),
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.amount,
    required this.amountColor,
  });

  final String title;
  final String amount;
  final Color amountColor;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              amount,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: amountColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({
    required this.group,
    this.onTap,
    this.subtitle,
    this.amountText,
  });

  final GroupSummary group;
  final VoidCallback? onTap;
  final String? subtitle;
  final String? amountText;

  @override
  Widget build(BuildContext context) {
    final badge = group.groupType == GroupType.family ? 'Family' : 'Split';
    final icon = group.groupType == GroupType.family
        ? Icons.home_outlined
        : Icons.group_outlined;
    final trailingText = amountText ?? '${group.memberCount} member(s)';
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(icon),
        ),
        title: Row(
          children: [
            Expanded(child: Text(group.name)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(badge, style: Theme.of(context).textTheme.labelSmall),
            ),
          ],
        ),
        subtitle: Text(
          subtitle ??
              (group.groupType == GroupType.family
                  ? 'Family monthly tracking (no balances)'
                  : 'Split expenses with members'),
        ),
        trailing: trailingText.isEmpty
            ? null
            : Text(trailingText, style: Theme.of(context).textTheme.labelLarge),
      ),
    );
  }
}

class _CreateGroupInput {
  const _CreateGroupInput({required this.name, required this.type});

  final String name;
  final GroupType type;
}
