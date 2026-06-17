import 'package:expense_tracker/app/routes/app_routes.dart';
import 'package:expense_tracker/core/constants/app_spacing.dart';
import 'package:expense_tracker/core/utils/platform_page_route.dart';
import 'package:expense_tracker/core/utils/platform_widget.dart';
import 'package:expense_tracker/core/utils/responsive_layout.dart';
import 'package:expense_tracker/core/widgets/smart_selection_area.dart';
import 'package:expense_tracker/data/models/group.dart';
import 'package:expense_tracker/features/auth/cubit/auth_cubit.dart';
import 'package:expense_tracker/features/account/view/account_page.dart';
import 'package:expense_tracker/features/activity/view/activity_page.dart';
import 'package:expense_tracker/features/credit_cards/view/credit_cards_page.dart';
import 'package:expense_tracker/features/dashboard/bloc/dashboard_snapshot_cubit.dart';
import 'package:expense_tracker/features/dashboard/models/dashboard_snapshot.dart';
import 'package:expense_tracker/features/dashboard/repositories/api_dashboard_snapshot_repository.dart';
import 'package:expense_tracker/features/dashboard/repositories/dashboard_snapshot_repository.dart';
import 'package:expense_tracker/features/dashboard/view/home_page.dart';
import 'package:expense_tracker/features/expenses/bloc/expenses_bloc.dart';
import 'package:expense_tracker/features/expenses/view/add_expense_page.dart';
import 'package:expense_tracker/features/family/view/family_page.dart';
import 'package:expense_tracker/features/friends/view/friends_page.dart';
import 'package:expense_tracker/features/groups/models/group_summary.dart';
import 'package:expense_tracker/features/groups/repositories/api_groups_repository.dart';
import 'package:expense_tracker/features/groups/view/groups_page.dart';
import 'package:expense_tracker/features/loans/view/loans_page.dart';
import 'package:expense_tracker/features/receipts/view/price_book_page.dart';
import 'package:expense_tracker/features/recurring/view/recurring_page.dart';
import 'package:expense_tracker/features/savings/view/savings_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;

class HomeShellPage extends StatefulWidget {
  const HomeShellPage({this.initialIndex = 0, this.repository, super.key});

  final int initialIndex;
  final DashboardSnapshotRepository? repository;

  @override
  State<HomeShellPage> createState() => _HomeShellPageState();
}

class _HomeShellPageState extends State<HomeShellPage>
    with SingleTickerProviderStateMixin {
  late int _selectedIndex;
  http.Client? _httpClient;
  late final http.Client _actionHttpClient;
  late final bool _ownsHttpClient;
  late final DashboardSnapshotCubit _dashboardCubit;
  late final AnimationController _actionMenuController;
  late final Animation<double> _actionMenuAnimation;
  bool _actionMenuOpen = false;

  static const _destinations = <_ShellDestination>[
    _ShellDestination(
      label: 'Home',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
      page: SizedBox.shrink(),
    ),
    _ShellDestination(
      label: 'Family',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
      page: FamilyPage(),
    ),
    _ShellDestination(
      label: 'Activity',
      icon: Icons.list_alt_outlined,
      selectedIcon: Icons.list_alt,
      page: ActivityPage(),
    ),
    _ShellDestination(
      label: 'Account',
      icon: Icons.account_circle_outlined,
      selectedIcon: Icons.account_circle,
      page: AccountPage(),
    ),
  ];

  bool get _showAddExpenseButton =>
      _destinations[_selectedIndex].label != 'Account';

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _actionHttpClient = http.Client();
    _ownsHttpClient = widget.repository == null;
    final repository = widget.repository ?? _buildApiRepository();
    _dashboardCubit = DashboardSnapshotCubit(repository: repository)..load();
    _actionMenuController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      reverseDuration: const Duration(milliseconds: 140),
    );
    _actionMenuAnimation = CurvedAnimation(
      parent: _actionMenuController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  DashboardSnapshotRepository _buildApiRepository() {
    _httpClient = http.Client();
    return ApiDashboardSnapshotRepository(client: _httpClient!);
  }

  @override
  void dispose() {
    _dashboardCubit.close();
    _actionMenuController.dispose();
    if (_ownsHttpClient) {
      _httpClient?.close();
    }
    _actionHttpClient.close();
    super.dispose();
  }

  void _onDestinationSelected(int index) {
    if (index == _selectedIndex) return;
    _closeActionMenu();
    final path = _routeForIndex(index);
    try {
      Navigator.of(context).pushReplacementNamed(path);
    } catch (_) {
      if (mounted) {
        setState(() => _selectedIndex = index);
      }
    }
  }

  void _toggleActionMenu() {
    setState(() => _actionMenuOpen = !_actionMenuOpen);
    if (_actionMenuOpen) {
      _actionMenuController.forward();
    } else {
      _actionMenuController.reverse();
    }
  }

  void _closeActionMenu() {
    if (!_actionMenuOpen) return;
    setState(() => _actionMenuOpen = false);
    _actionMenuController.reverse();
  }

  void _runAction(VoidCallback action) {
    _closeActionMenu();
    action();
  }

  Future<bool> _openAddExpense({
    bool initialBillUpload = false,
    bool forcePersonal = false,
    String? initialCategory,
    String? initialDescription,
    double? initialAmount,
    String? initialCurrency,
  }) {
    if (!forcePersonal && _destinations[_selectedIndex].label == 'Family') {
      final category = (initialCategory?.trim().isNotEmpty == true)
          ? initialCategory!.trim()
          : 'Groceries';
      final description = initialBillUpload
          ? null
          : (initialDescription?.trim().isNotEmpty == true
                ? initialDescription!.trim()
                : category);
      Navigator.of(context).push<void>(
        platformPageRoute(
          builder: (_) => FamilyPage(
            autoRefresh: true,
            openAddExpenseOnLaunch: true,
            initialExpenseCategory: category,
            initialExpenseDescription: description,
            initialBillUpload: initialBillUpload,
          ),
        ),
      );
      return Future.value(false);
    }
    final expensesBloc = context.read<ExpensesBloc>();
    return Navigator.of(context)
        .push<bool>(
          platformPageRoute(
            builder: (context) => BlocProvider.value(
              value: expensesBloc,
              child: AddExpensePage(
                initialBillUpload: initialBillUpload,
                initialCategory: initialCategory,
                initialDescription: initialDescription,
                initialAmount: initialAmount,
                initialCurrency: initialCurrency,
              ),
            ),
          ),
        )
        .then((value) => value == true);
  }

  void _openHouseholdGroceries() {
    Navigator.of(context).push<void>(
      platformPageRoute(
        builder: (_) => const FamilyPage(
          autoRefresh: true,
          openAddExpenseOnLaunch: true,
          initialExpenseCategory: 'Groceries',
          initialExpenseDescription: 'Groceries',
        ),
      ),
    );
  }

  void _openHouseholdBillScan() {
    Navigator.of(context).push<void>(
      platformPageRoute(
        builder: (_) => const FamilyPage(
          autoRefresh: true,
          openAddExpenseOnLaunch: true,
          initialExpenseCategory: 'Other',
          initialBillUpload: true,
        ),
      ),
    );
  }

  Future<void> _openScanBill() async {
    if (_destinations[_selectedIndex].label == 'Family') {
      _openHouseholdBillScan();
      return;
    }
    final target = await showDialog<_BillScanTarget>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Where should this bill go?'),
        content: const Text('Choose household for shared family spending.'),
        actions: [
          TextButton.icon(
            onPressed: () =>
                Navigator.of(context).pop(_BillScanTarget.personal),
            icon: const Icon(Icons.person_outline),
            label: const Text('Personal bill'),
          ),
          FilledButton.icon(
            onPressed: () =>
                Navigator.of(context).pop(_BillScanTarget.household),
            icon: const Icon(Icons.home_outlined),
            label: const Text('Household bill'),
          ),
        ],
      ),
    );
    if (!mounted || target == null) return;
    switch (target) {
      case _BillScanTarget.household:
        _openHouseholdBillScan();
      case _BillScanTarget.personal:
        _openAddExpense(initialBillUpload: true, forcePersonal: true);
    }
  }

  void _openSharedSpace(GroupType groupType) {
    Navigator.of(context).push<void>(
      platformPageRoute(
        builder: (_) => GroupsPage(groupType: groupType, autoRefresh: true),
      ),
    );
  }

  void _openFriendsPage() {
    Navigator.of(context).push<void>(
      platformPageRoute(builder: (_) => const FriendsPage(autoRefresh: true)),
    );
  }

  void _openRecurringPage({
    String? initialMonth,
    String? initialOccurrenceId,
    bool openConfirmOnLaunch = false,
  }) {
    Navigator.of(context).push<void>(
      platformPageRoute(
        builder: (_) => RecurringPage(
          autoRefresh: true,
          initialMonth: initialMonth,
          initialOccurrenceId: initialOccurrenceId,
          openConfirmOnLaunch: openConfirmOnLaunch,
        ),
      ),
    );
  }

  void _openLoansPage() {
    Navigator.of(context).push<void>(
      platformPageRoute(builder: (_) => const LoansPage(autoRefresh: true)),
    );
  }

  void _openCreditCardsPage() {
    Navigator.of(
      context,
    ).push<void>(platformPageRoute(builder: (_) => const CreditCardsPage()));
  }

  void _openSavingsPage() {
    Navigator.of(context).push<void>(
      platformPageRoute(builder: (_) => const SavingsPage(autoRefresh: true)),
    );
  }

  void _openPriceBookPage() {
    Navigator.of(
      context,
    ).push<void>(platformPageRoute(builder: (_) => const PriceBookPage()));
  }

  void _openPersonalPlannedExpense(String category) {
    final label = category.trim().isEmpty ? 'Personal' : category.trim();
    _openAddExpense(
      forcePersonal: true,
      initialCategory: label,
      initialDescription: label,
    );
  }

  Future<bool> _recordPersonalPlannedPayment(
    String category, {
    required double amount,
    required String currency,
  }) {
    final label = category.trim().isEmpty ? 'Personal' : category.trim();
    return _openAddExpense(
      forcePersonal: true,
      initialCategory: label,
      initialDescription: label,
      initialAmount: amount,
      initialCurrency: currency,
    );
  }

  void _openActivityCategory(String category) {
    final label = category.trim();
    Navigator.of(context).push<void>(
      platformPageRoute(
        builder: (_) =>
            ActivityPage(autoRefresh: true, initialCategoryFilter: label),
      ),
    );
  }

  void _openGroupExpenseAction(DailyActionItem item) {
    final groupId = item.groupId.trim();
    final expenseId = item.expenseId.trim();
    if (groupId.isEmpty || expenseId.isEmpty) {
      _openDashboardActionDestination(item.destination);
      return;
    }
    final groupName = item.subtitle.trim().isNotEmpty
        ? item.subtitle.trim()
        : 'Group';
    final group = GroupSummary(
      id: groupId,
      name: groupName,
      groupType: item.destination == 'family'
          ? GroupType.family
          : GroupType.split,
      memberCount: 0,
    );
    Navigator.of(context)
        .push<bool>(
          platformPageRoute(
            builder: (_) => GroupDetailsPage(
              group: group,
              repository: ApiGroupsRepository(client: _actionHttpClient),
              initialExpenseId: expenseId,
              autoRefresh: true,
            ),
          ),
        )
        .then((changed) {
          if (changed == true && mounted) {
            _dashboardCubit.load(showLoading: false);
          }
        });
  }

  void _openFamilyReviewAction(DailyActionItem item) {
    final category = item.category.trim();
    Navigator.of(context).push<void>(
      platformPageRoute(
        builder: (_) => FamilyPage(
          autoRefresh: true,
          openReviewOnLaunch: true,
          initialReviewFilter: GroupExpenseReviewFilter(
            category: category,
            currentMonthOnly: true,
          ),
        ),
      ),
    );
  }

  void _openDashboardAction(DailyActionItem item) {
    switch (item.actionType) {
      case 'confirm_recurring':
        final occurrenceId = item.occurrenceId.trim();
        if (occurrenceId.isNotEmpty) {
          _openRecurringPage(
            initialMonth: item.period,
            initialOccurrenceId: occurrenceId,
            openConfirmOnLaunch: true,
          );
          return;
        }
        break;
      case 'attach_group_receipt':
        _openGroupExpenseAction(item);
        return;
      case 'review_budget_category':
        _openFamilyReviewAction(item);
        return;
    }
    _openDashboardActionDestination(item.destination);
  }

  void _openDashboardActionDestination(String destination) {
    switch (destination) {
      case 'friends':
        _openFriendsPage();
        return;
      case 'groups':
        _openSharedSpace(GroupType.split);
        return;
      case 'family':
        _onDestinationSelected(1);
        return;
      case 'recurring':
        _openRecurringPage();
        return;
      case 'loans':
        _openLoansPage();
        return;
      case 'credit_cards':
        _openCreditCardsPage();
        return;
      case 'savings':
        _openSavingsPage();
        return;
      default:
        _onDestinationSelected(2);
    }
  }

  Widget _pageForDestination(_ShellDestination destination, int index) {
    final autoRefresh = index == _selectedIndex;
    if (destination.label == 'Home') {
      return HomePage(
        autoRefresh: autoRefresh,
        onOpenFriends: _openFriendsPage,
        onOpenGroups: () => _openSharedSpace(GroupType.split),
        onOpenFamily: () => _onDestinationSelected(1),
        onOpenRecurring: _openRecurringPage,
        onOpenAction: _openDashboardAction,
        onAddExpenseForCategory: _openPersonalPlannedExpense,
        onRecordPlannedPayment: _recordPersonalPlannedPayment,
        onOpenActivityCategory: _openActivityCategory,
      );
    }
    if (destination.label == 'Family') {
      return FamilyPage(autoRefresh: autoRefresh);
    }
    if (destination.label == 'Activity') {
      return ActivityPage(autoRefresh: autoRefresh);
    }
    return destination.page;
  }

  Widget _withActionScrim(Widget child) {
    return Stack(
      children: [
        child,
        if (_actionMenuOpen)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _closeActionMenu,
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.08)),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final accountPhotoUrl = context.select(
      (AuthCubit? cubit) => cubit?.state.user?.photoUrl,
    );
    return BlocProvider.value(
      value: _dashboardCubit,
      child: SmartSelectionArea(
        child: PlatformWidget(
          ios: ResponsiveLayout(
            mobile: _buildCupertinoMobileShell(accountPhotoUrl),
            tablet: _buildDesktopScaffold(accountPhotoUrl),
            desktop: _buildDesktopScaffold(accountPhotoUrl),
          ),
          android: ResponsiveLayout(
            mobile: _buildMobileScaffold(
              centerTitle: false,
              accountPhotoUrl: accountPhotoUrl,
            ),
            tablet: _buildDesktopScaffold(accountPhotoUrl),
            desktop: _buildDesktopScaffold(accountPhotoUrl),
          ),
          web: ResponsiveLayout(
            mobile: _buildMobileScaffold(
              centerTitle: false,
              accountPhotoUrl: accountPhotoUrl,
            ),
            tablet: _buildDesktopScaffold(accountPhotoUrl),
            desktop: _buildWideWebScaffold(accountPhotoUrl),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileScaffold({
    required bool centerTitle,
    String? accountPhotoUrl,
  }) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: centerTitle,
        title: Text(_destinations[_selectedIndex].label),
      ),
      body: _withActionScrim(
        IndexedStack(
          index: _selectedIndex,
          children: _destinations
              .asMap()
              .entries
              .map((entry) => _pageForDestination(entry.value, entry.key))
              .toList(growable: false),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onDestinationSelected,
        destinations: _destinations
            .asMap()
            .entries
            .map((entry) {
              final index = entry.key;
              final destination = entry.value;
              return NavigationDestination(
                icon: _buildDestinationIcon(
                  index: index,
                  selected: false,
                  accountPhotoUrl: accountPhotoUrl,
                ),
                selectedIcon: _buildDestinationIcon(
                  index: index,
                  selected: true,
                  accountPhotoUrl: accountPhotoUrl,
                ),
                label: destination.label,
              );
            })
            .toList(growable: false),
      ),
      floatingActionButton: _showAddExpenseButton ? _buildActionFab() : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildDesktopScaffold(String? accountPhotoUrl) {
    return Scaffold(
      body: _withActionScrim(
        SafeArea(
          child: Row(
            children: [
              NavigationRail(
                selectedIndex: _selectedIndex,
                labelType: NavigationRailLabelType.all,
                onDestinationSelected: _onDestinationSelected,
                destinations: _destinations
                    .asMap()
                    .entries
                    .map(
                      (entry) => NavigationRailDestination(
                        icon: _buildDestinationIcon(
                          index: entry.key,
                          selected: false,
                          accountPhotoUrl: accountPhotoUrl,
                        ),
                        selectedIcon: _buildDestinationIcon(
                          index: entry.key,
                          selected: true,
                          accountPhotoUrl: accountPhotoUrl,
                        ),
                        label: Text(entry.value.label),
                      ),
                    )
                    .toList(growable: false),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        20,
                        AppSpacing.lg,
                        12,
                      ),
                      child: Row(
                        children: [
                          Text(
                            _destinations[_selectedIndex].label,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: IndexedStack(
                        index: _selectedIndex,
                        children: _destinations
                            .asMap()
                            .entries
                            .map(
                              (entry) =>
                                  _pageForDestination(entry.value, entry.key),
                            )
                            .toList(growable: false),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: _showAddExpenseButton ? _buildActionFab() : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildWideWebScaffold(String? accountPhotoUrl) {
    final colors = Theme.of(context).colorScheme;
    final headerActions = <_QuickAction>[
      _QuickAction(
        label: 'Price book',
        icon: Icons.price_check_outlined,
        onTap: _openPriceBookPage,
      ),
      _QuickAction(
        label: 'Recurring',
        icon: Icons.event_repeat,
        onTap: _openRecurringPage,
      ),
    ];
    final shortcuts = _quickActions();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border(
                  bottom: BorderSide(color: colors.outlineVariant),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: colors.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.account_balance_wallet_outlined,
                            color: colors.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Expense Tracker',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              Text(
                                'Family and personal finance',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: colors.outline),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 2,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _destinations
                            .asMap()
                            .entries
                            .map(
                              (entry) => _WideNavChip(
                                label: entry.value.label,
                                icon: _buildDestinationIcon(
                                  index: entry.key,
                                  selected: _selectedIndex == entry.key,
                                  accountPhotoUrl: accountPhotoUrl,
                                ),
                                selected: _selectedIndex == entry.key,
                                onTap: () => _onDestinationSelected(entry.key),
                              ),
                            )
                            .toList(growable: false),
                      ),
                    ),
                  ),
                  if (_showAddExpenseButton) ...[
                    const SizedBox(width: 24),
                    FilledButton.icon(
                      onPressed: _openAddExpense,
                      icon: const Icon(Icons.receipt_long),
                      label: const Text('Add expense'),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1480),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _destinations[_selectedIndex].label,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.headlineMedium,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _widePageSubtitle,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(color: colors.outline),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              alignment: WrapAlignment.end,
                              children: headerActions
                                  .map(
                                    (action) => OutlinedButton.icon(
                                      onPressed: () => _runAction(action.onTap),
                                      icon: Icon(action.icon, size: 18),
                                      label: Text(action.label),
                                    ),
                                  )
                                  .toList(growable: false),
                            ),
                          ],
                        ),
                        if (_selectedIndex != 3) ...[
                          const SizedBox(height: 18),
                          Text(
                            'Quick access',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: shortcuts
                                  .map(
                                    (action) => Padding(
                                      padding: const EdgeInsets.only(right: 12),
                                      child: _WideShortcutTile(action: action),
                                    ),
                                  )
                                  .toList(growable: false),
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        Expanded(
                          child: IndexedStack(
                            index: _selectedIndex,
                            children: _destinations
                                .asMap()
                                .entries
                                .map(
                                  (entry) => _pageForDestination(
                                    entry.value,
                                    entry.key,
                                  ),
                                )
                                .toList(growable: false),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCupertinoMobileShell(String? accountPhotoUrl) {
    final tabItems = _destinations
        .asMap()
        .entries
        .map(
          (entry) => BottomNavigationBarItem(
            icon: _buildCupertinoDestinationIcon(
              index: entry.key,
              selected: false,
              accountPhotoUrl: accountPhotoUrl,
            ),
            activeIcon: _buildCupertinoDestinationIcon(
              index: entry.key,
              selected: true,
              accountPhotoUrl: accountPhotoUrl,
            ),
            label: entry.value.label,
          ),
        )
        .toList(growable: false);

    return CupertinoTabScaffold(
      tabBar: CupertinoTabBar(
        currentIndex: _selectedIndex,
        items: tabItems,
        onTap: _onDestinationSelected,
      ),
      tabBuilder: (context, index) {
        final destination = _destinations[index];
        final showAddButton = destination.label != 'Account';
        final page = _pageForDestination(destination, index);

        return CupertinoTabView(
          builder: (context) {
            return CupertinoPageScaffold(
              navigationBar: CupertinoNavigationBar(
                middle: Text(destination.label),
                trailing: showAddButton
                    ? CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(30, 30),
                        onPressed: () => _openAddExpense(),
                        child: const Icon(CupertinoIcons.add_circled_solid),
                      )
                    : null,
              ),
              child: SafeArea(
                bottom: false,
                child: Stack(
                  children: [
                    Positioned.fill(child: page),
                    if (_actionMenuOpen)
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _closeActionMenu,
                          child: ColoredBox(
                            color: Colors.black.withValues(alpha: 0.08),
                          ),
                        ),
                      ),
                    if (showAddButton)
                      Positioned(
                        right: AppSpacing.md,
                        bottom: 90,
                        child: _buildActionFab(compact: true),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildActionFab({bool compact = false}) {
    final actions = _quickActions();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SizeTransition(
          sizeFactor: _actionMenuAnimation,
          axisAlignment: -1,
          child: FadeTransition(
            opacity: _actionMenuAnimation,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: actions
                    .map(
                      (action) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _QuickActionButton(action: action),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FloatingActionButton.small(
              heroTag: 'quick-actions-toggle',
              tooltip: _actionMenuOpen
                  ? 'Close quick actions'
                  : 'Quick actions',
              onPressed: _toggleActionMenu,
              child: AnimatedRotation(
                turns: _actionMenuOpen ? 0.25 : 0,
                duration: const Duration(milliseconds: 160),
                child: Icon(_actionMenuOpen ? Icons.close : Icons.more_horiz),
              ),
            ),
            const SizedBox(width: 10),
            FloatingActionButton.extended(
              heroTag: 'add-expense-action',
              onPressed: () => _openAddExpense(),
              icon: const Icon(Icons.receipt_long),
              label: Text(compact ? 'Add' : 'Add expense'),
            ),
          ],
        ),
      ],
    );
  }

  IconData _toCupertinoIcon(IconData materialIcon) {
    switch (materialIcon) {
      case Icons.person_outline:
        return CupertinoIcons.person;
      case Icons.person:
        return CupertinoIcons.person_fill;
      case Icons.dashboard_outlined:
        return CupertinoIcons.chart_bar;
      case Icons.dashboard:
        return CupertinoIcons.chart_bar_fill;
      case Icons.home_outlined:
        return CupertinoIcons.house;
      case Icons.home:
        return CupertinoIcons.house_fill;
      case Icons.group_outlined:
        return CupertinoIcons.group;
      case Icons.group:
        return CupertinoIcons.group_solid;
      case Icons.list_alt_outlined:
        return CupertinoIcons.list_bullet;
      case Icons.list_alt:
        return CupertinoIcons.list_bullet_below_rectangle;
      case Icons.account_circle_outlined:
        return CupertinoIcons.profile_circled;
      case Icons.account_circle:
        return CupertinoIcons.profile_circled;
      default:
        return CupertinoIcons.circle;
    }
  }

  String _routeForIndex(int index) {
    switch (index) {
      case 0:
        return AppRoutes.home;
      case 1:
        return AppRoutes.family;
      case 2:
        return AppRoutes.activity;
      case 3:
        return AppRoutes.account;
      default:
        return AppRoutes.home;
    }
  }

  Widget _buildDestinationIcon({
    required int index,
    required bool selected,
    required String? accountPhotoUrl,
  }) {
    final destination = _destinations[index];
    if (destination.label != 'Account') {
      return Icon(selected ? destination.selectedIcon : destination.icon);
    }
    return _AccountDestinationAvatar(
      photoUrl: accountPhotoUrl,
      selected: selected,
    );
  }

  Widget _buildCupertinoDestinationIcon({
    required int index,
    required bool selected,
    required String? accountPhotoUrl,
  }) {
    final destination = _destinations[index];
    if (destination.label != 'Account') {
      return Icon(
        _toCupertinoIcon(
          selected ? destination.selectedIcon : destination.icon,
        ),
      );
    }
    return _AccountDestinationAvatar(
      photoUrl: accountPhotoUrl,
      selected: selected,
      size: 22,
    );
  }

  List<_QuickAction> _quickActions() {
    return [
      _QuickAction(
        label: 'Groceries',
        icon: Icons.shopping_basket_outlined,
        onTap: () => _runAction(_openHouseholdGroceries),
      ),
      _QuickAction(
        label: 'Scan bill',
        icon: Icons.document_scanner_outlined,
        onTap: () => _runAction(_openScanBill),
      ),
      _QuickAction(
        label: 'Price book',
        icon: Icons.price_check_outlined,
        onTap: () => _runAction(_openPriceBookPage),
      ),
      _QuickAction(
        label: 'Recurring',
        icon: Icons.event_repeat,
        onTap: () => _runAction(_openRecurringPage),
      ),
      _QuickAction(
        label: 'Loans',
        icon: Icons.account_balance_outlined,
        onTap: () => _runAction(_openLoansPage),
      ),
      _QuickAction(
        label: 'Credit cards',
        icon: Icons.credit_card,
        onTap: () => _runAction(_openCreditCardsPage),
      ),
      _QuickAction(
        label: 'Savings',
        icon: Icons.savings_outlined,
        onTap: () => _runAction(_openSavingsPage),
      ),
      _QuickAction(
        label: 'Friend balances',
        icon: Icons.payments_outlined,
        onTap: () => _runAction(_openFriendsPage),
      ),
    ];
  }

  String get _widePageSubtitle {
    switch (_destinations[_selectedIndex].label) {
      case 'Home':
        return 'Track budgets, shared routines, and what needs attention this month.';
      case 'Family':
        return 'Manage household members, roles, and shared spending in one place.';
      case 'Activity':
        return 'Review recent expenses, receipts, and month-to-date changes.';
      case 'Account':
        return 'Adjust your profile, sign-in details, and personal preferences.';
      default:
        return '';
    }
  }
}

class _ShellDestination {
  const _ShellDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.page,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget page;
}

enum _BillScanTarget { household, personal }

class _QuickAction {
  const _QuickAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({required this.action});

  final _QuickAction action;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 148),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    action.label,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                const SizedBox(width: 10),
                Icon(action.icon, size: 20, color: colorScheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WideNavChip extends StatelessWidget {
  const _WideNavChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Widget icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colors.primaryContainer : colors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconTheme(
                data: IconThemeData(
                  size: 20,
                  color: selected
                      ? colors.onPrimaryContainer
                      : colors.onSurfaceVariant,
                ),
                child: icon,
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected
                      ? colors.onPrimaryContainer
                      : colors.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WideShortcutTile extends StatelessWidget {
  const _WideShortcutTile({required this.action});

  final _QuickAction action;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: 172,
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: action.onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: colors.secondaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    action.icon,
                    size: 18,
                    color: colors.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    action.label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountDestinationAvatar extends StatelessWidget {
  const _AccountDestinationAvatar({
    required this.photoUrl,
    required this.selected,
    this.size = 22,
  });

  final String? photoUrl;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (photoUrl == null || photoUrl!.isEmpty) {
      return Icon(
        selected ? Icons.account_circle : Icons.account_circle_outlined,
      );
    }

    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Image.network(
          photoUrl!,
          fit: BoxFit.cover,
          webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
          errorBuilder: (context, error, stackTrace) => Icon(
            selected ? Icons.account_circle : Icons.account_circle_outlined,
            size: size,
          ),
        ),
      ),
    );
  }
}
