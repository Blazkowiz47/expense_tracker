import 'package:expense_tracker/core/widgets/selectable_error_message.dart';
import 'package:expense_tracker/data/models/group.dart';
import 'package:expense_tracker/features/auth/cubit/auth_cubit.dart';
import 'package:expense_tracker/features/friends/repositories/api_friends_repository.dart';
import 'package:expense_tracker/features/groups/models/group_expense.dart';
import 'package:expense_tracker/features/groups/models/group_member.dart';
import 'package:expense_tracker/features/groups/models/group_summary.dart';
import 'package:expense_tracker/features/groups/repositories/api_groups_repository.dart';
import 'package:expense_tracker/features/groups/utils/group_balance_calculator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
        builder: (_) => GroupDetailsPage(group: group, repository: _repository),
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

class GroupDetailsPage extends StatefulWidget {
  const GroupDetailsPage({
    required this.group,
    required this.repository,
    super.key,
  });

  final GroupSummary group;
  final ApiGroupsRepository repository;

  @override
  State<GroupDetailsPage> createState() => _GroupDetailsPageState();
}

class _GroupDetailsPageState extends State<GroupDetailsPage> {
  List<GroupExpense> _expenses = const [];
  List<GroupMember> _members = const [];
  bool _loading = true;
  _GroupBusyAction _busyAction = _GroupBusyAction.none;
  late int _memberCount;
  String? _error;

  bool get _busy => _busyAction != _GroupBusyAction.none;

  Set<String> _currentUserIdentifiers({
    required String uid,
    String? email,
    String? displayName,
    String? phone,
  }) {
    final identifiers = <String>{uid.trim().toLowerCase()};
    if (email != null && email.trim().isNotEmpty) {
      identifiers.add(email.trim().toLowerCase());
    }
    if (displayName != null && displayName.trim().isNotEmpty) {
      identifiers.add(displayName.trim().toLowerCase());
    }
    if (phone != null && phone.trim().isNotEmpty) {
      identifiers.add(phone.trim().toLowerCase());
    }

    for (final member in _members) {
      if (member.uid == uid) {
        if (member.uid.trim().isNotEmpty) {
          identifiers.add(member.uid.trim().toLowerCase());
        }
        if (member.displayName.trim().isNotEmpty) {
          identifiers.add(member.displayName.trim().toLowerCase());
        }
        if (member.email.trim().isNotEmpty) {
          identifiers.add(member.email.trim().toLowerCase());
        }
        if (member.phone.trim().isNotEmpty) {
          identifiers.add(member.phone.trim().toLowerCase());
        }
      }
    }
    return identifiers;
  }

  ({double owed, double owe}) _balanceForExpense({
    required GroupExpense expense,
    required Set<String> userIdentifiers,
    required int memberCount,
  }) {
    if (memberCount <= 0 || userIdentifiers.isEmpty || expense.amount <= 0) {
      return (owed: 0, owe: 0);
    }
    final createdBy = expense.createdBy.trim().toLowerCase();
    final share = expense.amount / memberCount;
    if (userIdentifiers.contains(createdBy)) {
      return (owed: expense.amount - share, owe: 0);
    }
    return (owed: 0, owe: share);
  }

  Future<_SplitSelectionResult?> _openSplitOptionsPage({
    required List<String> participants,
    required Set<String> selectedMembers,
    required String currentMode,
    required double totalAmount,
  }) {
    return Navigator.of(context).push<_SplitSelectionResult>(
      MaterialPageRoute<_SplitSelectionResult>(
        builder: (_) => _SplitOptionsPage(
          participants: participants,
          selectedMembers: selectedMembers,
          currentMode: currentMode,
          totalAmount: totalAmount,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _memberCount = widget.group.memberCount;
    _loadData();
  }

  Future<void> _loadData() async {
    await Future.wait([_loadMembers(), _loadExpenses()]);
  }

  Future<bool> _loadMembers() async {
    try {
      final items = await widget.repository.fetchMembers(widget.group.id);
      if (!mounted) return false;
      setState(() {
        _members = items;
        _memberCount = items.length;
      });
      return true;
    } catch (_) {
      return false;
    }
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
      await _loadMembers();
      if (!mounted) return;
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

  Future<String?> _promptAttachmentUrl() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Attach bill photo'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Image URL',
            hintText: 'https://...',
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
  }

  Future<Map<String, dynamic>?> _showExpenseForm({
    required String title,
    required List<String> participants,
    String? initialDescription,
    double? initialAmount,
    String? initialPaidBy,
    String initialSplitMode = 'equally',
    Set<String>? initialSplitWith,
    List<String>? initialAttachments,
  }) {
    final descriptionController = TextEditingController(
      text: initialDescription ?? '',
    );
    final amountController = TextEditingController(
      text: initialAmount == null ? '' : initialAmount.toStringAsFixed(2),
    );
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        final screenWidth = MediaQuery.sizeOf(context).width;
        final dialogWidth = (screenWidth * 0.72).clamp(360.0, 920.0);
        var paidBy = initialPaidBy ?? participants.first;
        var splitMode = initialSplitMode;
        final selected = {...(initialSplitWith ?? participants)};
        var splitWithAll = selected.length == participants.length;
        final attachments = [...?initialAttachments];

        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
            title: Text(title),
            content: SingleChildScrollView(
              child: SizedBox(
                width: dialogWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                      ),
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
                        ActionChip(
                          label: Text(paidBy),
                          onPressed: () async {
                            final chosen = await Navigator.of(context)
                                .push<String>(
                                  MaterialPageRoute<String>(
                                    builder: (_) => _ChoosePayerPage(
                                      participants: participants,
                                      currentPayer: paidBy,
                                    ),
                                  ),
                                );
                            if (chosen == null) return;
                            setDialogState(() => paidBy = chosen);
                          },
                        ),
                        const Text('and split'),
                        ActionChip(
                          label: Text(splitMode),
                          onPressed: () async {
                            final result = await _openSplitOptionsPage(
                              participants: participants,
                              selectedMembers: selected,
                              currentMode: splitMode,
                              totalAmount:
                                  double.tryParse(
                                    amountController.text.trim(),
                                  ) ??
                                  0,
                            );
                            if (result == null) return;
                            setDialogState(() {
                              splitMode = result.mode;
                              selected
                                ..clear()
                                ..addAll(result.selectedMembers);
                              splitWithAll =
                                  selected.length == participants.length;
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        const Text('Split with'),
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
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Attachments',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ...attachments.asMap().entries.map(
                          (entry) => Chip(
                            label: Text('Bill ${entry.key + 1}'),
                            onDeleted: () {
                              setDialogState(
                                () => attachments.removeAt(entry.key),
                              );
                            },
                          ),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.attach_file, size: 16),
                          label: const Text('Add URL'),
                          onPressed: () async {
                            final url = await _promptAttachmentUrl();
                            if (url == null || url.isEmpty) return;
                            setDialogState(() => attachments.add(url));
                          },
                        ),
                      ],
                    ),
                  ],
                ),
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
                  'attachments': attachments,
                }),
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _addExpense() async {
    if (_members.isEmpty && _memberCount > 0) {
      await _loadMembers();
      if (!mounted) return;
    }
    final participants = _members.isNotEmpty
        ? _members.map((m) => m.label).toList(growable: false)
        : List<String>.generate(
            _memberCount,
            (index) => index == 0 ? 'You' : 'Member ${index + 1}',
          );

    final payload = await _showExpenseForm(
      title: 'Add group expense',
      participants: participants,
      initialSplitWith: participants.toSet(),
    );
    if (!mounted || payload == null) return;
    final description = (payload['description'] as String?) ?? '';
    final amount = payload['amount'] as double?;
    final attachments = (payload['attachments'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList(growable: false);
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
        attachments: attachments,
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

  Future<void> _editExpense(GroupExpense expense) async {
    if (_members.isEmpty && _memberCount > 0) {
      await _loadMembers();
      if (!mounted) return;
    }
    final participants = _members.isNotEmpty
        ? _members.map((m) => m.label).toList(growable: false)
        : List<String>.generate(
            _memberCount,
            (index) => index == 0 ? 'You' : 'Member ${index + 1}',
          );
    final payload = await _showExpenseForm(
      title: 'Edit group expense',
      participants: participants,
      initialDescription: expense.description,
      initialAmount: expense.amount,
      initialSplitWith: participants.toSet(),
      initialAttachments: expense.attachments,
    );

    if (!mounted || payload == null) return;
    final description = (payload['description'] as String?) ?? '';
    final amount = payload['amount'] as double?;
    final attachments = (payload['attachments'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList(growable: false);
    if (description.isEmpty || amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid description and amount.')),
      );
      return;
    }

    setState(() => _busyAction = _GroupBusyAction.addingExpense);
    try {
      await widget.repository.updateExpense(
        groupId: widget.group.id,
        expenseId: expense.id,
        description: description,
        amount: amount,
        attachments: attachments,
        date: expense.date,
      );
      if (!mounted) return;
      await _loadExpenses();
      if (!mounted) return;
      setState(() => _busyAction = _GroupBusyAction.none);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Group expense updated.')));
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
    final authUser = context.select((AuthCubit cubit) => cubit.state.user);
    final total = _expenses.fold<double>(0, (sum, e) => sum + e.amount);
    final memberCount = _members.isNotEmpty ? _members.length : _memberCount;
    final userIdentifiers = authUser == null
        ? <String>{}
        : _currentUserIdentifiers(
            uid: authUser.uid,
            email: authUser.email,
            displayName: authUser.displayName,
            phone: authUser.phoneNumber,
          );
    final balance = authUser == null
        ? (lent: 0.0, borrowed: 0.0)
        : calculateGroupLentBorrowed(
            expenses: _expenses,
            memberCount: memberCount,
            userIdentifiers: userIdentifiers,
          );
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
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('$_memberCount member(s)'),
                        if (balance.lent > 0.005 || balance.borrowed > 0.005)
                          const SizedBox(height: 4),
                        if (balance.lent > 0.005)
                          Text(
                            'You are owed INR ${balance.lent.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        if (balance.borrowed > 0.005)
                          Text(
                            'You owe INR ${balance.borrowed.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                      ],
                    ),
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
                  ..._expenses.map((expense) {
                    final expenseBalance = _balanceForExpense(
                      expense: expense,
                      userIdentifiers: userIdentifiers,
                      memberCount: memberCount,
                    );
                    return Card(
                      child: ListTile(
                        onTap: _busy ? null : () => _editExpense(expense),
                        title: Text(expense.description),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              expense.date
                                  .toLocal()
                                  .toString()
                                  .split('.')
                                  .first,
                            ),
                            if (expense.attachments.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 52,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: expense.attachments.length,
                                  itemBuilder: (context, index) {
                                    final url = expense.attachments[index];
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          url,
                                          width: 52,
                                          height: 52,
                                          fit: BoxFit.cover,
                                          loadingBuilder:
                                              (
                                                context,
                                                child,
                                                loadingProgress,
                                              ) {
                                                if (loadingProgress == null) {
                                                  return child;
                                                }
                                                return Container(
                                                  width: 52,
                                                  height: 52,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .surfaceContainerHighest,
                                                  child: const Center(
                                                    child: SizedBox(
                                                      width: 16,
                                                      height: 16,
                                                      child:
                                                          CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                          ),
                                                    ),
                                                  ),
                                                );
                                              },
                                          errorBuilder:
                                              (
                                                context,
                                                _,
                                                errorDetails,
                                              ) => Container(
                                                width: 52,
                                                height: 52,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .surfaceContainerHighest,
                                                child: const Icon(
                                                  Icons.broken_image_outlined,
                                                  size: 18,
                                                ),
                                              ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ],
                        ),
                        trailing: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('INR ${expense.amount.toStringAsFixed(2)}'),
                            if (expenseBalance.owed > 0.005)
                              Text(
                                'owed ${expenseBalance.owed.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            if (expenseBalance.owe > 0.005)
                              Text(
                                'owe ${expenseBalance.owe.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
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

class _SplitSelectionResult {
  const _SplitSelectionResult({
    required this.mode,
    required this.selectedMembers,
  });

  final String mode;
  final Set<String> selectedMembers;
}

class _SplitOptionsPage extends StatefulWidget {
  const _SplitOptionsPage({
    required this.participants,
    required this.selectedMembers,
    required this.currentMode,
    required this.totalAmount,
  });

  final List<String> participants;
  final Set<String> selectedMembers;
  final String currentMode;
  final double totalAmount;

  @override
  State<_SplitOptionsPage> createState() => _SplitOptionsPageState();
}

class _SplitOptionsPageState extends State<_SplitOptionsPage> {
  late String _mode;
  late Set<String> _selected;
  String? _lastEditedExactMember;
  String? _lastEditedPercentMember;
  String? _lastEditedAdjustmentMember;
  final Map<String, TextEditingController> _exactControllers = {};
  final Map<String, TextEditingController> _percentControllers = {};
  final Map<String, TextEditingController> _sharesControllers = {};
  final Map<String, TextEditingController> _adjustmentControllers = {};

  @override
  void initState() {
    super.initState();
    _mode = 'equally';
    _selected = {...widget.selectedMembers};
    if (_selected.isEmpty && widget.participants.isNotEmpty) {
      _selected = {widget.participants.first};
    }
    for (final member in widget.participants) {
      _exactControllers[member] = TextEditingController();
      _percentControllers[member] = TextEditingController();
      _sharesControllers[member] = TextEditingController();
      _adjustmentControllers[member] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final controller in _exactControllers.values) {
      controller.dispose();
    }
    for (final controller in _percentControllers.values) {
      controller.dispose();
    }
    for (final controller in _sharesControllers.values) {
      controller.dispose();
    }
    for (final controller in _adjustmentControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _toggleMember(String member, bool selected) {
    setState(() {
      if (selected) {
        _selected.add(member);
      } else if (_selected.length > 1) {
        _selected.remove(member);
      }
    });
  }

  String _formatCurrency(double value) {
    return value.toStringAsFixed(2).replaceAll('.', ',');
  }

  double _parseLocalizedDouble(String raw) {
    final normalized = raw.trim().replaceAll(' ', '').replaceAll(',', '.');
    return double.tryParse(normalized) ?? 0;
  }

  double _exactEnteredTotal() {
    var sum = 0.0;
    for (final member in widget.participants) {
      sum += _parseLocalizedDouble(_exactControllers[member]?.text ?? '');
    }
    return sum;
  }

  double _percentEnteredTotal() {
    var sum = 0.0;
    for (final member in widget.participants) {
      sum += _parseLocalizedDouble(_percentControllers[member]?.text ?? '');
    }
    return sum;
  }

  int _sharesEnteredTotal() {
    var sum = 0;
    for (final member in widget.participants) {
      final raw = _sharesControllers[member]?.text.trim() ?? '';
      sum += int.tryParse(raw) ?? 0;
    }
    return sum;
  }

  double _adjustmentEnteredTotal() {
    var sum = 0.0;
    for (final member in widget.participants) {
      sum += _parseLocalizedDouble(_adjustmentControllers[member]?.text ?? '');
    }
    return sum;
  }

  bool _isExactTotalMismatch() {
    if (_mode != 'exact' || widget.totalAmount <= 0) {
      return false;
    }
    return (_exactEnteredTotal() - widget.totalAmount).abs() > 0.005;
  }

  bool _isExactOverAllocated() {
    if (_mode != 'exact' || widget.totalAmount <= 0) {
      return false;
    }
    return _exactEnteredTotal() - widget.totalAmount > 0.005;
  }

  bool _isPercentOverAllocated() {
    if (_mode != 'percent') {
      return false;
    }
    return _percentEnteredTotal() - 100 > 0.05;
  }

  bool _isAdjustmentOverAllocated() {
    if (_mode != 'adjustment' || widget.totalAmount <= 0) {
      return false;
    }
    return _adjustmentEnteredTotal() - widget.totalAmount > 0.005;
  }

  String _titleForMode() {
    switch (_mode) {
      case 'exact':
        return 'Split by exact amounts';
      case 'percent':
        return 'Split by percentages';
      case 'shares':
        return 'Split by shares';
      case 'adjustment':
        return 'Split by adjustment';
      case 'equally':
      default:
        return 'Split equally';
    }
  }

  String _subtitleForMode() {
    switch (_mode) {
      case 'exact':
        return 'Specify exactly how much each person owes.';
      case 'percent':
        return 'Enter the percentage split that is fair for your situation.';
      case 'shares':
        return 'Great for time-based splitting and family ratios.';
      case 'adjustment':
        return 'Adjust who owes extra; remainder is split equally.';
      case 'equally':
      default:
        return 'Select which people owe an equal share.';
    }
  }

  Widget _buildModeTab(
    BuildContext context,
    String mode,
    String label,
    IconData icon,
  ) {
    final selected = _mode == mode;
    return InkWell(
      onTap: () => setState(() => _mode = mode),
      child: Container(
        width: 58,
        height: 34,
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        alignment: Alignment.center,
        child: label.isEmpty
            ? Icon(
                icon,
                size: 18,
                color: selected
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              )
            : Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? Theme.of(context).colorScheme.onPrimary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
      ),
    );
  }

  Widget _buildParticipantRow(BuildContext context, String member, int index) {
    final selected = _selected.contains(member);
    final colorChoices = <Color>[
      const Color(0xFF6EC8AA),
      const Color(0xFF4DA58E),
      const Color(0xFFE39A6B),
      const Color(0xFF4F7AA2),
    ];
    final avatarColor = colorChoices[index % colorChoices.length];

    Widget trailing;
    switch (_mode) {
      case 'exact':
        final mismatch = _isExactTotalMismatch();
        final overAllocated = _isExactOverAllocated();
        final editedMember = _lastEditedExactMember;
        final showErrorForThisMember =
            mismatch &&
            editedMember != null &&
            member != editedMember &&
            widget.participants.length > 1;
        final showInlineOverflowError =
            overAllocated && editedMember != null && member == editedMember;
        final errorColor = Theme.of(context).colorScheme.error;
        trailing = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '₹ ',
              style: TextStyle(
                color: showErrorForThisMember ? errorColor : Colors.grey,
              ),
            ),
            SizedBox(
              width: 78,
              child: TextField(
                controller: _exactControllers[member],
                onChanged: (_) {
                  setState(() {
                    _lastEditedExactMember = member;
                  });
                },
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: showErrorForThisMember ? errorColor : null,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '0,00',
                  border: const UnderlineInputBorder(),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: showErrorForThisMember
                          ? errorColor
                          : Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: showErrorForThisMember || showInlineOverflowError
                          ? errorColor
                          : Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  errorText: showInlineOverflowError ? 'Exceeds total' : null,
                ),
              ),
            ),
          ],
        );
        break;
      case 'percent':
        final overAllocated = _isPercentOverAllocated();
        final showInlineOverflowError =
            overAllocated &&
            _lastEditedPercentMember != null &&
            member == _lastEditedPercentMember;
        final errorColor = Theme.of(context).colorScheme.error;
        trailing = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 68,
              child: TextField(
                controller: _percentControllers[member],
                onChanged: (_) {
                  setState(() {
                    _lastEditedPercentMember = member;
                  });
                },
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: showInlineOverflowError ? errorColor : null,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '0',
                  border: const UnderlineInputBorder(),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: showInlineOverflowError
                          ? errorColor
                          : Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: showInlineOverflowError
                          ? errorColor
                          : Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  errorText: showInlineOverflowError ? 'Exceeds 100%' : null,
                ),
              ),
            ),
            const SizedBox(width: 2),
            Text(
              '%',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ],
        );
        break;
      case 'shares':
        trailing = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 54,
              child: TextField(
                controller: _sharesControllers[member],
                onChanged: (_) => setState(() {}),
                keyboardType: TextInputType.number,
                textAlign: TextAlign.right,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '0',
                  border: UnderlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Text('share(s)'),
          ],
        );
        break;
      case 'adjustment':
        final overAllocated = _isAdjustmentOverAllocated();
        final showInlineOverflowError =
            overAllocated &&
            _lastEditedAdjustmentMember != null &&
            member == _lastEditedAdjustmentMember;
        final errorColor = Theme.of(context).colorScheme.error;
        trailing = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '+ ',
              style: TextStyle(
                color: showInlineOverflowError ? errorColor : Colors.grey,
              ),
            ),
            SizedBox(
              width: 78,
              child: TextField(
                controller: _adjustmentControllers[member],
                onChanged: (_) {
                  setState(() {
                    _lastEditedAdjustmentMember = member;
                  });
                },
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: showInlineOverflowError ? errorColor : null,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '0,00',
                  border: const UnderlineInputBorder(),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: showInlineOverflowError
                          ? errorColor
                          : Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: showInlineOverflowError
                          ? errorColor
                          : Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  errorText: showInlineOverflowError ? 'Exceeds total' : null,
                ),
              ),
            ),
          ],
        );
        break;
      case 'equally':
      default:
        trailing = Icon(
          Icons.check_circle,
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outline,
          size: 20,
        );
    }

    return InkWell(
      onTap: () => _toggleMember(member, !selected),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: avatarColor,
              child: Text(
                member.isNotEmpty ? member[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Text(member, style: const TextStyle(fontSize: 16))],
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final perPerson = (_selected.isEmpty || widget.totalAmount <= 0)
        ? 0.0
        : widget.totalAmount / _selected.length;
    final enteredExact = _exactEnteredTotal();
    final enteredPercent = _percentEnteredTotal();
    final enteredShares = _sharesEnteredTotal();
    final enteredAdjustment = _adjustmentEnteredTotal();
    final exactRemaining = widget.totalAmount - enteredExact;
    final percentRemaining = 100 - enteredPercent;
    final sharesRemaining = widget.participants.length - enteredShares;
    final adjustmentRemaining = widget.totalAmount - enteredAdjustment;

    String footerTitle;
    String footerSubtitle;
    bool footerError;
    switch (_mode) {
      case 'exact':
        footerTitle =
            '₹ ${_formatCurrency(enteredExact)} of ₹ ${_formatCurrency(widget.totalAmount)}';
        footerSubtitle = exactRemaining < 0
            ? '₹ 0,00 left'
            : '₹ ${_formatCurrency(exactRemaining)} left';
        footerError = exactRemaining.abs() > 0.005 && exactRemaining >= 0;
        break;
      case 'percent':
        footerTitle = '${enteredPercent.toStringAsFixed(0)}% of 100%';
        footerSubtitle = percentRemaining < 0
            ? '0% left'
            : '${percentRemaining.toStringAsFixed(0)}% left';
        footerError = percentRemaining.abs() > 0.05 && percentRemaining >= 0;
        break;
      case 'shares':
        footerTitle = '$enteredShares total shares';
        footerSubtitle = '$sharesRemaining share(s) remaining';
        footerError = sharesRemaining != 0;
        break;
      case 'adjustment':
        footerTitle =
            '₹ ${_formatCurrency(enteredAdjustment)} of ₹ ${_formatCurrency(widget.totalAmount)}';
        footerSubtitle = adjustmentRemaining < 0
            ? '₹ 0,00 left'
            : '₹ ${_formatCurrency(adjustmentRemaining)} left';
        footerError =
            adjustmentRemaining.abs() > 0.005 && adjustmentRemaining >= 0;
        break;
      case 'equally':
      default:
        footerTitle = '₹ ${_formatCurrency(perPerson)}/person';
        footerSubtitle = '(${_selected.length} people)';
        footerError = false;
    }

    return Scaffold(
      appBar: AppBar(
        leading: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        leadingWidth: 80,
        title: const Text('Split options'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(
                _SplitSelectionResult(mode: _mode, selectedMembers: _selected),
              );
            },
            child: const Text('Done'),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: const [
                _SplitMascot(
                  color: Color(0xFF9BDDD0),
                  icon: Icons.icecream_outlined,
                ),
                _SplitMascot(
                  color: Color(0xFF6CA6D9),
                  icon: Icons.pets_outlined,
                ),
                _SplitMascot(
                  color: Color(0xFFD96D8A),
                  icon: Icons.pets_outlined,
                ),
                _SplitMascot(
                  color: Color(0xFF9E80D9),
                  icon: Icons.pets_outlined,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _titleForMode(),
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              _subtitleForMode(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildModeTab(context, 'equally', '=', Icons.drag_handle),
                _buildModeTab(context, 'exact', '1.23', Icons.tag),
                _buildModeTab(context, 'percent', '%', Icons.percent),
                _buildModeTab(context, 'shares', '', Icons.bar_chart),
                _buildModeTab(context, 'adjustment', '+/-', Icons.tune),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ...widget.participants.asMap().entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _buildParticipantRow(context, entry.value, entry.key),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      footerTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      footerSubtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: footerError
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Text('All'),
                    const SizedBox(width: 6),
                    Icon(
                      _selected.length == widget.participants.length
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: Theme.of(context).colorScheme.primary,
                      size: 18,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SplitMascot extends StatelessWidget {
  const _SplitMascot({required this.color, required this.icon});

  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, color: Colors.white),
    );
  }
}

class _ChoosePayerPage extends StatelessWidget {
  const _ChoosePayerPage({
    required this.participants,
    required this.currentPayer,
  });

  final List<String> participants;
  final String currentPayer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        leadingWidth: 80,
        title: const Text('Choose payer'),
      ),
      body: ListView(
        children: [
          ...participants.map(
            (name) => ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              title: Text(name),
              trailing: name == currentPayer
                  ? Icon(
                      Icons.check,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : null,
              onTap: () => Navigator.of(context).pop(name),
            ),
          ),
        ],
      ),
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
