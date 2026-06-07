import 'package:expense_tracker/core/ui/app_ui.dart';
import 'package:expense_tracker/core/utils/date_formatter.dart';
import 'package:expense_tracker/core/widgets/selectable_error_message.dart';
import 'package:expense_tracker/data/models/expense.dart';
import 'package:expense_tracker/data/models/expense_core.dart';
import 'package:expense_tracker/data/models/group.dart';
import 'package:expense_tracker/data/repositories/expenses_repository.dart';
import 'package:expense_tracker/features/auth/cubit/auth_cubit.dart';
import 'package:expense_tracker/features/expenses/repositories/bill_ai_repository.dart';
import 'package:expense_tracker/features/friends/repositories/api_friends_repository.dart';
import 'package:expense_tracker/features/groups/models/group_expense.dart';
import 'package:expense_tracker/features/groups/models/group_member.dart';
import 'package:expense_tracker/features/groups/models/group_summary.dart';
import 'package:expense_tracker/features/groups/repositories/api_groups_repository.dart';
import 'package:expense_tracker/features/groups/utils/group_balance_calculator.dart';
import 'package:expense_tracker/features/groups/utils/group_transfer_simplifier.dart';
import 'package:expense_tracker/features/planning/models/monthly_category_catalog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';

const _groupCurrencyOptions = <String>['INR', 'USD', 'EUR', 'GBP', 'NOK'];

String _normalizedGroupCurrency(String value) {
  final normalized = value.trim().toUpperCase();
  return _groupCurrencyOptions.contains(normalized) ? normalized : 'INR';
}

List<String> _normalizedGroupCurrencies(Iterable<String> values) {
  return values.map(_normalizedGroupCurrency).toSet().toList(growable: false);
}

class GroupsPage extends StatefulWidget {
  const GroupsPage({
    this.groupType = GroupType.split,
    this.repository,
    this.client,
    this.autoRefresh = false,
    super.key,
  });

  final GroupType groupType;
  final ApiGroupsRepository? repository;
  final http.Client? client;
  final bool autoRefresh;

  @override
  State<GroupsPage> createState() => _GroupsPageState();
}

class _GroupsPageState extends State<GroupsPage> {
  http.Client? _ownedClient;
  late final ApiGroupsRepository _repository;
  List<GroupSummary> _groups = const [];
  bool _loading = true;
  bool _creating = false;
  String? _error;

  bool get _isFamily => widget.groupType == GroupType.family;

  String get _sectionTitle => _isFamily ? 'Family' : 'Groups';

  String get _createActionLabel =>
      _isFamily ? 'Create family group' : 'Create group';

  String get _emptyTitle => _isFamily ? 'No family group yet' : 'No groups yet';

  String get _emptySubtitle => _isFamily
      ? 'Create a family group to track household spending.'
      : 'Create a group to split expenses with others.';

  String get _creatingMessage =>
      _isFamily ? 'Creating family group...' : 'Creating group...';

  String get _createdMessage =>
      _isFamily ? 'Family group created.' : 'Group created.';

  @override
  void initState() {
    super.initState();
    final client = widget.client ?? http.Client();
    if (widget.repository == null && widget.client == null) {
      _ownedClient = client;
    }
    _repository = widget.repository ?? ApiGroupsRepository(client: client);
    _loadGroups();
  }

  @override
  void dispose() {
    _ownedClient?.close();
    super.dispose();
  }

  List<GroupSummary> _filterGroups(List<GroupSummary> groups) {
    return groups
        .where((group) => group.groupType == widget.groupType)
        .toList(growable: false);
  }

  Future<void> _loadGroups({bool showLoading = true}) async {
    setState(() {
      _loading = showLoading || _groups.isEmpty;
      _error = null;
    });
    var hadCached = false;
    try {
      final cachedGroups = await _repository.getCachedGroups();
      if (!mounted) return;
      if (cachedGroups.isNotEmpty) {
        hadCached = true;
        setState(() => _groups = _filterGroups(cachedGroups));
      }
      final groups = await _repository.fetchGroups();
      if (!mounted) return;
      setState(() => _groups = _filterGroups(groups));
    } catch (error) {
      if (!mounted) return;
      if (!hadCached && (showLoading || _groups.isEmpty)) {
        setState(() => _error = error.toString());
      }
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
      builder: (context) => _CreateGroupDialog(
        initialType: widget.groupType,
        title: _createActionLabel,
      ),
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
      ).showSnackBar(SnackBar(content: Text(_createdMessage)));
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
        builder: (_) => GroupDetailsPage(
          group: group,
          repository: _repository,
          autoRefresh: true,
        ),
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
        AppPageContainer(
          onRefresh: () => _loadGroups(showLoading: false),
          autoRefresh: widget.autoRefresh,
          children: [
            AppSectionHeader(
              title: _sectionTitle,
              actionLabel: _createActionLabel,
              onAction: _creating ? null : _openCreateGroupDialog,
            ),
            if (_loading)
              const AppBalanceTile(
                title: 'Loading groups...',
                leadingIcon: Icons.group_outlined,
              )
            else if (_error != null)
              SelectableErrorMessage(_error!)
            else if (_groups.isEmpty)
              AppEmptyState(
                title: _emptyTitle,
                subtitle: _emptySubtitle,
                actionLabel: _createActionLabel,
                onAction: _openCreateGroupDialog,
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
        if (_creating)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black26,
              child: Center(
                child: AppCard(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        ),
                        const SizedBox(width: 12),
                        Text(_creatingMessage),
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

class _CreateGroupDialog extends StatefulWidget {
  const _CreateGroupDialog({required this.initialType, required this.title});

  final GroupType initialType;
  final String title;

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
  late GroupType _type;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
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
      title: Text(widget.title),
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
    this.initialExpenseId,
    this.initialAddExpense = false,
    this.initialExpenseCategory = 'Groceries',
    this.initialExpenseDescription,
    this.initialBillUpload = false,
    this.autoRefresh = false,
    super.key,
  });

  final GroupSummary group;
  final ApiGroupsRepository repository;
  final String? initialExpenseId;
  final bool initialAddExpense;
  final String initialExpenseCategory;
  final String? initialExpenseDescription;
  final bool initialBillUpload;
  final bool autoRefresh;

  @override
  State<GroupDetailsPage> createState() => _GroupDetailsPageState();
}

class _GroupDetailsPageState extends State<GroupDetailsPage> {
  List<GroupExpense> _expenses = const [];
  List<GroupMember> _members = const [];
  bool _loading = true;
  bool _simplifyBalances = true;
  _GroupBusyAction _busyAction = _GroupBusyAction.none;
  bool _didMutateGroupData = false;
  bool _didOpenInitialExpense = false;
  late int _memberCount;
  String? _error;
  final _billRepository = BillAiRepository();
  final _billPicker = ImagePicker();

  bool get _busy => _busyAction != _GroupBusyAction.none;

  List<String> _expenseParticipantKeys() {
    if (_members.isEmpty) {
      return List<String>.generate(
        _memberCount,
        (index) => index == 0 ? 'You' : 'Member ${index + 1}',
      );
    }
    final labelCounts = <String, int>{};
    for (final member in _members) {
      final label = member.label.trim();
      labelCounts[label] = (labelCounts[label] ?? 0) + 1;
    }
    return _members
        .map((member) {
          final label = member.label.trim();
          final labelIsAmbiguous = (labelCounts[label] ?? 0) > 1;
          if (labelIsAmbiguous && member.email.trim().isNotEmpty) {
            return member.email.trim();
          }
          return label.isNotEmpty ? label : member.uid;
        })
        .toList(growable: false);
  }

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
    final paidBy =
        (expense.paidBy.isNotEmpty ? expense.paidBy : expense.createdBy)
            .trim()
            .toLowerCase();
    final splitAmounts = _normalizedSplitAmounts(expense.splitAmounts);
    if (splitAmounts.isNotEmpty) {
      final userShare = splitAmounts.entries
          .where((entry) => userIdentifiers.contains(entry.key))
          .fold<double>(0, (sum, entry) => sum + entry.value);
      if (userIdentifiers.contains(paidBy)) {
        return (owed: expense.amount - userShare, owe: 0);
      }
      return (owed: 0, owe: userShare);
    }

    final splitParticipants = expense.splitWith
        .map((id) => id.trim().toLowerCase())
        .where((id) => id.isNotEmpty)
        .toSet();
    final splitCount = splitParticipants.isEmpty
        ? memberCount
        : splitParticipants.length;
    final userIsInSplit =
        splitParticipants.isEmpty ||
        splitParticipants.any((id) => userIdentifiers.contains(id));
    final share = expense.amount / splitCount;
    if (userIdentifiers.contains(paidBy)) {
      return (owed: expense.amount - (userIsInSplit ? share : 0), owe: 0);
    }
    return (owed: 0, owe: userIsInSplit ? share : 0);
  }

  Map<String, double> _normalizedSplitAmounts(Map<String, double> amounts) {
    final normalized = <String, double>{};
    for (final entry in amounts.entries) {
      final key = entry.key.trim().toLowerCase();
      if (key.isEmpty || entry.value <= 0) continue;
      normalized[key] = (normalized[key] ?? 0) + entry.value;
    }
    return normalized;
  }

  Map<String, double> _splitAmountsFromPayload(Object? value) {
    if (value is! Map) {
      return const {};
    }
    final amounts = <String, double>{};
    for (final entry in value.entries) {
      final key = entry.key?.toString().trim() ?? '';
      final amount = entry.value is num
          ? (entry.value as num).toDouble()
          : double.tryParse(entry.value?.toString() ?? '');
      if (key.isNotEmpty && amount != null && amount > 0) {
        amounts[key] = amount;
      }
    }
    return amounts;
  }

  Map<String, double> _splitAmountsForParticipantLabels(
    Map<String, double> amounts,
    List<String> participants,
  ) {
    if (amounts.isEmpty) {
      return const {};
    }
    final labeled = <String, double>{};
    for (final entry in amounts.entries) {
      labeled[_resolvePayerLabel(entry.key, participants)] = entry.value;
    }
    return labeled;
  }

  bool _splitAmountsMatchTotal(Map<String, double> amounts, double total) {
    if (amounts.isEmpty) {
      return true;
    }
    final splitTotal = amounts.values.fold<double>(
      0,
      (sum, item) => sum + item,
    );
    return (splitTotal - total).abs() <= 0.005;
  }

  Map<String, double> _totalAmountsByCurrency(List<GroupExpense> expenses) {
    final totals = <String, double>{};
    for (final expense in expenses) {
      for (final entry in expense.amountsByCurrency.entries) {
        totals[entry.key] = (totals[entry.key] ?? 0) + entry.value;
      }
    }
    return totals;
  }

  Map<String, double> _netAmountsByCurrency(
    Map<String, GroupLentBorrowed> balances,
  ) {
    final nets = <String, double>{};
    for (final entry in balances.entries) {
      nets[entry.key] = entry.value.lent - entry.value.borrowed;
    }
    return nets;
  }

  Map<String, double> _positiveAmounts(Map<String, double> amounts) {
    return Map.fromEntries(
      amounts.entries.where((entry) => entry.value > 0.005),
    );
  }

  Map<String, double> _negativeAmounts(Map<String, double> amounts) {
    return Map.fromEntries(
      amounts.entries
          .where((entry) => entry.value < -0.005)
          .map((entry) => MapEntry(entry.key, -entry.value)),
    );
  }

  String _targetCurrencyForExpense(GroupExpense expense) {
    for (final option in _groupCurrencyOptions) {
      if (option != expense.currency &&
          expense.convertedAmounts.containsKey(option)) {
        return option;
      }
    }
    return 'INR';
  }

  Future<void> _openSettings() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => _GroupSettingsPage(
          repository: widget.repository,
          groupId: widget.group.id,
          groupName: widget.group.name,
          members: _members,
          expenses: _expenses,
          simplifyBalances: _simplifyBalances,
          memberCountFallback: _memberCount,
          autoRefresh: true,
        ),
      ),
    );
    if (!mounted) return;
    if (result != null) {
      setState(() => _simplifyBalances = result);
    }
    final refreshed = await _loadMembers();
    if (!mounted) return;
    if (refreshed) {
      setState(() => _didMutateGroupData = true);
    }
  }

  String _resolvePayerLabel(String rawPaidBy, List<String> participants) {
    final normalized = rawPaidBy.trim().toLowerCase();
    if (normalized.isEmpty) {
      return participants.first;
    }
    for (final member in _members) {
      final candidates = <String>{
        member.uid.trim().toLowerCase(),
        member.displayName.trim().toLowerCase(),
        member.email.trim().toLowerCase(),
        member.phone.trim().toLowerCase(),
        member.label.trim().toLowerCase(),
      }..removeWhere((v) => v.isEmpty);
      if (candidates.contains(normalized)) {
        for (final participant in participants) {
          if (candidates.contains(participant.trim().toLowerCase())) {
            return participant;
          }
        }
        return member.label;
      }
    }
    for (final participant in participants) {
      if (participant.trim().toLowerCase() == normalized) {
        return participant;
      }
    }
    return participants.first;
  }

  String _normalizedCategory(String value) {
    return normalizeMonthlyCategory(value);
  }

  Future<_SplitSelectionResult?> _openSplitOptionsPage({
    required List<String> participants,
    required Set<String> selectedMembers,
    required String currentMode,
    required double totalAmount,
    required String currency,
    Map<String, double> splitAmounts = const {},
  }) {
    return Navigator.of(context).push<_SplitSelectionResult>(
      MaterialPageRoute<_SplitSelectionResult>(
        builder: (_) => _SplitOptionsPage(
          participants: participants,
          selectedMembers: selectedMembers,
          currentMode: currentMode,
          totalAmount: totalAmount,
          currency: currency,
          splitAmounts: splitAmounts,
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

  Future<void> _loadData({bool showLoading = true}) async {
    await Future.wait([
      _loadMembers(),
      _loadExpenses(showLoading: showLoading),
    ]);
    _openInitialExpenseAction();
  }

  void _openInitialExpenseAction() {
    if (_didOpenInitialExpense) return;
    if (widget.initialAddExpense) {
      _didOpenInitialExpense = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _addExpense(
          initialCategory: widget.initialExpenseCategory,
          initialDescription: widget.initialExpenseDescription,
          initialBillUpload: widget.initialBillUpload,
        );
      });
      return;
    }
    final expenseId = widget.initialExpenseId?.trim();
    if (expenseId == null || expenseId.isEmpty) return;
    final expense = _expenses.where((item) => item.id == expenseId).firstOrNull;
    if (expense == null) return;
    _didOpenInitialExpense = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _editExpense(expense);
    });
  }

  Future<bool> _loadMembers() async {
    var hadCached = false;
    try {
      final cachedMembers = await widget.repository.getCachedMembers(
        widget.group.id,
      );
      if (!mounted) return false;
      if (cachedMembers.isNotEmpty) {
        hadCached = true;
        setState(() {
          _members = cachedMembers;
          _memberCount = cachedMembers.length;
        });
      }
      final items = await widget.repository.fetchMembers(widget.group.id);
      if (!mounted) return false;
      setState(() {
        _members = items;
        _memberCount = items.length;
      });
      return true;
    } catch (_) {
      return hadCached;
    }
  }

  Future<void> _loadExpenses({bool showLoading = true}) async {
    setState(() {
      _loading = showLoading || _expenses.isEmpty;
      _error = null;
    });
    var hadCached = false;
    try {
      final cachedItems = await widget.repository.getCachedExpenses(
        widget.group.id,
      );
      if (!mounted) return;
      if (cachedItems.isNotEmpty) {
        hadCached = true;
        setState(() => _expenses = cachedItems);
      }
      final items = await widget.repository.fetchExpenses(widget.group.id);
      if (!mounted) return;
      setState(() => _expenses = items);
    } catch (error) {
      if (!mounted) return;
      if (!hadCached && (showLoading || _expenses.isEmpty)) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _replaceExpenseInList(GroupExpense updatedExpense) {
    setState(() {
      _expenses = _expenses
          .map((item) => item.id == updatedExpense.id ? updatedExpense : item)
          .toList(growable: false);
    });
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
        _didMutateGroupData = true;
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

  Future<void> _openAttachmentPreview({
    required String title,
    required String url,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: InteractiveViewer(
                  child: Image.network(
                    url,
                    gaplessPlayback: true,
                    webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) {
                        return child;
                      }
                      final expectedBytes = loadingProgress.expectedTotalBytes;
                      final loadedBytes = loadingProgress.cumulativeBytesLoaded;
                      final progress =
                          expectedBytes == null || expectedBytes <= 0
                          ? null
                          : loadedBytes / expectedBytes;
                      return Center(
                        child: Text(
                          progress == null
                              ? 'Loading attachment...'
                              : 'Loading ${(progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) => const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Failed to load attachment preview.'),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<Map<String, dynamic>?> _showExpenseForm({
    required String title,
    required String expenseId,
    required List<String> participants,
    bool isEditing = false,
    String? initialDescription,
    double? initialAmount,
    String? initialPaidBy,
    String initialSplitMode = 'equally',
    Set<String>? initialSplitWith,
    Map<String, double> initialSplitAmounts = const {},
    String initialCurrency = 'INR',
    String initialTargetCurrency = 'INR',
    String initialCategory = 'Groceries',
    DateTime? initialDate,
    bool showMonthlyCategory = false,
    bool initialBillUpload = false,
    List<String>? initialAttachments,
    DateTime? initialUpdatedAt,
    String? initialUpdatedBy,
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
        var currency = _normalizedGroupCurrency(initialCurrency);
        var targetCurrency = _normalizedGroupCurrency(initialTargetCurrency);
        var category = _normalizedCategory(initialCategory);
        var expenseDate = initialDate ?? DateTime.now();
        final selected = {...(initialSplitWith ?? participants)};
        var splitAmounts = Map<String, double>.from(initialSplitAmounts);
        var splitWithAll = selected.length == participants.length;
        final attachmentItems = [
          ...?initialAttachments?.asMap().entries.map(
            (entry) => _AttachmentUploadItem(
              id: 'existing-${entry.key}-${entry.value.hashCode}',
              label: 'Bill ${entry.key + 1}',
              url: entry.value,
              progress: 1,
              uploading: false,
            ),
          ),
        ];
        var requiresExplicitAttachmentSave = false;
        var didInlineAttachmentUpload = false;
        var extractingBill = false;
        String? billMessage;
        BillExtractionResult? billResult;
        var didStartInitialBillUpload = false;

        Future<void> scanBill(StateSetter setDialogState) async {
          setDialogState(() {
            extractingBill = true;
            billMessage = 'Reading bill...';
          });
          try {
            final image = await _billPicker.pickImage(
              source: ImageSource.gallery,
              imageQuality: 85,
            );
            if (image == null) {
              setDialogState(() {
                extractingBill = false;
                billMessage = null;
              });
              return;
            }

            final bytes = await image.readAsBytes();
            final mimeType =
                lookupMimeType(image.name, headerBytes: bytes) ?? 'image/jpeg';
            final itemId =
                '${DateTime.now().microsecondsSinceEpoch}-${image.name.hashCode}-scan';
            setDialogState(() {
              attachmentItems.add(
                _AttachmentUploadItem(
                  id: itemId,
                  label: image.name,
                  progress: 0,
                  uploading: true,
                  localPreviewBytes: bytes,
                  localPreviewPath: image.path,
                  pendingUploadBytes: isEditing ? null : bytes,
                  uploadFileName: image.name,
                  uploadContentType: mimeType,
                ),
              );
            });

            final result = await _billRepository.uploadAndWait(
              bytes: bytes,
              fileName: image.name,
              contentType: mimeType,
            );
            if (!mounted) return;

            final primaryDescription = result.merchant.trim().isNotEmpty
                ? result.merchant.trim()
                : result.notes.trim();
            setDialogState(() {
              if (primaryDescription.isNotEmpty) {
                descriptionController.text = primaryDescription;
              }
              if (result.amount > 0) {
                amountController.text = result.amount.toStringAsFixed(2);
              }
              currency = _normalizedGroupCurrency(result.currency);
              category = _normalizedCategory(result.category);
              expenseDate = result.date;
              billResult = result;
              billMessage =
                  'Bill ready (${(result.confidence * 100).toStringAsFixed(0)}% confidence).';
            });

            if (isEditing) {
              final url = await widget.repository.uploadAttachment(
                groupId: widget.group.id,
                expenseId: expenseId,
                bytes: bytes,
                fileName: image.name,
                contentType: mimeType,
                onProgress: (sent, total) {
                  if (total <= 0) return;
                  final progress = sent / total;
                  setDialogState(() {
                    final idx = attachmentItems.indexWhere(
                      (item) => item.id == itemId,
                    );
                    if (idx >= 0) {
                      attachmentItems[idx] = attachmentItems[idx].copyWith(
                        progress: progress,
                      );
                    }
                  });
                },
              );
              if (!mounted) return;
              setDialogState(() {
                final idx = attachmentItems.indexWhere(
                  (item) => item.id == itemId,
                );
                if (idx >= 0) {
                  attachmentItems[idx] = attachmentItems[idx].copyWith(
                    uploading: false,
                    progress: 1,
                    url: url,
                    error: null,
                    pendingUploadBytes: null,
                  );
                  didInlineAttachmentUpload = true;
                }
              });
            } else {
              setDialogState(() {
                final idx = attachmentItems.indexWhere(
                  (item) => item.id == itemId,
                );
                if (idx >= 0) {
                  attachmentItems[idx] = attachmentItems[idx].copyWith(
                    uploading: false,
                    progress: 1,
                    pendingUploadBytes: bytes,
                    uploadFileName: image.name,
                    uploadContentType: mimeType,
                  );
                }
              });
            }
          } catch (error) {
            if (!mounted) return;
            setDialogState(() {
              extractingBill = false;
              billMessage = 'Bill extraction failed.';
              final lastIndex = attachmentItems.lastIndexWhere(
                (item) => item.uploading,
              );
              if (lastIndex >= 0) {
                attachmentItems[lastIndex] = attachmentItems[lastIndex]
                    .copyWith(uploading: false, error: error.toString());
              }
            });
            return;
          }
          if (!mounted) return;
          setDialogState(() => extractingBill = false);
        }

        return StatefulBuilder(
          builder: (context, setDialogState) {
            if (initialBillUpload && !didStartInitialBillUpload) {
              didStartInitialBillUpload = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                scanBill(setDialogState);
              });
            }
            return AlertDialog(
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
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final amountField = TextField(
                            controller: amountController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Amount',
                              prefixText: '$currency ',
                            ),
                          );
                          final currencyField = DropdownButtonFormField<String>(
                            initialValue: currency,
                            decoration: const InputDecoration(
                              labelText: 'Currency',
                              border: OutlineInputBorder(),
                            ),
                            items: _groupCurrencyOptions
                                .map(
                                  (item) => DropdownMenuItem<String>(
                                    value: item,
                                    child: Text(item),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: (value) {
                              if (value != null) {
                                setDialogState(() => currency = value);
                              }
                            },
                          );
                          final targetCurrencyField =
                              DropdownButtonFormField<String>(
                                initialValue: targetCurrency,
                                decoration: const InputDecoration(
                                  labelText: 'Convert to',
                                  border: OutlineInputBorder(),
                                ),
                                items: _groupCurrencyOptions
                                    .map(
                                      (item) => DropdownMenuItem<String>(
                                        value: item,
                                        child: Text(item),
                                      ),
                                    )
                                    .toList(growable: false),
                                onChanged: (value) {
                                  if (value != null) {
                                    setDialogState(
                                      () => targetCurrency = value,
                                    );
                                  }
                                },
                              );
                          if (constraints.maxWidth < 640) {
                            return Column(
                              children: [
                                amountField,
                                const SizedBox(height: 12),
                                currencyField,
                                const SizedBox(height: 12),
                                targetCurrencyField,
                              ],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: amountField),
                              const SizedBox(width: 12),
                              SizedBox(width: 140, child: currencyField),
                              const SizedBox(width: 12),
                              SizedBox(width: 140, child: targetCurrencyField),
                            ],
                          );
                        },
                      ),
                      if (showMonthlyCategory) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: category,
                          decoration: const InputDecoration(
                            labelText: 'Monthly category',
                            border: OutlineInputBorder(),
                          ),
                          items: householdMonthlyCategories
                              .map(
                                (item) => DropdownMenuItem<String>(
                                  value: item,
                                  child: Text(item),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() => category = value);
                            }
                          },
                        ),
                      ],
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final selectedDate = await showDatePicker(
                              context: context,
                              initialDate: expenseDate,
                              firstDate: DateTime(2000),
                              lastDate: DateTime.now().add(
                                const Duration(days: 365),
                              ),
                            );
                            if (selectedDate == null) return;
                            setDialogState(() {
                              expenseDate = DateTime(
                                selectedDate.year,
                                selectedDate.month,
                                selectedDate.day,
                                expenseDate.hour,
                                expenseDate.minute,
                              );
                            });
                          },
                          icon: const Icon(Icons.calendar_today_outlined),
                          label: Text(DateFormatter.formatDate(expenseDate)),
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
                                currency: currency,
                                splitAmounts: splitAmounts,
                              );
                              if (result == null) return;
                              setDialogState(() {
                                splitMode = result.mode;
                                splitAmounts = Map<String, double>.from(
                                  result.splitAmounts,
                                );
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
                                splitMode = 'equally';
                                splitAmounts.clear();
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
                              setDialogState(() {
                                splitWithAll = false;
                                splitMode = 'equally';
                                splitAmounts.clear();
                              });
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
                                      splitMode = 'equally';
                                      splitAmounts.clear();
                                    });
                                  },
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ],
                      if (isEditing &&
                          initialUpdatedAt != null &&
                          initialUpdatedBy != null &&
                          initialUpdatedBy.trim().isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Last updated ${initialUpdatedAt.toLocal().toString().split('.').first} by ${initialUpdatedBy.trim()}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
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
                      if (attachmentItems.isEmpty)
                        Text(
                          'No attachments yet.',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        )
                      else
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 260),
                          child: Scrollbar(
                            thumbVisibility: true,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: attachmentItems.length,
                              separatorBuilder: (_, index) =>
                                  const SizedBox(width: 8),
                              itemBuilder: (context, index) {
                                final item = attachmentItems[index];
                                final displayLabel =
                                    !item.uploading &&
                                        (item.url?.isNotEmpty ?? false)
                                    ? 'Bill ${index + 1}'
                                    : item.label;
                                final percent = (item.progress * 100).clamp(
                                  0,
                                  100,
                                );
                                final previewable =
                                    item.url != null &&
                                    item.url!.isNotEmpty &&
                                    !item.uploading &&
                                    item.error == null;
                                final previewUrl = item.url;

                                Widget previewBox() {
                                  if (item.localPreviewBytes != null) {
                                    if (kIsWeb &&
                                        item.localPreviewPath != null &&
                                        item.localPreviewPath!.isNotEmpty) {
                                      return ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          item.localPreviewPath!,
                                          key: ValueKey(
                                            '${item.id}|${item.localPreviewPath}|local-web',
                                          ),
                                          gaplessPlayback: true,
                                          webHtmlElementStrategy:
                                              WebHtmlElementStrategy.prefer,
                                          width: 100,
                                          height: 140,
                                          fit: BoxFit.cover,
                                          errorBuilder:
                                              (
                                                context,
                                                error,
                                                stackTrace,
                                              ) => Container(
                                                width: 100,
                                                height: 140,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .surfaceContainerHighest,
                                                alignment: Alignment.center,
                                                child: const Text(
                                                  'Preview unavailable',
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                        ),
                                      );
                                    }
                                    return ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.memory(
                                        item.localPreviewBytes!,
                                        width: 100,
                                        height: 140,
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) =>
                                                Container(
                                                  width: 100,
                                                  height: 140,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .surfaceContainerHighest,
                                                  alignment: Alignment.center,
                                                  child: const Text(
                                                    'Preview unavailable',
                                                    textAlign: TextAlign.center,
                                                  ),
                                                ),
                                      ),
                                    );
                                  }

                                  if (kIsWeb &&
                                      previewable &&
                                      previewUrl != null) {
                                    return ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: SizedBox(
                                        width: 100,
                                        height: 140,
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            Container(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .surfaceContainerHighest,
                                              alignment: Alignment.center,
                                              child: const SizedBox(
                                                width: 24,
                                                height: 24,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2.2,
                                                    ),
                                              ),
                                            ),
                                            Image.network(
                                              previewUrl,
                                              key: ValueKey(
                                                '$previewUrl|attachment-thumb-web',
                                              ),
                                              gaplessPlayback: true,
                                              webHtmlElementStrategy:
                                                  WebHtmlElementStrategy.prefer,
                                              fit: BoxFit.cover,
                                              errorBuilder:
                                                  (
                                                    context,
                                                    error,
                                                    stackTrace,
                                                  ) => Container(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .surfaceContainerHighest,
                                                    alignment: Alignment.center,
                                                    child: const Text(
                                                      'Preview unavailable',
                                                      textAlign:
                                                          TextAlign.center,
                                                    ),
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }

                                  if (!kIsWeb &&
                                      previewable &&
                                      previewUrl != null) {
                                    return InkWell(
                                      onTap: () => _openAttachmentPreview(
                                        title: item.label,
                                        url: previewUrl,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        width: 100,
                                        height: 140,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.surfaceContainerHighest,
                                        ),
                                        alignment: Alignment.center,
                                        child: const Icon(Icons.zoom_in),
                                      ),
                                    );
                                  }

                                  return Container(
                                    width: 100,
                                    height: 140,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHighest,
                                    ),
                                    alignment: Alignment.center,
                                    child: item.uploading
                                        ? Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              SizedBox(
                                                width: 26,
                                                height: 26,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2.2,
                                                      value: item.progress > 0
                                                          ? item.progress.clamp(
                                                              0,
                                                              1,
                                                            )
                                                          : null,
                                                    ),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                '${percent.toStringAsFixed(0)}%',
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.bodySmall,
                                              ),
                                            ],
                                          )
                                        : Icon(
                                            item.error == null
                                                ? Icons.image_outlined
                                                : Icons.error_outline,
                                          ),
                                  );
                                }

                                return Container(
                                  width: 132,
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.outlineVariant,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              displayLabel,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          InkWell(
                                            onTap: () async {
                                              setDialogState(() {
                                                attachmentItems.removeAt(index);
                                                if (isEditing) {
                                                  requiresExplicitAttachmentSave =
                                                      true;
                                                }
                                              });
                                            },
                                            child: const Padding(
                                              padding: EdgeInsets.all(4),
                                              child: Icon(
                                                Icons.close,
                                                size: 18,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      previewBox(),
                                      if (item.error != null) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          item.error!,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.error,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ActionChip(
                            avatar: extractingBill
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.document_scanner_outlined,
                                    size: 16,
                                  ),
                            label: Text(
                              extractingBill ? 'Reading bill...' : 'Scan bill',
                            ),
                            onPressed: extractingBill
                                ? null
                                : () => scanBill(setDialogState),
                          ),
                          ActionChip(
                            avatar: const Icon(
                              Icons.photo_library_outlined,
                              size: 16,
                            ),
                            label: const Text('Gallery'),
                            onPressed: () async {
                              final picker = ImagePicker();
                              final picked = await picker.pickMultiImage(
                                imageQuality: 85,
                              );
                              if (picked.isEmpty) return;
                              for (final image in picked) {
                                final itemId =
                                    '${DateTime.now().microsecondsSinceEpoch}-${image.name.hashCode}';
                                setDialogState(() {
                                  attachmentItems.add(
                                    _AttachmentUploadItem(
                                      id: itemId,
                                      label: image.name,
                                      progress: 0,
                                      uploading: true,
                                    ),
                                  );
                                });
                                try {
                                  final bytes = await image.readAsBytes();
                                  setDialogState(() {
                                    final idx = attachmentItems.indexWhere(
                                      (it) => it.id == itemId,
                                    );
                                    if (idx >= 0) {
                                      attachmentItems[idx] =
                                          attachmentItems[idx].copyWith(
                                            localPreviewBytes: bytes,
                                            localPreviewPath: image.path,
                                            pendingUploadBytes: bytes,
                                          );
                                    }
                                  });
                                  final mimeType =
                                      lookupMimeType(
                                        image.name,
                                        headerBytes: bytes,
                                      ) ??
                                      'image/jpeg';
                                  if (!isEditing) {
                                    setDialogState(() {
                                      final idx = attachmentItems.indexWhere(
                                        (it) => it.id == itemId,
                                      );
                                      if (idx >= 0) {
                                        attachmentItems[idx] =
                                            attachmentItems[idx].copyWith(
                                              uploading: false,
                                              progress: 1,
                                              uploadFileName: image.name,
                                              uploadContentType: mimeType,
                                            );
                                      }
                                    });
                                    continue;
                                  }
                                  final url = await widget.repository
                                      .uploadAttachment(
                                        groupId: widget.group.id,
                                        expenseId: expenseId,
                                        bytes: bytes,
                                        fileName: image.name,
                                        contentType: mimeType,
                                        onProgress: (sent, total) {
                                          if (total <= 0) return;
                                          final progress = sent / total;
                                          setDialogState(() {
                                            final idx = attachmentItems
                                                .indexWhere(
                                                  (it) => it.id == itemId,
                                                );
                                            if (idx >= 0) {
                                              attachmentItems[idx] =
                                                  attachmentItems[idx].copyWith(
                                                    progress: progress,
                                                  );
                                            }
                                          });
                                        },
                                      );
                                  setDialogState(() {
                                    final idx = attachmentItems.indexWhere(
                                      (it) => it.id == itemId,
                                    );
                                    if (idx >= 0) {
                                      attachmentItems[idx] =
                                          attachmentItems[idx].copyWith(
                                            uploading: false,
                                            progress: 1,
                                            url: url,
                                            error: null,
                                            localPreviewBytes: bytes,
                                            localPreviewPath: image.path,
                                            pendingUploadBytes: null,
                                          );
                                      didInlineAttachmentUpload = true;
                                    }
                                  });
                                } catch (error) {
                                  setDialogState(() {
                                    final idx = attachmentItems.indexWhere(
                                      (it) => it.id == itemId,
                                    );
                                    if (idx >= 0) {
                                      attachmentItems[idx] =
                                          attachmentItems[idx].copyWith(
                                            uploading: false,
                                            error: error.toString(),
                                          );
                                    }
                                  });
                                }
                              }
                            },
                          ),
                          ActionChip(
                            avatar: const Icon(
                              Icons.photo_camera_outlined,
                              size: 16,
                            ),
                            label: const Text('Camera'),
                            onPressed: () async {
                              final picker = ImagePicker();
                              final image = await picker.pickImage(
                                source: ImageSource.camera,
                                imageQuality: 85,
                              );
                              if (image == null) return;
                              final itemId =
                                  '${DateTime.now().microsecondsSinceEpoch}-${image.name.hashCode}';
                              setDialogState(() {
                                attachmentItems.add(
                                  _AttachmentUploadItem(
                                    id: itemId,
                                    label: image.name,
                                    progress: 0,
                                    uploading: true,
                                  ),
                                );
                              });
                              try {
                                final bytes = await image.readAsBytes();
                                setDialogState(() {
                                  final idx = attachmentItems.indexWhere(
                                    (it) => it.id == itemId,
                                  );
                                  if (idx >= 0) {
                                    attachmentItems[idx] = attachmentItems[idx]
                                        .copyWith(
                                          localPreviewBytes: bytes,
                                          localPreviewPath: image.path,
                                          pendingUploadBytes: bytes,
                                        );
                                  }
                                });
                                final mimeType =
                                    lookupMimeType(
                                      image.name,
                                      headerBytes: bytes,
                                    ) ??
                                    'image/jpeg';
                                if (!isEditing) {
                                  setDialogState(() {
                                    final idx = attachmentItems.indexWhere(
                                      (it) => it.id == itemId,
                                    );
                                    if (idx >= 0) {
                                      attachmentItems[idx] =
                                          attachmentItems[idx].copyWith(
                                            uploading: false,
                                            progress: 1,
                                            uploadFileName: image.name,
                                            uploadContentType: mimeType,
                                          );
                                    }
                                  });
                                  return;
                                }
                                final url = await widget.repository
                                    .uploadAttachment(
                                      groupId: widget.group.id,
                                      expenseId: expenseId,
                                      bytes: bytes,
                                      fileName: image.name,
                                      contentType: mimeType,
                                      onProgress: (sent, total) {
                                        if (total <= 0) return;
                                        final progress = sent / total;
                                        setDialogState(() {
                                          final idx = attachmentItems
                                              .indexWhere(
                                                (it) => it.id == itemId,
                                              );
                                          if (idx >= 0) {
                                            attachmentItems[idx] =
                                                attachmentItems[idx].copyWith(
                                                  progress: progress,
                                                );
                                          }
                                        });
                                      },
                                    );
                                setDialogState(() {
                                  final idx = attachmentItems.indexWhere(
                                    (it) => it.id == itemId,
                                  );
                                  if (idx >= 0) {
                                    attachmentItems[idx] = attachmentItems[idx]
                                        .copyWith(
                                          uploading: false,
                                          progress: 1,
                                          url: url,
                                          error: null,
                                          localPreviewBytes: bytes,
                                          localPreviewPath: image.path,
                                          pendingUploadBytes: null,
                                        );
                                    didInlineAttachmentUpload = true;
                                  }
                                });
                              } catch (error) {
                                setDialogState(() {
                                  final idx = attachmentItems.indexWhere(
                                    (it) => it.id == itemId,
                                  );
                                  if (idx >= 0) {
                                    attachmentItems[idx] = attachmentItems[idx]
                                        .copyWith(
                                          uploading: false,
                                          error: error.toString(),
                                        );
                                  }
                                });
                              }
                            },
                          ),
                          ActionChip(
                            avatar: const Icon(Icons.attach_file, size: 16),
                            label: const Text('Add URL'),
                            onPressed: () async {
                              final url = await _promptAttachmentUrl();
                              if (url == null || url.isEmpty) return;
                              setDialogState(() {
                                if (isEditing) {
                                  requiresExplicitAttachmentSave = true;
                                }
                                attachmentItems.add(
                                  _AttachmentUploadItem(
                                    id: '${DateTime.now().microsecondsSinceEpoch}-url',
                                    label: 'Bill URL',
                                    url: url,
                                    progress: 1,
                                    uploading: false,
                                  ),
                                );
                              });
                            },
                          ),
                        ],
                      ),
                      if (billMessage != null) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            billMessage!,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                      if (billResult != null) ...[
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            [
                              if (billResult!.merchant.trim().isNotEmpty)
                                billResult!.merchant.trim(),
                              if (billResult!.amount > 0)
                                '${billResult!.currency} ${billResult!.amount.toStringAsFixed(2)}',
                              billResult!.category,
                            ].where((item) => item.trim().isNotEmpty).join(' · '),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                if (isEditing)
                  TextButton.icon(
                    onPressed: () => Navigator.of(
                      context,
                    ).pop({'action': 'delete', 'expenseId': expenseId}),
                    icon: Icon(
                      Icons.delete_outline,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    label: Text(
                      'Delete',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop({
                    'action': 'save',
                    'description': descriptionController.text.trim(),
                    'expenseId': expenseId,
                    'amount': double.tryParse(amountController.text.trim()),
                    'currency': currency,
                    'targetCurrencies': [targetCurrency],
                    'category': showMonthlyCategory ? category : '',
                    'date': expenseDate,
                    'paidBy': paidBy,
                    'splitMode': splitMode,
                    'splitWith': selected.toList(growable: false),
                    'splitAmounts': splitAmounts,
                    'attachments': attachmentItems
                        .where((item) => !item.uploading && item.url != null)
                        .map((item) => item.url!)
                        .toList(growable: false),
                    'attachmentItems': List<_AttachmentUploadItem>.from(
                      attachmentItems,
                    ),
                    'requiresExplicitAttachmentSave':
                        requiresExplicitAttachmentSave,
                    'didInlineAttachmentUpload': didInlineAttachmentUpload,
                  }),
                  child: Text(isEditing ? 'Done' : 'Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _addExpense({
    String initialCategory = 'Groceries',
    String? initialDescription,
    bool initialBillUpload = false,
  }) async {
    if (_members.isEmpty && _memberCount > 0) {
      await _loadMembers();
      if (!mounted) return;
    }
    final participants = _expenseParticipantKeys();
    final payload = await _showExpenseForm(
      title: widget.group.groupType == GroupType.family
          ? 'Add household expense'
          : 'Add group expense',
      expenseId: '',
      participants: participants,
      initialDescription: initialDescription,
      initialCategory: initialCategory,
      initialSplitWith: participants.toSet(),
      showMonthlyCategory: widget.group.groupType == GroupType.family,
      initialBillUpload: initialBillUpload,
    );
    if (!mounted || payload == null) return;
    final description = (payload['description'] as String?) ?? '';
    final paidBy = (payload['paidBy'] as String?) ?? participants.first;
    final splitMode = (payload['splitMode'] as String?) ?? 'equally';
    final splitWith = (payload['splitWith'] as List<dynamic>? ?? participants)
        .whereType<String>()
        .toList(growable: false);
    final splitAmounts = _splitAmountsFromPayload(payload['splitAmounts']);
    final amount = payload['amount'] as double?;
    final currency = _normalizedGroupCurrency(
      (payload['currency'] as String?) ?? 'INR',
    );
    final targetCurrencies = _normalizedGroupCurrencies(
      (payload['targetCurrencies'] as List<dynamic>? ?? const []).map(
        (item) => item.toString(),
      ),
    );
    final category = (payload['category'] as String?) ?? '';
    final date = payload['date'] is DateTime
        ? payload['date'] as DateTime
        : DateTime.now();
    final attachments = (payload['attachments'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList(growable: false);
    final attachmentItems =
        (payload['attachmentItems'] as List<dynamic>? ?? const [])
            .whereType<_AttachmentUploadItem>()
            .toList(growable: false);
    if (description.isEmpty || amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid description and amount.')),
      );
      return;
    }
    if (!_splitAmountsMatchTotal(splitAmounts, amount)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Review the split before saving.')),
      );
      return;
    }
    setState(() => _busyAction = _GroupBusyAction.addingExpense);
    try {
      final created = await widget.repository.addExpense(
        groupId: widget.group.id,
        description: description,
        paidBy: paidBy,
        splitMode: splitMode,
        splitWith: splitWith,
        splitAmounts: splitAmounts,
        amount: amount,
        currency: currency,
        targetCurrencies: targetCurrencies,
        category: category,
        attachments: attachments,
        date: date,
      );

      var failedUploads = 0;
      for (final item in attachmentItems) {
        final bytes = item.pendingUploadBytes;
        if (bytes == null || bytes.isEmpty) {
          continue;
        }
        try {
          await widget.repository.uploadAttachment(
            groupId: widget.group.id,
            expenseId: created.id,
            bytes: bytes,
            fileName: item.uploadFileName?.trim().isNotEmpty == true
                ? item.uploadFileName!
                : item.label,
            contentType: item.uploadContentType?.trim().isNotEmpty == true
                ? item.uploadContentType!
                : 'image/jpeg',
          );
        } catch (_) {
          failedUploads += 1;
        }
      }
      if (!mounted) return;
      await _loadExpenses();
      if (!mounted) return;
      setState(() {
        _busyAction = _GroupBusyAction.none;
        _didMutateGroupData = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failedUploads > 0
                ? 'Group expense added. $failedUploads attachment(s) failed.'
                : 'Group expense added.',
          ),
        ),
      );
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
    final participants = _expenseParticipantKeys();
    final payload = await _showExpenseForm(
      title: 'Edit group expense',
      expenseId: expense.id,
      participants: participants,
      isEditing: true,
      initialDescription: expense.description,
      initialAmount: expense.amount,
      initialPaidBy: _resolvePayerLabel(expense.paidBy, participants),
      initialSplitMode: expense.splitMode.isNotEmpty
          ? expense.splitMode
          : 'equally',
      initialSplitWith: expense.splitWith.isNotEmpty
          ? expense.splitWith
                .map((member) => _resolvePayerLabel(member, participants))
                .toSet()
          : participants.toSet(),
      initialSplitAmounts: _splitAmountsForParticipantLabels(
        expense.splitAmounts,
        participants,
      ),
      initialCurrency: expense.currency,
      initialCategory: expense.category,
      initialTargetCurrency: _targetCurrencyForExpense(expense),
      initialDate: expense.date,
      showMonthlyCategory: widget.group.groupType == GroupType.family,
      initialAttachments: expense.attachments,
      initialUpdatedAt: expense.updatedAt,
      initialUpdatedBy: _resolvePayerLabel(expense.updatedBy, participants),
    );

    if (!mounted) return;
    if (payload == null) {
      await _loadExpenses();
      if (!mounted) return;
      setState(() => _didMutateGroupData = true);
      return;
    }
    final action = (payload['action'] as String?) ?? 'save';
    if (action == 'delete') {
      await _deleteExpense(expense);
      return;
    }
    final description = (payload['description'] as String?) ?? '';
    final paidBy = (payload['paidBy'] as String?) ?? participants.first;
    final splitMode = (payload['splitMode'] as String?) ?? 'equally';
    final splitWith = (payload['splitWith'] as List<dynamic>? ?? participants)
        .whereType<String>()
        .toList(growable: false);
    final splitAmounts = _splitAmountsFromPayload(payload['splitAmounts']);
    final amount = payload['amount'] as double?;
    final currency = _normalizedGroupCurrency(
      (payload['currency'] as String?) ?? expense.currency,
    );
    final targetCurrencies = _normalizedGroupCurrencies(
      (payload['targetCurrencies'] as List<dynamic>? ?? const []).map(
        (item) => item.toString(),
      ),
    );
    final category = (payload['category'] as String?) ?? '';
    final date = payload['date'] is DateTime
        ? payload['date'] as DateTime
        : expense.date;
    final attachments = (payload['attachments'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList(growable: false);
    final requiresExplicitAttachmentSave =
        payload['requiresExplicitAttachmentSave'] == true;
    final didInlineAttachmentUpload =
        payload['didInlineAttachmentUpload'] == true;
    if (description.isEmpty || amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid description and amount.')),
      );
      return;
    }
    if (!_splitAmountsMatchTotal(splitAmounts, amount)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Review the split before saving.')),
      );
      return;
    }

    final originalPaidBy = _resolvePayerLabel(expense.paidBy, participants);
    final originalTargetCurrency = _targetCurrencyForExpense(expense);
    final originalSplitMode = expense.splitMode.isNotEmpty
        ? expense.splitMode
        : 'equally';
    final originalSplitWith = expense.splitWith.isNotEmpty
        ? expense.splitWith
              .map((member) => _resolvePayerLabel(member, participants))
              .toSet()
        : participants.toSet();
    final originalSplitAmounts = _splitAmountsForParticipantLabels(
      expense.splitAmounts,
      participants,
    );
    final dateChanged =
        date.toUtc().difference(expense.date.toUtc()).inMilliseconds.abs() >
        1000;
    final fieldChanged =
        description != expense.description ||
        currency != expense.currency ||
        (targetCurrencies.isNotEmpty &&
            targetCurrencies.first != originalTargetCurrency) ||
        category != expense.category ||
        (amount - expense.amount).abs() > 0.000001 ||
        paidBy != originalPaidBy ||
        splitMode != originalSplitMode ||
        !setEquals(splitWith.toSet(), originalSplitWith) ||
        !mapEquals(splitAmounts, originalSplitAmounts) ||
        dateChanged;
    if (!fieldChanged && !requiresExplicitAttachmentSave) {
      if (didInlineAttachmentUpload) {
        final locallyUpdated = GroupExpense(
          id: expense.id,
          groupId: expense.groupId,
          createdBy: expense.createdBy,
          updatedBy: expense.updatedBy,
          paidBy: expense.paidBy,
          splitMode: expense.splitMode,
          splitWith: expense.splitWith,
          splitAmounts: expense.splitAmounts,
          splitAmountsByCurrency: expense.splitAmountsByCurrency,
          amount: expense.amount,
          currency: expense.currency,
          convertedAmounts: expense.convertedAmounts,
          category: expense.category,
          description: expense.description,
          attachments: attachments,
          date: expense.date,
          createdAt: expense.createdAt,
          updatedAt: DateTime.now(),
        );
        _replaceExpenseInList(locallyUpdated);
        _didMutateGroupData = true;
      }
      return;
    }

    setState(() => _busyAction = _GroupBusyAction.addingExpense);
    try {
      final updatedExpense = await widget.repository.updateExpense(
        groupId: widget.group.id,
        expenseId: expense.id,
        description: description,
        paidBy: paidBy,
        splitMode: splitMode,
        splitWith: splitWith,
        splitAmounts: splitAmounts,
        amount: amount,
        currency: currency,
        targetCurrencies: targetCurrencies,
        category: category,
        attachments: attachments,
        date: date,
      );
      _replaceExpenseInList(updatedExpense);
      if (!mounted) return;
      setState(() {
        _busyAction = _GroupBusyAction.none;
        _didMutateGroupData = true;
      });
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

  Future<void> _deleteExpense(GroupExpense expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete expense'),
        content: Text('Delete "${expense.description}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busyAction = _GroupBusyAction.deletingExpense);
    try {
      await widget.repository.deleteExpense(
        groupId: widget.group.id,
        expenseId: expense.id,
      );
      if (!mounted) return;
      await _loadExpenses();
      if (!mounted) return;
      setState(() {
        _busyAction = _GroupBusyAction.none;
        _didMutateGroupData = true;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Group expense deleted.')));
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
    final totalByCurrency = _totalAmountsByCurrency(_expenses);
    final memberCount = _members.isNotEmpty ? _members.length : _memberCount;
    final userIdentifiers = authUser == null
        ? <String>{}
        : _currentUserIdentifiers(
            uid: authUser.uid,
            email: authUser.email,
            displayName: authUser.displayName,
            phone: authUser.phone,
          );
    final balanceByCurrency = authUser == null
        ? <String, GroupLentBorrowed>{}
        : calculateGroupLentBorrowedByCurrency(
            expenses: _expenses,
            memberCount: memberCount,
            userIdentifiers: userIdentifiers,
          );
    final netByCurrency = _netAmountsByCurrency(balanceByCurrency);
    final owedByCurrency = _positiveAmounts(netByCurrency);
    final oweByCurrency = _negativeAmounts(netByCurrency);
    final lentByCurrency = Map.fromEntries(
      balanceByCurrency.entries
          .where((entry) => entry.value.lent > 0.005)
          .map((entry) => MapEntry(entry.key, entry.value.lent)),
    );
    final borrowedByCurrency = Map.fromEntries(
      balanceByCurrency.entries
          .where((entry) => entry.value.borrowed > 0.005)
          .map((entry) => MapEntry(entry.key, entry.value.borrowed)),
    );
    final busyMessage = switch (_busyAction) {
      _GroupBusyAction.addingMember => 'Adding member...',
      _GroupBusyAction.addingExpense => 'Saving expense...',
      _GroupBusyAction.deletingExpense => 'Deleting expense...',
      _GroupBusyAction.leavingGroup => 'Leaving group...',
      _GroupBusyAction.none => '',
    };
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop(_didMutateGroupData);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: () => Navigator.of(context).pop(_didMutateGroupData),
            icon: const Icon(Icons.arrow_back),
          ),
          title: Text(widget.group.name),
          actions: [
            IconButton(
              onPressed: _busy ? null : _openSettings,
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Group settings',
            ),
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
            AppPageContainer(
              onRefresh: () => _loadData(showLoading: false),
              autoRefresh: widget.autoRefresh,
              children: [
                AppCard(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          widget.group.groupType == GroupType.family
                              ? 'Family monthly spend'
                              : 'Group total spend',
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$_memberCount member${_memberCount == 1 ? '' : 's'}',
                            ),
                            if (_simplifyBalances) ...[
                              const SizedBox(height: 4),
                              Builder(
                                builder: (context) {
                                  if (owedByCurrency.isEmpty &&
                                      oweByCurrency.isEmpty) {
                                    return Text(
                                      'You are all settled up',
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.outline,
                                      ),
                                    );
                                  }
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (owedByCurrency.isNotEmpty)
                                        Text(
                                          'You are owed ${AppMoney.formatCurrencyAmounts(owedByCurrency)}',
                                          style: TextStyle(
                                            color: AppMoney.positiveColor,
                                          ),
                                        ),
                                      if (oweByCurrency.isNotEmpty)
                                        Text(
                                          'You owe ${AppMoney.formatCurrencyAmounts(oweByCurrency)}',
                                          style: TextStyle(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.error,
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ] else ...[
                              if (lentByCurrency.isNotEmpty ||
                                  borrowedByCurrency.isNotEmpty)
                                const SizedBox(height: 4),
                              if (lentByCurrency.isNotEmpty)
                                Text(
                                  'You are owed ${AppMoney.formatCurrencyAmounts(lentByCurrency)}',
                                  style: TextStyle(
                                    color: AppMoney.positiveColor,
                                  ),
                                ),
                              if (borrowedByCurrency.isNotEmpty)
                                Text(
                                  'You owe ${AppMoney.formatCurrencyAmounts(borrowedByCurrency)}',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                            ],
                          ],
                        ),
                        trailing: Text(
                          AppMoney.formatCurrencyAmounts(totalByCurrency),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _busy ? null : _openSettings,
                          icon: const Icon(Icons.handshake_outlined),
                          label: const Text('Settle up'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (_loading)
                  const AppBalanceTile(
                    title: 'Loading group expenses...',
                    leadingIcon: Icons.receipt_long_outlined,
                  )
                else if (_error != null)
                  SelectableErrorMessage(_error!)
                else if (_expenses.isEmpty)
                  const AppEmptyState(
                    title: 'No group expenses yet',
                    subtitle: 'Tap Add expense to create one.',
                  )
                else
                  ..._expenses.map((expense) {
                    final expenseBalance = _balanceForExpense(
                      expense: expense,
                      userIdentifiers: userIdentifiers,
                      memberCount: memberCount,
                    );
                    final convertedOtherAmounts = Map.fromEntries(
                      expense.convertedAmounts.entries.where(
                        (entry) => entry.key != expense.currency,
                      ),
                    );
                    return AppCard(
                      child: ListTile(
                        onTap: _busy ? null : () => _editExpense(expense),
                        leading: const AppAvatar(
                          icon: Icons.receipt_long_outlined,
                        ),
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
                            if (expense.category.trim().isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                expense.category.trim(),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                            if (convertedOtherAmounts.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Saved as ${AppMoney.formatCurrencyAmounts(convertedOtherAmounts)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                            if (expense.attachments.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                '${expense.attachments.length} attachment${expense.attachments.length == 1 ? '' : 's'}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ],
                        ),
                        trailing: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              AppMoney.formatCurrency(
                                expense.amount,
                                expense.currency,
                              ),
                            ),
                            if (expenseBalance.owed > 0.005)
                              Text(
                                'owed ${AppMoney.formatCurrency(expenseBalance.owed, expense.currency)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppMoney.positiveColor,
                                ),
                              ),
                            if (expenseBalance.owe > 0.005)
                              Text(
                                'owe ${AppMoney.formatCurrency(expenseBalance.owe, expense.currency)}',
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
      ),
    );
  }
}

class _GroupSettingsPage extends StatefulWidget {
  const _GroupSettingsPage({
    required this.repository,
    required this.groupId,
    required this.groupName,
    required this.members,
    required this.expenses,
    required this.simplifyBalances,
    required this.memberCountFallback,
    required this.autoRefresh,
  });

  final ApiGroupsRepository repository;
  final String groupId;
  final String groupName;
  final List<GroupMember> members;
  final List<GroupExpense> expenses;
  final bool simplifyBalances;
  final int memberCountFallback;
  final bool autoRefresh;

  @override
  State<_GroupSettingsPage> createState() => _GroupSettingsPageState();
}

class _GroupSettingsPageState extends State<_GroupSettingsPage> {
  late bool _simplify;
  late List<GroupMember> _members;
  late final http.Client _client;
  late final ExpenseRepository _expenseRepository;
  bool _settlementLoading = true;
  String? _settlingMemberUid;
  String? _updatingRoleUid;
  Map<String, Map<String, double>> _settlementNetByCurrency = const {};

  @override
  void initState() {
    super.initState();
    _simplify = widget.simplifyBalances;
    _members = widget.members;
    _client = http.Client();
    _expenseRepository = ExpenseRepository(client: _client);
    _loadSettlementBalances();
  }

  @override
  void dispose() {
    _expenseRepository.dispose();
    _client.close();
    super.dispose();
  }

  Future<void> _loadSettlementBalances() async {
    setState(() => _settlementLoading = true);
    try {
      await _expenseRepository.refresh();
      final expenses = _expenseRepository.getExpenses();
      final netByCurrency = <String, Map<String, double>>{};
      for (final member in _members) {
        netByCurrency.putIfAbsent('INR', () => <String, double>{})[member.uid] =
            0;
      }
      for (final expense in expenses) {
        final category = (expense.category ?? '').trim().toLowerCase();
        if (category != 'settlement') continue;
        final meta = _parseGroupSettlementMeta(expense.description ?? '');
        if (meta == null) continue;
        if (meta.groupId != widget.groupId) continue;
        if (!_members.any((member) => member.uid == meta.memberUid)) continue;
        final currency = _normalizeSettlementCurrency(expense.currency);
        final currencyNet = netByCurrency.putIfAbsent(
          currency,
          () => <String, double>{for (final member in _members) member.uid: 0},
        );
        final signedDelta = meta.direction == 'received'
            ? expense.amount
            : -expense.amount;
        currencyNet[meta.memberUid] =
            (currencyNet[meta.memberUid] ?? 0) + signedDelta;
      }
      if (!mounted) return;
      setState(() {
        _settlementNetByCurrency = netByCurrency;
        _settlementLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _settlementLoading = false);
    }
  }

  Future<void> _refreshSettings() async {
    try {
      final members = await widget.repository.fetchMembers(widget.groupId);
      if (!mounted) return;
      setState(() => _members = members);
    } catch (_) {
      // Keep the current member list and still refresh settlement totals.
    }
    await _loadSettlementBalances();
  }

  _GroupSettlementMeta? _parseGroupSettlementMeta(String description) {
    final match = RegExp(
      r'\[type:groupSettlement\]\[group:([^\]]+)\]\[uid:([^\]]+)\]\[dir:(paid|received)\]',
    ).firstMatch(description);
    if (match == null) return null;
    final groupId = (match.group(1) ?? '').trim();
    final memberUid = (match.group(2) ?? '').trim();
    final direction = (match.group(3) ?? '').trim();
    if (groupId.isEmpty || memberUid.isEmpty) return null;
    if (direction != 'paid' && direction != 'received') return null;
    return _GroupSettlementMeta(
      groupId: groupId,
      memberUid: memberUid,
      direction: direction,
    );
  }

  String _normalizeSettlementCurrency(String value) {
    final currency = value.trim().toUpperCase();
    return RegExp(r'^[A-Z]{3}$').hasMatch(currency) ? currency : 'INR';
  }

  List<String> _settlementCurrencyOptions() {
    final currencies = <String>{'INR'};
    for (final expense in widget.expenses) {
      currencies.addAll(
        expense.amountsByCurrency.keys.map(_normalizeSettlementCurrency),
      );
    }
    currencies.addAll(_settlementNetByCurrency.keys);
    final sorted = currencies.toList()..sort();
    if (sorted.remove('INR')) {
      sorted.insert(0, 'INR');
    }
    return sorted;
  }

  String _preferredSettlementCurrency(GroupMember member) {
    final netByCurrency = _memberNetByCurrency();
    String? selected;
    var selectedMagnitude = 0.0;
    for (final entry in netByCurrency.entries) {
      final amount = (entry.value[member.uid] ?? 0).abs();
      if (amount > selectedMagnitude) {
        selected = entry.key;
        selectedMagnitude = amount;
      }
    }
    return selected ?? _settlementCurrencyOptions().first;
  }

  Future<_GroupSettleUpInput?> _openSettleUpDialog(GroupMember member) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var direction = 'paid';
    var currency = _preferredSettlementCurrency(member);
    final currencyOptions = _settlementCurrencyOptions();
    return showDialog<_GroupSettleUpInput>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Settle up with ${member.label}'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment<String>(value: 'paid', label: Text('I paid')),
                    ButtonSegment<String>(
                      value: 'received',
                      label: Text('I received'),
                    ),
                  ],
                  selected: {direction},
                  onSelectionChanged: (selection) {
                    setDialogState(() => direction = selection.first);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: currency,
                  decoration: const InputDecoration(
                    labelText: 'Currency',
                    border: OutlineInputBorder(),
                  ),
                  items: currencyOptions
                      .map(
                        (item) =>
                            DropdownMenuItem(value: item, child: Text(item)),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => currency = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Amount',
                    prefixText: '$currency ',
                    hintText: '0.00',
                  ),
                  validator: (value) {
                    final amount = double.tryParse((value ?? '').trim());
                    if (amount == null || amount <= 0) {
                      return 'Enter a valid amount';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (!(formKey.currentState?.validate() ?? false)) return;
                final amount = double.parse(controller.text.trim());
                Navigator.of(context).pop(
                  _GroupSettleUpInput(
                    amount: amount,
                    direction: direction,
                    currency: currency,
                  ),
                );
              },
              child: const Text('Record'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _settleUpWithMember(GroupMember member) async {
    final input = await _openSettleUpDialog(member);
    if (input == null) return;
    setState(() => _settlingMemberUid = member.uid);
    try {
      final description =
          'Group settle up with ${member.label} '
          '[type:groupSettlement][group:${widget.groupId}][uid:${member.uid}][dir:${input.direction}][currency:${input.currency}]';
      await _expenseRepository.createExpense(
        Expense(
          core: ExpenseCore(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            title: 'Group settlement',
            amount: input.amount,
            currency: input.currency,
            category: 'Settlement',
            createdAt: DateTime.now(),
          ),
          description: description,
        ),
      );
      await _loadSettlementBalances();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Recorded ${AppMoney.formatCurrency(input.amount, input.currency)} with ${member.label}.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _settlingMemberUid = null);
      }
    }
  }

  Future<void> _updateMemberRole(GroupMember member, String role) async {
    if (_updatingRoleUid != null || role == member.role) return;
    setState(() => _updatingRoleUid = member.uid);
    try {
      final updated = await widget.repository.updateMemberRole(
        groupId: widget.groupId,
        memberUid: member.uid,
        role: role,
      );
      if (!mounted) return;
      setState(() {
        _members = _members
            .map((item) => item.uid == updated.uid ? updated : item)
            .toList(growable: false);
        _updatingRoleUid = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _updatingRoleUid = null);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Map<String, Map<String, double>> _memberNetByCurrency() {
    final memberCount = _members.isNotEmpty
        ? _members.length
        : widget.memberCountFallback;
    if (memberCount <= 0) {
      return const {};
    }

    final netByCurrency = <String, Map<String, double>>{};

    Map<String, double> netForCurrency(String currency) =>
        netByCurrency.putIfAbsent(
          currency,
          () => <String, double>{for (final member in _members) member.uid: 0},
        );

    String? resolveMemberUid(String key) {
      final normalizedKey = key.trim().toLowerCase();
      if (normalizedKey.isEmpty) return null;
      for (final member in _members) {
        final candidates = <String>{
          member.uid.trim().toLowerCase(),
          member.displayName.trim().toLowerCase(),
          member.email.trim().toLowerCase(),
          member.phone.trim().toLowerCase(),
          member.label.trim().toLowerCase(),
        }..removeWhere((v) => v.isEmpty);
        if (candidates.contains(normalizedKey)) {
          return member.uid;
        }
      }
      return null;
    }

    for (final expense in widget.expenses) {
      final payerKey = expense.paidBy.isNotEmpty
          ? expense.paidBy
          : expense.createdBy;
      final payerUid = resolveMemberUid(payerKey);
      final splitUids = expense.splitWith
          .map(resolveMemberUid)
          .whereType<String>()
          .toSet();
      final effectiveSplitUids = splitUids.isEmpty
          ? _members.map((member) => member.uid).toSet()
          : splitUids;
      for (final entry in expense.amountsByCurrency.entries) {
        final currency = _normalizeSettlementCurrency(entry.key);
        final amount = entry.value;
        if (amount <= 0) continue;
        final currencyNet = netForCurrency(currency);
        final splitAmounts = expense.splitAmountsForCurrency(currency);
        if (splitAmounts.isNotEmpty) {
          for (final splitEntry in splitAmounts.entries) {
            final uid = resolveMemberUid(splitEntry.key);
            final share = splitEntry.value;
            if (uid == null || share <= 0) continue;
            currencyNet[uid] = (currencyNet[uid] ?? 0) - share;
          }
          if (payerUid != null) {
            currencyNet[payerUid] = (currencyNet[payerUid] ?? 0) + amount;
          }
          continue;
        }
        final share = amount / effectiveSplitUids.length;

        for (final uid in effectiveSplitUids) {
          currencyNet[uid] = (currencyNet[uid] ?? 0) - share;
        }
        if (payerUid != null) {
          currencyNet[payerUid] = (currencyNet[payerUid] ?? 0) + amount;
        }
      }
    }

    _settlementNetByCurrency.forEach((currency, netByUid) {
      final currencyNet = netForCurrency(currency);
      netByUid.forEach((uid, value) {
        currencyNet[uid] = (currencyNet[uid] ?? 0) + value;
      });
    });

    return netByCurrency;
  }

  String _memberLabelByUid(String uid) {
    for (final member in _members) {
      if (member.uid == uid) {
        return member.label;
      }
    }
    return uid;
  }

  String _primarySettlementCurrency(
    Map<String, Map<String, double>> netByCurrency,
  ) {
    var selected = _settlementCurrencyOptions().first;
    var selectedMagnitude = 0.0;
    for (final entry in netByCurrency.entries) {
      final magnitude = entry.value.values.fold<double>(
        0,
        (sum, amount) => sum + amount.abs(),
      );
      if (magnitude > selectedMagnitude) {
        selected = entry.key;
        selectedMagnitude = magnitude;
      }
    }
    return selected;
  }

  @override
  Widget build(BuildContext context) {
    final authUid = context.select(
      (AuthCubit cubit) => cubit.state.user?.uid ?? '',
    );
    final netByCurrency = _memberNetByCurrency();
    final primaryCurrency = _primarySettlementCurrency(netByCurrency);
    final netByUid = netByCurrency[primaryCurrency] ?? const <String, double>{};
    final transferSuggestions = _simplify
        ? simplifyGroupTransfers(netByUid)
        : const <GroupTransferSuggestion>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Group settings')),
      body: AppPageContainer(
        onRefresh: _refreshSettings,
        autoRefresh: widget.autoRefresh,
        children: [
          AppCard(
            child: ListTile(
              title: Text(widget.groupName),
              subtitle: Text(
                '${_members.length} member${_members.length == 1 ? '' : 's'}',
              ),
            ),
          ),
          const SizedBox(height: 12),
          const AppSectionHeader(title: 'Group members'),
          if (_settlementLoading)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          ..._members.map((member) {
            final memberNetByCurrency = <String, double>{};
            for (final entry in netByCurrency.entries) {
              final amount = entry.value[member.uid] ?? 0;
              if (amount.abs() > 0.005) {
                memberNetByCurrency[entry.key] = amount;
              }
            }
            final positiveAmounts = memberNetByCurrency.map(
              (currency, amount) => MapEntry(currency, amount.abs()),
            );
            final allPositive = memberNetByCurrency.values.every(
              (amount) => amount > 0,
            );
            final allNegative = memberNetByCurrency.values.every(
              (amount) => amount < 0,
            );
            final status = memberNetByCurrency.isEmpty
                ? 'settled up'
                : allPositive
                ? 'gets back ${AppMoney.formatCurrencyAmounts(positiveAmounts)}'
                : allNegative
                ? 'owes ${AppMoney.formatCurrencyAmounts(positiveAmounts)}'
                : 'mixed ${AppMoney.formatCurrencyAmounts(positiveAmounts)}';
            final primaryNet = netByUid[member.uid] ?? 0;
            final statusColor = memberNetByCurrency.isEmpty
                ? Theme.of(context).colorScheme.outline
                : primaryNet > 0
                ? AppMoney.positiveColor
                : Theme.of(context).colorScheme.error;
            return AppCard(
              child: ListTile(
                leading: AppAvatar(label: member.label),
                title: Text(member.label),
                subtitle: member.email.isNotEmpty
                    ? Text('${member.roleLabel} · ${member.email}')
                    : Text(
                        member.phone.isNotEmpty
                            ? '${member.roleLabel} · ${member.phone}'
                            : member.roleLabel,
                      ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _updatingRoleUid == member.uid
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : PopupMenuButton<String>(
                            tooltip: 'Assign role',
                            icon: const Icon(Icons.badge_outlined),
                            onSelected: (role) =>
                                _updateMemberRole(member, role),
                            itemBuilder: (context) => familyRoleOptions
                                .map(
                                  (role) => PopupMenuItem(
                                    value: role,
                                    child: Text(role),
                                  ),
                                )
                                .toList(growable: false),
                          ),
                    const SizedBox(width: 8),
                    Text(
                      status,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (member.uid != authUid) ...[
                      const SizedBox(width: 8),
                      _settlingMemberUid == member.uid
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : IconButton(
                              tooltip: 'Settle up',
                              onPressed: () => _settleUpWithMember(member),
                              icon: const Icon(Icons.handshake_outlined),
                            ),
                    ],
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 16),
          const AppSectionHeader(title: 'Advanced settings'),
          AppCard(
            child: SwitchListTile(
              title: const Text('Simplify group debts'),
              subtitle: const Text(
                'Automatically show only net owed/owe values in this group.',
              ),
              value: _simplify,
              onChanged: (value) {
                setState(() => _simplify = value);
              },
            ),
          ),
          if (_simplify) ...[
            const SizedBox(height: 8),
            AppCard(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Suggested transfers',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    if (transferSuggestions.isEmpty)
                      Text(
                        'No transfers needed. Group is settled up.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      )
                    else
                      ...transferSuggestions.map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            '${_memberLabelByUid(item.fromUid)} pays ${_memberLabelByUid(item.toUid)} ${AppMoney.formatCurrency(item.amount, primaryCurrency)}',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_simplify),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

enum _GroupBusyAction {
  none,
  addingMember,
  addingExpense,
  deletingExpense,
  leavingGroup,
}

class _AttachmentUploadItem {
  static const Object _unset = Object();

  const _AttachmentUploadItem({
    required this.id,
    required this.label,
    required this.progress,
    required this.uploading,
    this.url,
    this.error,
    this.localPreviewBytes,
    this.localPreviewPath,
    this.pendingUploadBytes,
    this.uploadFileName,
    this.uploadContentType,
  });

  final String id;
  final String label;
  final double progress;
  final bool uploading;
  final String? url;
  final String? error;
  final Uint8List? localPreviewBytes;
  final String? localPreviewPath;
  final Uint8List? pendingUploadBytes;
  final String? uploadFileName;
  final String? uploadContentType;

  _AttachmentUploadItem copyWith({
    String? id,
    String? label,
    double? progress,
    bool? uploading,
    Object? url = _unset,
    Object? error = _unset,
    Object? localPreviewBytes = _unset,
    Object? localPreviewPath = _unset,
    Object? pendingUploadBytes = _unset,
    Object? uploadFileName = _unset,
    Object? uploadContentType = _unset,
  }) {
    return _AttachmentUploadItem(
      id: id ?? this.id,
      label: label ?? this.label,
      progress: progress ?? this.progress,
      uploading: uploading ?? this.uploading,
      url: identical(url, _unset) ? this.url : url as String?,
      error: identical(error, _unset) ? this.error : error as String?,
      localPreviewBytes: identical(localPreviewBytes, _unset)
          ? this.localPreviewBytes
          : localPreviewBytes as Uint8List?,
      localPreviewPath: identical(localPreviewPath, _unset)
          ? this.localPreviewPath
          : localPreviewPath as String?,
      pendingUploadBytes: identical(pendingUploadBytes, _unset)
          ? this.pendingUploadBytes
          : pendingUploadBytes as Uint8List?,
      uploadFileName: identical(uploadFileName, _unset)
          ? this.uploadFileName
          : uploadFileName as String?,
      uploadContentType: identical(uploadContentType, _unset)
          ? this.uploadContentType
          : uploadContentType as String?,
    );
  }
}

class _GroupSettleUpInput {
  const _GroupSettleUpInput({
    required this.amount,
    required this.direction,
    required this.currency,
  });

  final double amount;
  final String direction;
  final String currency;
}

class _GroupSettlementMeta {
  const _GroupSettlementMeta({
    required this.groupId,
    required this.memberUid,
    required this.direction,
  });

  final String groupId;
  final String memberUid;
  final String direction;
}

class _SplitSelectionResult {
  const _SplitSelectionResult({
    required this.mode,
    required this.selectedMembers,
    required this.splitAmounts,
  });

  final String mode;
  final Set<String> selectedMembers;
  final Map<String, double> splitAmounts;
}

class _SplitOptionsPage extends StatefulWidget {
  const _SplitOptionsPage({
    required this.participants,
    required this.selectedMembers,
    required this.currentMode,
    required this.totalAmount,
    required this.currency,
    required this.splitAmounts,
  });

  final List<String> participants;
  final Set<String> selectedMembers;
  final String currentMode;
  final double totalAmount;
  final String currency;
  final Map<String, double> splitAmounts;

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
    _mode = _supportedMode(widget.currentMode);
    _selected = {...widget.selectedMembers};
    if (_selected.isEmpty && widget.participants.isNotEmpty) {
      _selected = {widget.participants.first};
    }
    for (final member in widget.participants) {
      final splitAmount = widget.splitAmounts[member] ?? 0;
      _exactControllers[member] = TextEditingController(
        text: splitAmount > 0 && _mode == 'exact'
            ? splitAmount.toStringAsFixed(2)
            : '',
      );
      _percentControllers[member] = TextEditingController(
        text: splitAmount > 0 && _mode == 'percent' && widget.totalAmount > 0
            ? ((splitAmount / widget.totalAmount) * 100).toStringAsFixed(2)
            : '',
      );
      _sharesControllers[member] = TextEditingController(
        text: splitAmount > 0 && _mode == 'shares' ? '1' : '',
      );
      _adjustmentControllers[member] = TextEditingController();
    }
  }

  String _supportedMode(String mode) {
    return switch (mode.trim().toLowerCase()) {
      'exact' ||
      'percent' ||
      'shares' ||
      'adjustment' => mode.trim().toLowerCase(),
      _ => 'equally',
    };
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

  String get _moneyPrefix {
    final currency = widget.currency.trim().toUpperCase();
    return currency == 'INR' || currency.isEmpty ? '₹' : '$currency ';
  }

  Map<String, double> _positiveEntries(
    Map<String, TextEditingController> controllers,
  ) {
    final entries = <String, double>{};
    for (final member in widget.participants) {
      final amount = _parseLocalizedDouble(controllers[member]?.text ?? '');
      if (amount > 0) {
        entries[member] = amount;
      }
    }
    return entries;
  }

  Map<String, double> _amountsFromWeights(Map<String, double> weights) {
    final totalWeight = weights.values.fold<double>(
      0,
      (sum, item) => sum + item,
    );
    if (totalWeight <= 0 || widget.totalAmount <= 0) {
      return const {};
    }
    final entries = weights.entries.where((entry) => entry.value > 0).toList();
    final amounts = <String, double>{};
    var allocated = 0.0;
    for (var index = 0; index < entries.length; index += 1) {
      final entry = entries[index];
      final amount = index == entries.length - 1
          ? widget.totalAmount - allocated
          : double.parse(
              ((widget.totalAmount * entry.value) / totalWeight)
                  .toStringAsFixed(4),
            );
      if (amount > 0) {
        amounts[entry.key] = amount;
        allocated += amount;
      }
    }
    return amounts;
  }

  _SplitSelectionResult? _buildResult() {
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose at least one person.')),
      );
      return null;
    }
    if (_mode == 'equally') {
      return _SplitSelectionResult(
        mode: 'equally',
        selectedMembers: _selected,
        splitAmounts: const {},
      );
    }
    if (widget.totalAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the amount before splitting.')),
      );
      return null;
    }

    Map<String, double> splitAmounts;
    switch (_mode) {
      case 'exact':
        splitAmounts = _positiveEntries(_exactControllers);
        if ((splitAmounts.values.fold<double>(0, (sum, item) => sum + item) -
                    widget.totalAmount)
                .abs() >
            0.005) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Exact amounts must match the bill.')),
          );
          return null;
        }
        break;
      case 'percent':
        final percentages = _positiveEntries(_percentControllers);
        if ((percentages.values.fold<double>(0, (sum, item) => sum + item) -
                    100)
                .abs() >
            0.05) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Percentages must add up to 100%.')),
          );
          return null;
        }
        splitAmounts = _amountsFromWeights(percentages);
        break;
      case 'shares':
        final shares = <String, double>{};
        for (final member in widget.participants) {
          final raw = _sharesControllers[member]?.text.trim() ?? '';
          final share = int.tryParse(raw) ?? 0;
          if (share > 0) {
            shares[member] = share.toDouble();
          }
        }
        if (shares.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Enter at least one share.')),
          );
          return null;
        }
        splitAmounts = _amountsFromWeights(shares);
        break;
      case 'adjustment':
        final adjustments = _positiveEntries(_adjustmentControllers);
        final selectedMembers = _selected.toList(growable: false);
        final adjustedTotal = adjustments.values.fold<double>(
          0,
          (sum, item) => sum + item,
        );
        if (adjustedTotal - widget.totalAmount > 0.005) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Adjustments exceed the bill.')),
          );
          return null;
        }
        final base =
            (widget.totalAmount - adjustedTotal) / selectedMembers.length;
        splitAmounts = {
          for (final member in selectedMembers)
            member: base + (adjustments[member] ?? 0),
        };
        break;
      default:
        splitAmounts = {};
    }
    splitAmounts = Map<String, double>.from(splitAmounts);
    splitAmounts.removeWhere((key, value) => value <= 0);
    if (splitAmounts.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a valid split.')));
      return null;
    }
    return _SplitSelectionResult(
      mode: _mode,
      selectedMembers: splitAmounts.keys.toSet(),
      splitAmounts: Map.unmodifiable(splitAmounts),
    );
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
              _moneyPrefix,
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
                  hintText: '0.00',
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
                  hintText: '0.00',
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
            AppAvatar(
              label: member,
              backgroundColor: avatarColor,
              foregroundColor: Colors.white,
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
    final adjustmentRemaining = widget.totalAmount - enteredAdjustment;

    String footerTitle;
    String footerSubtitle;
    bool footerError;
    switch (_mode) {
      case 'exact':
        footerTitle =
            '${AppMoney.formatCurrency(enteredExact, widget.currency)} of ${AppMoney.formatCurrency(widget.totalAmount, widget.currency)}';
        footerSubtitle = exactRemaining < 0
            ? '${AppMoney.formatCurrency(0, widget.currency)} left'
            : '${AppMoney.formatCurrency(exactRemaining, widget.currency)} left';
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
        footerSubtitle = enteredShares <= 0
            ? 'Enter shares to split the bill'
            : 'Bill is divided by share count';
        footerError = enteredShares <= 0;
        break;
      case 'adjustment':
        footerTitle =
            '${AppMoney.formatCurrency(enteredAdjustment, widget.currency)} of ${AppMoney.formatCurrency(widget.totalAmount, widget.currency)}';
        footerSubtitle = adjustmentRemaining < 0
            ? '${AppMoney.formatCurrency(0, widget.currency)} left'
            : '${AppMoney.formatCurrency(adjustmentRemaining, widget.currency)} left';
        footerError =
            adjustmentRemaining.abs() > 0.005 && adjustmentRemaining >= 0;
        break;
      case 'equally':
      default:
        footerTitle =
            '${AppMoney.formatCurrency(perPerson, widget.currency)}/person';
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
              final result = _buildResult();
              if (result != null) {
                Navigator.of(context).pop(result);
              }
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
      body: AppPageContainer(
        children: [
          ...participants.map(
            (name) => AppBalanceTile(
              title: name,
              leadingLabel: name,
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

class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.group, this.onTap});

  final GroupSummary group;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final icon = group.groupType == GroupType.family
        ? Icons.home_outlined
        : Icons.group_outlined;
    final subtitle = group.groupType == GroupType.family
        ? '${group.memberCount} people · shared household'
        : '${group.memberCount} people · split expenses';
    return AppCard(
      child: ListTile(
        onTap: onTap,
        leading: AppAvatar(
          icon: icon,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
        title: Text(group.name),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
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
