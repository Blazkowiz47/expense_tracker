import 'package:expense_tracker/core/widgets/selectable_error_message.dart';
import 'package:expense_tracker/data/models/group.dart';
import 'package:expense_tracker/features/friends/repositories/api_friends_repository.dart';
import 'package:expense_tracker/features/groups/models/group_expense.dart';
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
        members: created.members,
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

  Future<void> _openGroupDetails(GroupSummary group) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            _GroupDetailsPage(group: group, repository: _repository),
      ),
    );
    if (changed == true && mounted) {
      await _loadGroups();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Align(
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
        ),
        if (_creating)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black26,
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        ),
                        SizedBox(width: 12),
                        Text('Creating group...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
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
  final _memberInputController = TextEditingController();
  late final http.Client _client;
  late final ApiFriendsRepository _friendsRepository;
  final List<_DialogMember> _members = <_DialogMember>[];
  String? _memberError;
  bool _resolvingMember = false;
  GroupType _type = GroupType.split;

  @override
  void initState() {
    super.initState();
    _client = http.Client();
    _friendsRepository = ApiFriendsRepository(client: _client);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _memberInputController.dispose();
    _client.close();
    super.dispose();
  }

  Future<void> _addMemberFromInput() async {
    if (_resolvingMember) return;
    final input = _memberInputController.text.trim();
    if (input.isEmpty) return;
    if (_members.any((m) => m.contact.toLowerCase() == input.toLowerCase())) {
      setState(() {
        _memberError = 'Member already added.';
        _memberInputController.clear();
      });
      return;
    }
    setState(() {
      _resolvingMember = true;
      _memberError = null;
    });
    try {
      final resolved = await _friendsRepository.resolveFriend(input);
      if (!mounted) return;
      if (!resolved.exists) {
        setState(() => _memberError = 'No user found for "$input".');
        return;
      }
      setState(() {
        _members.add(_DialogMember(contact: input, label: resolved.label));
        _memberInputController.clear();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _memberError = error.toString());
    } finally {
      if (mounted) {
        setState(() => _resolvingMember = false);
      }
    }
  }

  void _removeMember(_DialogMember member) {
    setState(() {
      _members.remove(member);
      _memberError = null;
    });
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    if (_memberInputController.text.trim().isNotEmpty) {
      await _addMemberFromInput();
      if (!mounted) return;
      if (_memberError != null) return;
    }

    final members = _members.map((m) => m.contact).toList(growable: false);
    final input = _CreateGroupInput(name: name, type: _type, members: members);
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
          TextField(
            controller: _memberInputController,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _addMemberFromInput(),
            decoration: InputDecoration(
              labelText: 'Add members (email or phone)',
              hintText: 'alice@example.com, +15551234567',
              errorText: _memberError,
              suffixIcon: _resolvingMember
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      onPressed: _addMemberFromInput,
                      icon: const Icon(Icons.add),
                    ),
            ),
          ),
          if (_members.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _members
                  .map(
                    (member) => InputChip(
                      label: Text(member.label),
                      onDeleted: () => _removeMember(member),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
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

class _GroupDetailsPage extends StatefulWidget {
  const _GroupDetailsPage({required this.group, required this.repository});

  final GroupSummary group;
  final ApiGroupsRepository repository;

  @override
  State<_GroupDetailsPage> createState() => _GroupDetailsPageState();
}

class _GroupDetailsPageState extends State<_GroupDetailsPage> {
  List<GroupExpense> _expenses = const [];
  bool _loading = true;
  _GroupBusyAction _busyAction = _GroupBusyAction.none;
  late int _memberCount;
  String? _error;

  bool get _busy => _busyAction != _GroupBusyAction.none;

  @override
  void initState() {
    super.initState();
    _memberCount = widget.group.memberCount;
    _loadExpenses();
  }

  Future<void> _loadExpenses() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.repository.fetchExpenses(widget.group.id);
      if (!mounted) return;
      setState(() => _expenses = items);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _leaveGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave group'),
        content: Text('Leave "${widget.group.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      setState(() => _busyAction = _GroupBusyAction.leavingGroup);
      final result = await widget.repository.leaveGroup(widget.group.id);
      if (!mounted) return;
      final deleted = result['deleted'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            deleted
                ? 'You left the group. Group was deleted.'
                : 'You left the group.',
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
      setState(() => _busyAction = _GroupBusyAction.none);
    }
  }

  Future<void> _addMember() async {
    final controller = TextEditingController();
    final contact = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add member'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Email or phone',
            hintText: 'friend@example.com or +15551234567',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (contact == null || contact.isEmpty || !mounted) return;
    setState(() => _busyAction = _GroupBusyAction.addingMember);
    try {
      final updated = await widget.repository.addMember(
        groupId: widget.group.id,
        emailOrPhone: contact,
      );
      if (!mounted) return;
      setState(() {
        _memberCount = updated.memberCount;
        _busyAction = _GroupBusyAction.none;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Member added.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
      setState(() => _busyAction = _GroupBusyAction.none);
    }
  }

  Future<void> _addExpense() async {
    final descriptionController = TextEditingController();
    final amountController = TextEditingController();
    final participants = List<String>.generate(
      _memberCount,
      (index) => index == 0 ? 'You' : 'Member ${index + 1}',
    );
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        var paidBy = participants.first;
        var splitMode = 'equally';
        var splitWithAll = true;
        final selected = participants.toSet();

        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Add group expense'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: descriptionController,
                    decoration: const InputDecoration(labelText: 'Description'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      prefixText: 'INR ',
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      const Text('Paid by'),
                      DropdownButton<String>(
                        value: paidBy,
                        items: participants
                            .map(
                              (p) => DropdownMenuItem<String>(
                                value: p,
                                child: Text(p),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => paidBy = value);
                        },
                      ),
                      const Text('and split'),
                      DropdownButton<String>(
                        value: splitMode,
                        items: const [
                          DropdownMenuItem(
                            value: 'equally',
                            child: Text('equally'),
                          ),
                          DropdownMenuItem(
                            value: 'custom',
                            child: Text('custom'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => splitMode = value);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Split with'),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('All members'),
                        selected: splitWithAll,
                        onSelected: (_) {
                          setDialogState(() {
                            splitWithAll = true;
                            selected
                              ..clear()
                              ..addAll(participants);
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Selected'),
                        selected: !splitWithAll,
                        onSelected: (_) {
                          setDialogState(() => splitWithAll = false);
                        },
                      ),
                    ],
                  ),
                  if (!splitWithAll) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: participants
                          .map(
                            (p) => FilterChip(
                              label: Text(p),
                              selected: selected.contains(p),
                              onSelected: (enabled) {
                                setDialogState(() {
                                  if (enabled) {
                                    selected.add(p);
                                  } else if (selected.length > 1) {
                                    selected.remove(p);
                                  }
                                });
                              },
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop({
                  'description': descriptionController.text.trim(),
                  'amount': double.tryParse(amountController.text.trim()),
                  'paidBy': paidBy,
                  'splitMode': splitMode,
                  'splitWith': selected.toList(growable: false),
                }),
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || payload == null) return;
    final description = (payload['description'] as String?) ?? '';
    final amount = payload['amount'] as double?;
    if (description.isEmpty || amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid description and amount.')),
      );
      return;
    }
    setState(() => _busyAction = _GroupBusyAction.addingExpense);
    try {
      await widget.repository.addExpense(
        groupId: widget.group.id,
        description: description,
        amount: amount,
        date: DateTime.now(),
      );
      if (!mounted) return;
      await _loadExpenses();
      if (!mounted) return;
      setState(() => _busyAction = _GroupBusyAction.none);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Group expense added.')));
    } catch (error) {
      if (!mounted) return;
      setState(() => _busyAction = _GroupBusyAction.none);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _expenses.fold<double>(0, (sum, e) => sum + e.amount);
    final busyMessage = switch (_busyAction) {
      _GroupBusyAction.addingMember => 'Adding member...',
      _GroupBusyAction.addingExpense => 'Saving expense...',
      _GroupBusyAction.leavingGroup => 'Leaving group...',
      _GroupBusyAction.none => '',
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.group.name),
        actions: [
          IconButton(
            onPressed: _busy ? null : _addMember,
            icon: const Icon(Icons.person_add_alt_1_outlined),
            tooltip: 'Add member',
          ),
          TextButton(
            onPressed: _busy ? null : _leaveGroup,
            child: Text(
              'Leave group',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _addExpense,
        icon: const Icon(Icons.receipt_long_outlined),
        label: const Text('Add expense'),
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              children: [
                Card(
                  child: ListTile(
                    title: Text(
                      widget.group.groupType == GroupType.family
                          ? 'Family monthly spend'
                          : 'Group total spend',
                    ),
                    subtitle: Text('$_memberCount member(s)'),
                    trailing: Text(
                      'INR ${total.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_loading)
                  const Card(
                    child: ListTile(title: Text('Loading group expenses...')),
                  )
                else if (_error != null)
                  SelectableErrorMessage(_error!)
                else if (_expenses.isEmpty)
                  const Card(
                    child: ListTile(
                      title: Text('No group expenses yet'),
                      subtitle: Text(
                        'Use the receipt icon in top-right to add the first group expense.',
                      ),
                    ),
                  )
                else
                  ..._expenses.map(
                    (expense) => Card(
                      child: ListTile(
                        title: Text(expense.description),
                        subtitle: Text(
                          expense.date.toLocal().toString().split('.').first,
                        ),
                        trailing: Text(
                          'INR ${expense.amount.toStringAsFixed(2)}',
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_busy)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Material(
                elevation: 1,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(
                      minHeight: 3,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text(
                        busyMessage,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

enum _GroupBusyAction { none, addingMember, addingExpense, leavingGroup }

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
  const _CreateGroupInput({
    required this.name,
    required this.type,
    required this.members,
  });

  final String name;
  final GroupType type;
  final List<String> members;
}

class _DialogMember {
  const _DialogMember({required this.contact, required this.label});

  final String contact;
  final String label;
}
