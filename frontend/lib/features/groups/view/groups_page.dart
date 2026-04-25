import 'package:expense_tracker/core/ui/app_ui.dart';
import 'package:expense_tracker/core/widgets/selectable_error_message.dart';
import 'package:expense_tracker/data/models/expense.dart';
import 'package:expense_tracker/data/models/expense_core.dart';
import 'package:expense_tracker/data/models/group.dart';
import 'package:expense_tracker/data/repositories/expenses_repository.dart';
import 'package:expense_tracker/features/auth/cubit/auth_cubit.dart';
import 'package:expense_tracker/features/dashboard/view/dashboard_overall_summary_card.dart';
import 'package:expense_tracker/features/friends/repositories/api_friends_repository.dart';
import 'package:expense_tracker/features/groups/models/group_expense.dart';
import 'package:expense_tracker/features/groups/models/group_member.dart';
import 'package:expense_tracker/features/groups/models/group_summary.dart';
import 'package:expense_tracker/features/groups/repositories/api_groups_repository.dart';
import 'package:expense_tracker/features/groups/utils/group_balance_calculator.dart';
import 'package:expense_tracker/features/groups/utils/group_transfer_simplifier.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';

class GroupsPage extends StatefulWidget {
  const GroupsPage({
    this.groupType = GroupType.split,
    this.repository,
    this.client,
    super.key,
  });

  final GroupType groupType;
  final ApiGroupsRepository? repository;
  final http.Client? client;

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

  Future<void> _loadGroups() async {
    setState(() {
      _loading = true;
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
      if (!hadCached) {
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
        AppPageContainer(
          children: [
            const DashboardOverallSummaryCard(),
            const SizedBox(height: 16),
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
    super.key,
  });

  final GroupSummary group;
  final ApiGroupsRepository repository;
  final String? initialExpenseId;

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
    final paidBy =
        (expense.paidBy.isNotEmpty ? expense.paidBy : expense.createdBy)
            .trim()
            .toLowerCase();
    final share = expense.amount / memberCount;
    if (userIdentifiers.contains(paidBy)) {
      return (owed: expense.amount - share, owe: 0);
    }
    return (owed: 0, owe: share);
  }

  Future<void> _openSettings() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => _GroupSettingsPage(
          groupId: widget.group.id,
          groupName: widget.group.name,
          members: _members,
          expenses: _expenses,
          simplifyBalances: _simplifyBalances,
          memberCountFallback: _memberCount,
        ),
      ),
    );
    if (!mounted || result == null) return;
    setState(() => _simplifyBalances = result);
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
    _openInitialExpenseEditor();
  }

  void _openInitialExpenseEditor() {
    if (_didOpenInitialExpense) return;
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

  Future<void> _loadExpenses() async {
    setState(() {
      _loading = true;
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
      if (!hadCached) {
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
        final selected = {...(initialSplitWith ?? participants)};
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
                        prefixText: AppMoney.inputPrefix,
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
                                              child: CircularProgressIndicator(
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
                                                    textAlign: TextAlign.center,
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
                                        borderRadius: BorderRadius.circular(8),
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
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.2,
                                                value: item.progress > 0
                                                    ? item.progress.clamp(0, 1)
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                            child: Icon(Icons.close, size: 18),
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
                                    attachmentItems[idx] = attachmentItems[idx]
                                        .copyWith(
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
                                        final idx = attachmentItems.indexWhere(
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
                  'paidBy': paidBy,
                  'splitMode': splitMode,
                  'splitWith': selected.toList(growable: false),
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
      expenseId: '',
      participants: participants,
      initialSplitWith: participants.toSet(),
    );
    if (!mounted || payload == null) return;
    final description = (payload['description'] as String?) ?? '';
    final paidBy = (payload['paidBy'] as String?) ?? participants.first;
    final splitMode = (payload['splitMode'] as String?) ?? 'equally';
    final splitWith = (payload['splitWith'] as List<dynamic>? ?? participants)
        .whereType<String>()
        .toList(growable: false);
    final amount = payload['amount'] as double?;
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
    setState(() => _busyAction = _GroupBusyAction.addingExpense);
    try {
      final created = await widget.repository.addExpense(
        groupId: widget.group.id,
        description: description,
        paidBy: paidBy,
        splitMode: splitMode,
        splitWith: splitWith,
        amount: amount,
        attachments: attachments,
        date: DateTime.now(),
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
    final participants = _members.isNotEmpty
        ? _members.map((m) => m.label).toList(growable: false)
        : List<String>.generate(
            _memberCount,
            (index) => index == 0 ? 'You' : 'Member ${index + 1}',
          );
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
          ? expense.splitWith.toSet()
          : participants.toSet(),
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
    final amount = payload['amount'] as double?;
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

    final originalPaidBy = _resolvePayerLabel(expense.paidBy, participants);
    final originalSplitMode = expense.splitMode.isNotEmpty
        ? expense.splitMode
        : 'equally';
    final originalSplitWith = expense.splitWith.isNotEmpty
        ? expense.splitWith.toSet()
        : participants.toSet();
    final fieldChanged =
        description != expense.description ||
        (amount - expense.amount).abs() > 0.000001 ||
        paidBy != originalPaidBy ||
        splitMode != originalSplitMode ||
        !setEquals(splitWith.toSet(), originalSplitWith);
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
          amount: expense.amount,
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
        amount: amount,
        attachments: attachments,
        date: expense.date,
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
              children: [
                AppCard(
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
                        Text(
                          '$_memberCount member${_memberCount == 1 ? '' : 's'}',
                        ),
                        if (_simplifyBalances) ...[
                          const SizedBox(height: 4),
                          Builder(
                            builder: (context) {
                              final net = balance.lent - balance.borrowed;
                              if (net.abs() <= 0.005) {
                                return Text(
                                  'You are all settled up',
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.outline,
                                  ),
                                );
                              }
                              if (net > 0) {
                                return Text(
                                  'You are owed ${AppMoney.format(net)}',
                                  style: TextStyle(
                                    color: AppMoney.positiveColor,
                                  ),
                                );
                              }
                              return Text(
                                'You owe ${AppMoney.format(-net)}',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              );
                            },
                          ),
                        ] else ...[
                          if (balance.lent > 0.005 || balance.borrowed > 0.005)
                            const SizedBox(height: 4),
                          if (balance.lent > 0.005)
                            Text(
                              'You are owed ${AppMoney.format(balance.lent)}',
                              style: TextStyle(color: AppMoney.positiveColor),
                            ),
                          if (balance.borrowed > 0.005)
                            Text(
                              'You owe ${AppMoney.format(balance.borrowed)}',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                        ],
                      ],
                    ),
                    trailing: Text(
                      AppMoney.format(total),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
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
                            Text(AppMoney.format(expense.amount)),
                            if (expenseBalance.owed > 0.005)
                              Text(
                                'owed ${AppMoney.format(expenseBalance.owed)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppMoney.positiveColor,
                                ),
                              ),
                            if (expenseBalance.owe > 0.005)
                              Text(
                                'owe ${AppMoney.format(expenseBalance.owe)}',
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
    required this.groupId,
    required this.groupName,
    required this.members,
    required this.expenses,
    required this.simplifyBalances,
    required this.memberCountFallback,
  });

  final String groupId;
  final String groupName;
  final List<GroupMember> members;
  final List<GroupExpense> expenses;
  final bool simplifyBalances;
  final int memberCountFallback;

  @override
  State<_GroupSettingsPage> createState() => _GroupSettingsPageState();
}

class _GroupSettingsPageState extends State<_GroupSettingsPage> {
  late bool _simplify;
  late final http.Client _client;
  late final ExpenseRepository _expenseRepository;
  bool _settlementLoading = true;
  String? _settlingMemberUid;
  Map<String, double> _settlementNetByUid = const {};

  @override
  void initState() {
    super.initState();
    _simplify = widget.simplifyBalances;
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
      final netByUid = <String, double>{};
      for (final member in widget.members) {
        netByUid[member.uid] = 0;
      }
      for (final expense in expenses) {
        final category = (expense.category ?? '').trim().toLowerCase();
        if (category != 'settlement') continue;
        final meta = _parseGroupSettlementMeta(expense.description ?? '');
        if (meta == null) continue;
        if (meta.groupId != widget.groupId) continue;
        if (!netByUid.containsKey(meta.memberUid)) continue;
        final signedDelta = meta.direction == 'received'
            ? expense.amount
            : -expense.amount;
        netByUid[meta.memberUid] =
            (netByUid[meta.memberUid] ?? 0) + signedDelta;
      }
      if (!mounted) return;
      setState(() {
        _settlementNetByUid = netByUid;
        _settlementLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _settlementLoading = false);
    }
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

  Future<_GroupSettleUpInput?> _openSettleUpDialog(GroupMember member) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var direction = 'paid';
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
                TextFormField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixText: AppMoney.inputPrefix,
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
                  _GroupSettleUpInput(amount: amount, direction: direction),
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
          '[type:groupSettlement][group:${widget.groupId}][uid:${member.uid}][dir:${input.direction}]';
      await _expenseRepository.createExpense(
        Expense(
          core: ExpenseCore(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            title: 'Group settlement',
            amount: input.amount,
            currency: 'INR',
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
            'Recorded ${AppMoney.format(input.amount)} with ${member.label}.',
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

  Map<String, double> _memberNetByUid() {
    final memberCount = widget.members.isNotEmpty
        ? widget.members.length
        : widget.memberCountFallback;
    if (memberCount <= 0) {
      return const {};
    }

    final netByUid = <String, double>{};
    for (final member in widget.members) {
      netByUid[member.uid] = 0;
    }

    for (final expense in widget.expenses) {
      if (expense.amount <= 0) continue;
      final payerKey = expense.paidBy.isNotEmpty
          ? expense.paidBy
          : expense.createdBy;
      final share = expense.amount / memberCount;

      String? payerUid;
      for (final member in widget.members) {
        final candidates = <String>{
          member.uid.trim().toLowerCase(),
          member.displayName.trim().toLowerCase(),
          member.email.trim().toLowerCase(),
          member.phone.trim().toLowerCase(),
          member.label.trim().toLowerCase(),
        }..removeWhere((v) => v.isEmpty);
        if (candidates.contains(payerKey.trim().toLowerCase())) {
          payerUid = member.uid;
          break;
        }
      }

      for (final member in widget.members) {
        netByUid[member.uid] = (netByUid[member.uid] ?? 0) - share;
      }
      if (payerUid != null) {
        netByUid[payerUid] = (netByUid[payerUid] ?? 0) + expense.amount;
      }
    }

    _settlementNetByUid.forEach((uid, value) {
      netByUid[uid] = (netByUid[uid] ?? 0) + value;
    });

    return netByUid;
  }

  String _memberLabelByUid(String uid) {
    for (final member in widget.members) {
      if (member.uid == uid) {
        return member.label;
      }
    }
    return uid;
  }

  @override
  Widget build(BuildContext context) {
    final authUid = context.select(
      (AuthCubit cubit) => cubit.state.user?.uid ?? '',
    );
    final netByUid = _memberNetByUid();
    final transferSuggestions = _simplify
        ? simplifyGroupTransfers(netByUid)
        : const <GroupTransferSuggestion>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Group settings')),
      body: AppPageContainer(
        children: [
          AppCard(
            child: ListTile(
              title: Text(widget.groupName),
              subtitle: Text(
                '${widget.members.length} member${widget.members.length == 1 ? '' : 's'}',
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
          ...widget.members.map((member) {
            final net = netByUid[member.uid] ?? 0;
            final status = net.abs() <= 0.005
                ? 'settled up'
                : net > 0
                ? 'gets back ${AppMoney.format(net)}'
                : 'owes ${AppMoney.format(-net)}';
            final statusColor = net.abs() <= 0.005
                ? Theme.of(context).colorScheme.outline
                : net > 0
                ? AppMoney.positiveColor
                : Theme.of(context).colorScheme.error;
            return AppCard(
              child: ListTile(
                leading: AppAvatar(label: member.label),
                title: Text(member.label),
                subtitle: member.email.isNotEmpty
                    ? Text(member.email)
                    : (member.phone.isNotEmpty ? Text(member.phone) : null),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                            '${_memberLabelByUid(item.fromUid)} pays ${_memberLabelByUid(item.toUid)} ${AppMoney.format(item.amount)}',
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
  const _GroupSettleUpInput({required this.amount, required this.direction});

  final double amount;
  final String direction;
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
              '₹',
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
    final sharesRemaining = widget.participants.length - enteredShares;
    final adjustmentRemaining = widget.totalAmount - enteredAdjustment;

    String footerTitle;
    String footerSubtitle;
    bool footerError;
    switch (_mode) {
      case 'exact':
        footerTitle =
            '${AppMoney.format(enteredExact)} of ${AppMoney.format(widget.totalAmount)}';
        footerSubtitle = exactRemaining < 0
            ? '${AppMoney.format(0)} left'
            : '${AppMoney.format(exactRemaining)} left';
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
            '${AppMoney.format(enteredAdjustment)} of ${AppMoney.format(widget.totalAmount)}';
        footerSubtitle = adjustmentRemaining < 0
            ? '${AppMoney.format(0)} left'
            : '${AppMoney.format(adjustmentRemaining)} left';
        footerError =
            adjustmentRemaining.abs() > 0.005 && adjustmentRemaining >= 0;
        break;
      case 'equally':
      default:
        footerTitle = '${AppMoney.format(perPerson)}/person';
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
