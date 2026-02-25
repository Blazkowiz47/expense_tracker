import 'package:expense_tracker/core/constants/app_spacing.dart';
import 'package:expense_tracker/core/utils/platform_page_route.dart';
import 'package:expense_tracker/core/utils/platform_widget.dart';
import 'package:expense_tracker/core/utils/responsive_layout.dart';
import 'package:expense_tracker/features/account/view/account_page.dart';
import 'package:expense_tracker/features/activity/view/activity_page.dart';
import 'package:expense_tracker/features/dashboard/bloc/dashboard_snapshot_cubit.dart';
import 'package:expense_tracker/features/dashboard/repositories/api_dashboard_snapshot_repository.dart';
import 'package:expense_tracker/features/dashboard/repositories/dashboard_snapshot_repository.dart';
import 'package:expense_tracker/features/expenses/view/add_expense_page.dart';
import 'package:expense_tracker/features/friends/view/friends_page.dart';
import 'package:expense_tracker/features/groups/view/groups_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;

class HomeShellPage extends StatefulWidget {
  const HomeShellPage({this.repository, super.key});

  final DashboardSnapshotRepository? repository;

  @override
  State<HomeShellPage> createState() => _HomeShellPageState();
}

class _HomeShellPageState extends State<HomeShellPage> {
  int _selectedIndex = 0;
  http.Client? _httpClient;
  late final bool _ownsHttpClient;
  late final DashboardSnapshotCubit _dashboardCubit;

  static const _destinations = <_ShellDestination>[
    _ShellDestination(
      label: 'Friends',
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
      page: FriendsPage(),
    ),
    _ShellDestination(
      label: 'Groups',
      icon: Icons.group_outlined,
      selectedIcon: Icons.group,
      page: GroupsPage(),
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

  bool get _showAddExpenseButton => _selectedIndex < 3;

  @override
  void initState() {
    super.initState();
    _ownsHttpClient = widget.repository == null;
    final repository = widget.repository ?? _buildApiRepository();
    _dashboardCubit = DashboardSnapshotCubit(repository: repository)..load();
  }

  DashboardSnapshotRepository _buildApiRepository() {
    _httpClient = http.Client();
    return ApiDashboardSnapshotRepository(client: _httpClient!);
  }

  @override
  void dispose() {
    _dashboardCubit.close();
    if (_ownsHttpClient) {
      _httpClient?.close();
    }
    super.dispose();
  }

  void _onDestinationSelected(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _openAddExpense() {
    Navigator.of(context).push<void>(
      platformPageRoute(builder: (context) => const AddExpensePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _dashboardCubit,
      child: PlatformWidget(
        ios: ResponsiveLayout(
          mobile: _buildCupertinoMobileShell(),
          tablet: _buildDesktopScaffold(),
          desktop: _buildDesktopScaffold(),
        ),
        android: ResponsiveLayout(
          mobile: _buildMobileScaffold(centerTitle: false),
          tablet: _buildDesktopScaffold(),
          desktop: _buildDesktopScaffold(),
        ),
        web: ResponsiveLayout(
          mobile: _buildMobileScaffold(centerTitle: false),
          tablet: _buildDesktopScaffold(),
          desktop: _buildDesktopScaffold(),
        ),
      ),
    );
  }

  Widget _buildMobileScaffold({required bool centerTitle}) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: centerTitle,
        title: Text(_destinations[_selectedIndex].label),
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: _destinations.map((d) => d.page).toList(growable: false),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onDestinationSelected,
        destinations: _destinations
            .map(
              (d) => NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: d.label,
              ),
            )
            .toList(growable: false),
      ),
      floatingActionButton: _showAddExpenseButton
          ? _buildAddExpenseFab()
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildDesktopScaffold() {
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            NavigationRail(
              selectedIndex: _selectedIndex,
              labelType: NavigationRailLabelType.all,
              onDestinationSelected: _onDestinationSelected,
              destinations: _destinations
                  .map(
                    (d) => NavigationRailDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selectedIcon),
                      label: Text(d.label),
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
                          .map((d) => d.page)
                          .toList(growable: false),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _showAddExpenseButton
          ? _buildAddExpenseFab()
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildCupertinoMobileShell() {
    final tabItems = _destinations
        .map(
          (d) => BottomNavigationBarItem(
            icon: Icon(_toCupertinoIcon(d.icon)),
            activeIcon: Icon(_toCupertinoIcon(d.selectedIcon)),
            label: d.label,
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
        final showAddButton = index < 3;

        return CupertinoTabView(
          builder: (context) {
            return CupertinoPageScaffold(
              navigationBar: CupertinoNavigationBar(
                middle: Text(destination.label),
                trailing: showAddButton
                    ? CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(30, 30),
                        onPressed: _openAddExpense,
                        child: const Icon(CupertinoIcons.add_circled_solid),
                      )
                    : null,
              ),
              child: SafeArea(
                bottom: false,
                child: Stack(
                  children: [
                    Positioned.fill(child: destination.page),
                    if (showAddButton)
                      Positioned(
                        right: AppSpacing.md,
                        bottom: 90,
                        child: CupertinoButton.filled(
                          onPressed: _openAddExpense,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(CupertinoIcons.add, size: 18),
                              SizedBox(width: 6),
                              Text('Add expense'),
                            ],
                          ),
                        ),
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

  Widget _buildAddExpenseFab() {
    return FloatingActionButton.extended(
      onPressed: _openAddExpense,
      icon: const Icon(Icons.receipt_long),
      label: const Text('Add expense'),
    );
  }

  IconData _toCupertinoIcon(IconData materialIcon) {
    switch (materialIcon) {
      case Icons.person_outline:
        return CupertinoIcons.person;
      case Icons.person:
        return CupertinoIcons.person_fill;
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
