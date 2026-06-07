import 'package:expense_tracker/core/ui/app_ui.dart';
import 'package:expense_tracker/data/models/group.dart';
import 'package:expense_tracker/features/auth/cubit/auth_cubit.dart';
import 'package:expense_tracker/features/groups/models/group_expense.dart';
import 'package:expense_tracker/features/groups/models/group_member.dart';
import 'package:expense_tracker/features/groups/models/group_summary.dart';
import 'package:expense_tracker/features/groups/repositories/api_groups_repository.dart';
import 'package:expense_tracker/features/groups/view/groups_page.dart';
import 'package:expense_tracker/features/planning/view/monthly_planning_card.dart';
import 'package:expense_tracker/features/planning/repositories/monthly_plan_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;

class FamilyPage extends StatefulWidget {
  const FamilyPage({
    this.repository,
    this.client,
    this.monthlyPlanRepository,
    super.key,
  });

  final ApiGroupsRepository? repository;
  final http.Client? client;
  final MonthlyPlanRepository? monthlyPlanRepository;

  @override
  State<FamilyPage> createState() => _FamilyPageState();
}

class _FamilyPageState extends State<FamilyPage> {
  http.Client? _ownedClient;
  late final ApiGroupsRepository _repository;
  List<GroupSummary> _families = const [];
  List<GroupMember> _members = const [];
  List<GroupExpense> _expenses = const [];
  GroupSummary? _selectedFamily;
  bool _loading = true;
  bool _loadingDetails = false;
  int _monthlyPlanRefreshToken = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    final client = widget.client ?? http.Client();
    if (widget.repository == null && widget.client == null) {
      _ownedClient = client;
    }
    _repository = widget.repository ?? ApiGroupsRepository(client: client);
    _loadFamilies();
  }

  @override
  void dispose() {
    _ownedClient?.close();
    super.dispose();
  }

  List<GroupSummary> _familyGroups(List<GroupSummary> groups) {
    return groups
        .where((group) => group.groupType == GroupType.family)
        .toList(growable: false);
  }

  Future<void> _loadFamilies() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    var hadCached = false;
    try {
      final cachedGroups = _familyGroups(await _repository.getCachedGroups());
      if (!mounted) return;
      if (cachedGroups.isNotEmpty) {
        hadCached = true;
        _applyFamilies(cachedGroups);
      }

      final groups = _familyGroups(await _repository.fetchGroups());
      if (!mounted) return;
      _applyFamilies(groups);
      await _loadSelectedFamilyDetails();
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

  void _applyFamilies(List<GroupSummary> families) {
    final previousId = _selectedFamily?.id;
    final selected = families
        .where((family) => family.id == previousId)
        .firstOrNull;
    setState(() {
      _families = families;
      _selectedFamily = selected ?? families.firstOrNull;
    });
  }

  Future<void> _loadSelectedFamilyDetails() async {
    final family = _selectedFamily;
    if (family == null) return;
    setState(() {
      _loadingDetails = true;
      _members = const [];
      _expenses = const [];
    });
    try {
      final cachedMembers = await _repository.getCachedMembers(family.id);
      final cachedExpenses = await _repository.getCachedExpenses(family.id);
      if (!mounted) return;
      if (cachedMembers.isNotEmpty || cachedExpenses.isNotEmpty) {
        setState(() {
          _members = cachedMembers;
          _expenses = cachedExpenses;
        });
      }

      final members = await _repository.fetchMembers(family.id);
      final expenses = await _repository.fetchExpenses(family.id);
      if (!mounted) return;
      setState(() {
        _members = members;
        _expenses = expenses;
      });
    } catch (error) {
      if (!mounted) return;
      if (_members.isEmpty && _expenses.isEmpty) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loadingDetails = false);
      }
    }
  }

  Future<void> _openSelectedFamily() async {
    final family = _selectedFamily;
    if (family == null) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            GroupDetailsPage(group: family, repository: _repository),
      ),
    );
    if (!mounted) return;
    if (changed == true) {
      setState(() => _monthlyPlanRefreshToken += 1);
      await _loadFamilies();
    }
  }

  Future<void> _openHouseholdSetup() async {
    final input = await showDialog<_HouseholdSetupInput>(
      context: context,
      builder: (_) => const _HouseholdSetupDialog(),
    );
    if (input == null || !mounted) return;
    final authUser = context.read<AuthCubit?>()?.state.user;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final created = await _repository.createGroup(
        name: input.householdName,
        groupType: GroupType.family,
        members: input.spouseEmail.isEmpty ? const [] : [input.spouseEmail],
      );
      final members = await _repository.fetchMembers(created.id);
      for (final member in members) {
        final isCurrentUser =
            authUser != null &&
            (member.uid == authUser.uid ||
                member.email.trim().toLowerCase() ==
                    authUser.email.trim().toLowerCase());
        final isSpouse =
            input.spouseEmail.isNotEmpty &&
            member.email.trim().toLowerCase() ==
                input.spouseEmail.trim().toLowerCase();
        if (isCurrentUser) {
          await _repository.updateMemberRole(
            groupId: created.id,
            memberUid: member.uid,
            role: input.yourRole,
          );
        } else if (isSpouse) {
          await _repository.updateMemberRole(
            groupId: created.id,
            memberUid: member.uid,
            role: input.spouseRole,
          );
        }
      }
      if (!mounted) return;
      setState(() => _monthlyPlanRefreshToken += 1);
      await _loadFamilies();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Household set up.')));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _householdSetupError(error, input.spouseEmail);
        _loading = false;
      });
    }
  }

  String _householdSetupError(Object error, String spouseEmail) {
    final message = error.toString();
    if (message.contains('member not found') && spouseEmail.trim().isNotEmpty) {
      return 'No account found for ${spouseEmail.trim()}. Ask them to create an account first, then set up the household.';
    }
    return message;
  }

  List<GroupExpense> get _currentMonthExpenses {
    final now = DateTime.now();
    return _expenses
        .where((expense) {
          final date = expense.date.toLocal();
          return date.year == now.year && date.month == now.month;
        })
        .toList(growable: false);
  }

  bool _memberPaidExpense(GroupMember member, GroupExpense expense) {
    final paidBy = (expense.paidBy.isNotEmpty
        ? expense.paidBy
        : expense.createdBy);
    final normalized = paidBy.trim().toLowerCase();
    final candidates =
        <String>{
          member.uid,
          member.displayName,
          member.email,
          member.phone,
          member.label,
        }.map((value) => value.trim().toLowerCase()).where((value) {
          return value.isNotEmpty;
        }).toSet();
    return candidates.contains(normalized);
  }

  Map<String, double> _paidThisMonth(GroupMember member) {
    return _sumAmounts(
      _currentMonthExpenses.where(
        (expense) => _memberPaidExpense(member, expense),
      ),
    );
  }

  List<_FamilyCategoryTotal> _categoryTotals() {
    final totals = <String, _FamilyCategoryTotal>{};
    for (final expense in _currentMonthExpenses) {
      final category = _categoryForExpense(expense);
      final current = totals[category] ?? _FamilyCategoryTotal.empty(category);
      totals[category] = current.add(expense.amountsByCurrency);
    }
    final items = totals.values.toList(growable: false)
      ..sort(
        (a, b) =>
            _amountMagnitude(b.amounts).compareTo(_amountMagnitude(a.amounts)),
      );
    return items;
  }

  Map<String, double> _sumAmounts(Iterable<GroupExpense> expenses) {
    final totals = <String, double>{};
    for (final expense in expenses) {
      for (final entry in expense.amountsByCurrency.entries) {
        totals[entry.key] = (totals[entry.key] ?? 0) + entry.value;
      }
    }
    return totals;
  }

  double _amountMagnitude(Map<String, double> amounts) {
    return amounts.values.fold<double>(0, (sum, amount) => sum + amount.abs());
  }

  String _categoryForExpense(GroupExpense expense) {
    final category = expense.category.trim();
    if (category.isNotEmpty) return category;
    return _categoryForDescription(expense.description);
  }

  String _categoryForDescription(String description) {
    final text = description.toLowerCase();
    if (text.contains('grocery') ||
        text.contains('groceries') ||
        text.contains('food')) {
      return 'Groceries';
    }
    if (text.contains('electric') ||
        text.contains('utility') ||
        text.contains('gas') ||
        text.contains('water') ||
        text.contains('internet')) {
      return 'Utilities';
    }
    if (text.contains('rent') ||
        text.contains('housing') ||
        text.contains('maintenance')) {
      return 'Rent and housing';
    }
    if (text.contains('school') ||
        text.contains('kid') ||
        text.contains('fee')) {
      return 'School and kids';
    }
    if (text.contains('cab') ||
        text.contains('fuel') ||
        text.contains('travel')) {
      return 'Travel';
    }
    return 'Other';
  }

  @override
  Widget build(BuildContext context) {
    final family = _selectedFamily;

    if (_loading && family == null) {
      return const AppPageContainer(
        children: [
          AppBalanceTile(
            title: 'Loading family...',
            leadingIcon: Icons.family_restroom,
          ),
        ],
      );
    }

    if (_error != null && family == null) {
      return AppPageContainer(
        children: [
          AppBalanceTile(
            title: 'Failed to load family',
            subtitle: Text(_error!),
            leadingIcon: Icons.error_outline,
          ),
        ],
      );
    }

    if (family == null) {
      return AppPageContainer(
        children: [
          AppEmptyState(
            title: 'No family group yet',
            subtitle:
                'Set up your household, add your spouse, and track shared spending.',
            actionLabel: 'Set up household',
            onAction: _openHouseholdSetup,
          ),
        ],
      );
    }

    final monthExpenses = _currentMonthExpenses;
    final monthSpent = _sumAmounts(monthExpenses);
    final trackedTotal = _sumAmounts(_expenses);
    final progress = _amountMagnitude(trackedTotal) <= 0
        ? 0.0
        : _amountMagnitude(monthSpent) / _amountMagnitude(trackedTotal);
    final trackedTotalForCopy = _amountMagnitude(trackedTotal) <= 0
        ? monthSpent
        : trackedTotal;
    final categories = _categoryTotals();

    return AppPageContainer(
      children: [
        _HouseholdCard(
          family: family,
          memberCount: _members.isEmpty ? family.memberCount : _members.length,
          monthSpent: monthSpent,
          trackedTotal: trackedTotalForCopy,
          progress: progress,
          loading: _loadingDetails,
          onOpen: _openSelectedFamily,
        ),
        const SizedBox(height: 16),
        MonthlyPlanningCard(
          repository: widget.monthlyPlanRepository,
          refreshToken: _monthlyPlanRefreshToken,
        ),
        if (_families.length > 1) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _families
                .map(
                  (item) => ChoiceChip(
                    label: Text(item.name),
                    selected: item.id == family.id,
                    onSelected: (_) {
                      setState(() => _selectedFamily = item);
                      _loadSelectedFamilyDetails();
                    },
                  ),
                )
                .toList(growable: false),
          ),
        ],
        const SizedBox(height: 16),
        AppSectionHeader(
          title: 'Members',
          actionLabel: 'Manage',
          onAction: _openSelectedFamily,
        ),
        if (_loadingDetails && _members.isEmpty)
          const AppBalanceTile(
            title: 'Loading members...',
            leadingIcon: Icons.person_outline,
          )
        else if (_members.isEmpty)
          const AppEmptyState(title: 'No members yet')
        else
          ..._members.map((member) {
            final paid = _paidThisMonth(member);
            return AppBalanceTile(
              title: member.label,
              subtitle: Text(
                '${member.roleLabel} · paid ${AppMoney.formatCurrencyAmounts(paid)} this month',
              ),
              leadingIcon: Icons.person_outline,
              trailing: Text(
                AppMoney.formatCurrencyAmounts(paid),
                style: Theme.of(context).textTheme.labelLarge,
              ),
            );
          }),
        const SizedBox(height: 16),
        AppSectionHeader(
          title: 'Categories',
          actionLabel: 'Open expenses',
          onAction: _openSelectedFamily,
        ),
        if (_loadingDetails && categories.isEmpty)
          const AppBalanceTile(
            title: 'Loading categories...',
            leadingIcon: Icons.receipt_long_outlined,
          )
        else if (categories.isEmpty)
          const AppEmptyState(title: 'No spending this month')
        else
          ...categories.map(
            (category) => AppBalanceTile(
              title: category.label,
              subtitle: Text(
                '${category.count} expense${category.count == 1 ? '' : 's'} · this month',
              ),
              leadingIcon: Icons.receipt_long_outlined,
              trailing: Text(
                AppMoney.formatCurrencyAmounts(category.amounts),
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          ),
      ],
    );
  }
}

class _HouseholdSetupInput {
  const _HouseholdSetupInput({
    required this.householdName,
    required this.spouseEmail,
    required this.yourRole,
    required this.spouseRole,
  });

  final String householdName;
  final String spouseEmail;
  final String yourRole;
  final String spouseRole;
}

class _HouseholdSetupDialog extends StatefulWidget {
  const _HouseholdSetupDialog();

  @override
  State<_HouseholdSetupDialog> createState() => _HouseholdSetupDialogState();
}

class _HouseholdSetupDialogState extends State<_HouseholdSetupDialog> {
  final _householdController = TextEditingController(text: 'Our household');
  final _spouseController = TextEditingController();
  String _yourRole = 'Husband';
  String _spouseRole = 'Wife';

  @override
  void dispose() {
    _householdController.dispose();
    _spouseController.dispose();
    super.dispose();
  }

  void _submit() {
    final householdName = _householdController.text.trim();
    if (householdName.isEmpty) return;
    Navigator.of(context).pop(
      _HouseholdSetupInput(
        householdName: householdName,
        spouseEmail: _spouseController.text.trim(),
        yourRole: _yourRole,
        spouseRole: _spouseRole,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Set up household'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _householdController,
              decoration: const InputDecoration(
                labelText: 'Household name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _spouseController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Spouse email',
                hintText: 'wife@example.com',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final yourRoleField = DropdownButtonFormField<String>(
                  initialValue: _yourRole,
                  decoration: const InputDecoration(
                    labelText: 'Your role',
                    border: OutlineInputBorder(),
                  ),
                  items: familyRoleOptions
                      .map(
                        (role) =>
                            DropdownMenuItem(value: role, child: Text(role)),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value != null) setState(() => _yourRole = value);
                  },
                );
                final spouseRoleField = DropdownButtonFormField<String>(
                  initialValue: _spouseRole,
                  decoration: const InputDecoration(
                    labelText: 'Spouse role',
                    border: OutlineInputBorder(),
                  ),
                  items: familyRoleOptions
                      .map(
                        (role) =>
                            DropdownMenuItem(value: role, child: Text(role)),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value != null) setState(() => _spouseRole = value);
                  },
                );
                if (constraints.maxWidth < 360) {
                  return Column(
                    children: [
                      yourRoleField,
                      const SizedBox(height: 12),
                      spouseRoleField,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: yourRoleField),
                    const SizedBox(width: 12),
                    Expanded(child: spouseRoleField),
                  ],
                );
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
        FilledButton(onPressed: _submit, child: const Text('Create')),
      ],
    );
  }
}

class _HouseholdCard extends StatelessWidget {
  const _HouseholdCard({
    required this.family,
    required this.memberCount,
    required this.monthSpent,
    required this.trackedTotal,
    required this.progress,
    required this.loading,
    required this.onOpen,
  });

  final GroupSummary family;
  final int memberCount;
  final Map<String, double> monthSpent;
  final Map<String, double> trackedTotal;
  final double progress;
  final bool loading;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final percent = (progress * 100).clamp(0, 100).round();
    final hasTrackedSpend = trackedTotal.values.any(
      (amount) => amount.abs() > 0.005,
    );
    final outsideThisMonth = Map<String, double>.from(trackedTotal);
    for (final entry in monthSpent.entries) {
      outsideThisMonth[entry.key] =
          (outsideThisMonth[entry.key] ?? 0) - entry.value;
    }
    outsideThisMonth.removeWhere((_, amount) => amount.abs() <= 0.005);

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppAvatar(
                icon: Icons.home,
                size: 44,
                backgroundColor: Color(0xFFCFE0FA),
                foregroundColor: Color(0xFF0C2D63),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      family.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$memberCount member${memberCount == 1 ? '' : 's'} · shared household',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (loading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                IconButton(
                  tooltip: 'Open family expenses',
                  onPressed: onOpen,
                  icon: const Icon(Icons.arrow_forward),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text('This month', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                AppMoney.formatCurrencyAmounts(monthSpent),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  !hasTrackedSpend
                      ? 'tracked'
                      : 'of ${AppMoney.formatCurrencyAmounts(trackedTotal)} tracked',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AppProgressBar(value: progress),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '$percent% this month',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Spacer(),
              Text(
                !hasTrackedSpend
                    ? 'No spending tracked yet'
                    : '${AppMoney.formatCurrencyAmounts(outsideThisMonth)} outside this month',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FamilyCategoryTotal {
  const _FamilyCategoryTotal({
    required this.label,
    required this.amounts,
    required this.count,
  });

  factory _FamilyCategoryTotal.empty(String label) {
    return _FamilyCategoryTotal(label: label, amounts: const {}, count: 0);
  }

  final String label;
  final Map<String, double> amounts;
  final int count;

  _FamilyCategoryTotal add(Map<String, double> values) {
    final updated = Map<String, double>.from(amounts);
    for (final entry in values.entries) {
      updated[entry.key] = (updated[entry.key] ?? 0) + entry.value;
    }
    return _FamilyCategoryTotal(
      label: label,
      amounts: Map.unmodifiable(updated),
      count: count + 1,
    );
  }
}
