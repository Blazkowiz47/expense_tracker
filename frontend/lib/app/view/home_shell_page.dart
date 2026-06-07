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
import 'package:expense_tracker/features/recurring/view/recurring_page.dart';
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

  void _openAddExpense({
    bool initialBillUpload = false,
    bool forcePersonal = false,
  }) {
    if (!forcePersonal && _destinations[_selectedIndex].label == 'Family') {
      Navigator.of(context).push<void>(
        platformPageRoute(
          builder: (_) => FamilyPage(
            autoRefresh: true,
            openAddExpenseOnLaunch: true,
            initialExpenseCategory: 'Groceries',
            initialExpenseDescription: initialBillUpload ? null : 'Groceries',
            initialBillUpload: initialBillUpload,
          ),
        ),
      );
      return;
    }
    final expensesBloc = context.read<ExpensesBloc>();
    Navigator.of(context).push<void>(
      platformPageRoute(
        builder: (context) => BlocProvider.value(
          value: expensesBloc,
          child: AddExpensePage(initialBillUpload: initialBillUpload),
        ),
      ),
    );
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
            desktop: _buildDesktopScaffold(accountPhotoUrl),
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
    final actions = [
      _QuickAction(
        label: 'Groceries',
        icon: Icons.shopping_basket_outlined,
        onTap: () => _runAction(_openHouseholdGroceries),
      ),
      _QuickAction(
        label: 'Scan bill',
        icon: Icons.document_scanner_outlined,
        onTap: () => _runAction(() {
          _openScanBill();
        }),
      ),
      _QuickAction(
        label: 'Recurring',
        icon: Icons.event_repeat,
        onTap: () => _runAction(_openRecurringPage),
      ),
      _QuickAction(
        label: 'Settle up',
        icon: Icons.payments_outlined,
        onTap: () => _runAction(_openFriendsPage),
      ),
    ];

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
