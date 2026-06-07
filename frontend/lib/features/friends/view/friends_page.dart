import 'package:expense_tracker/core/ui/app_ui.dart';
import 'package:expense_tracker/features/friends/models/friend_contact.dart';
import 'package:expense_tracker/features/friends/repositories/api_friends_repository.dart';
import 'package:expense_tracker/features/friends/utils/settlement_balance_calculator.dart';
import 'package:expense_tracker/data/repositories/expenses_repository.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const _friendCurrencyOptions = <String>['INR', 'USD', 'EUR', 'GBP', 'NOK'];

class FriendsPage extends StatefulWidget {
  const FriendsPage({
    super.key,
    this.friendsRepository,
    this.expenseRepository,
    this.client,
    this.autoRefresh = false,
  });

  final ApiFriendsRepository? friendsRepository;
  final ExpenseRepository? expenseRepository;
  final http.Client? client;
  final bool autoRefresh;

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  http.Client? _ownedClient;
  late final ApiFriendsRepository _repository;
  late final ExpenseRepository _expenseRepository;

  List<FriendContact> _friends = const [];
  Map<String, Map<String, double>> _friendSettlementNetByUid = const {};
  bool _loading = true;
  bool _addingFriend = false;
  bool _showFriendAddedSuccess = false;
  String? _removingFriendUid;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.friendsRepository != null && widget.expenseRepository != null) {
      _repository = widget.friendsRepository!;
      _expenseRepository = widget.expenseRepository!;
    } else {
      final client = widget.client ?? http.Client();
      if (widget.client == null) {
        _ownedClient = client;
      }
      _repository =
          widget.friendsRepository ?? ApiFriendsRepository(client: client);
      _expenseRepository =
          widget.expenseRepository ?? ExpenseRepository(client: client);
    }
    _loadFriends();
  }

  @override
  void dispose() {
    if (_ownedClient != null) {
      if (widget.expenseRepository == null) {
        _expenseRepository.dispose();
      } else {
        _ownedClient!.close();
      }
    }
    super.dispose();
  }

  Future<void> _loadFriends({bool showLoading = true}) async {
    setState(() {
      _loading = showLoading || _friends.isEmpty;
      _error = null;
    });
    try {
      final friends = await _repository.fetchFriends();
      final settlementMap = await _loadSettlementBalances();
      if (!mounted) return;
      setState(() {
        _friends = friends;
        _friendSettlementNetByUid = settlementMap;
      });
    } catch (error) {
      if (!mounted) return;
      if (!showLoading && _friends.isNotEmpty) {
        return;
      }
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<Map<String, Map<String, double>>> _loadSettlementBalances() async {
    try {
      return await _repository.fetchBalances();
    } catch (_) {
      await _expenseRepository.refresh();
      final expenses = _expenseRepository.getExpenses();
      return calculateFriendSettlementNetByUidAndCurrency(expenses);
    }
  }

  Future<void> _addFriendFlow() async {
    if (_addingFriend) return;
    final query = await _openAddFriendDialog();
    if (query == null || query.isEmpty) return;

    setState(() => _addingFriend = true);
    try {
      final resolved = await _repository.resolveFriend(query);
      if (!resolved.exists) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No account found.')));
        return;
      }

      await _repository.addFriend(query);
      if (!mounted) return;
      await _loadFriends();
      if (!mounted) return;
      setState(() => _addingFriend = false);
      await _showSuccessTickAnimation();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted && _addingFriend) {
        setState(() => _addingFriend = false);
      }
    }
  }

  Future<void> _showSuccessTickAnimation() async {
    if (!mounted) return;
    setState(() => _showFriendAddedSuccess = true);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() => _showFriendAddedSuccess = false);
  }

  Future<void> _removeFriendFlow(FriendContact friend) async {
    if (_removingFriendUid != null || _addingFriend) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove friend'),
        content: Text('Remove ${friend.label} from your friends list?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _removingFriendUid = friend.uid);
    try {
      final contact = friend.contactHint;
      if (contact.isEmpty) {
        throw Exception('No contact available to remove this friend.');
      }
      await _repository.removeFriend(contact);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Friend removed.')));
      await _loadFriends();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _removingFriendUid = null);
      }
    }
  }

  Future<void> _settleUpFlow(FriendContact friend) async {
    if (_removingFriendUid != null || _addingFriend) return;
    final input = await _openSettleUpDialog(friend);
    if (input == null || input.amount <= 0) return;

    setState(() => _removingFriendUid = friend.uid);
    try {
      await _repository.recordSettlement(
        friendUid: friend.uid,
        direction: input.direction,
        amount: input.amount,
        currency: input.currency,
      );
      final settlementMap = await _loadSettlementBalances();
      if (!mounted) return;
      setState(() => _friendSettlementNetByUid = settlementMap);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Settlement of ${AppMoney.formatCurrency(input.amount, input.currency)} recorded for both accounts.',
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
        setState(() => _removingFriendUid = null);
      }
    }
  }

  Future<_SettleUpInput?> _openSettleUpDialog(FriendContact friend) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var direction = 'paid';
    var currency = 'INR';
    return showDialog<_SettleUpInput>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Settle up with ${friend.label}'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment<String>(
                      value: 'paid',
                      label: Text('I paid them'),
                    ),
                    ButtonSegment<String>(
                      value: 'received',
                      label: Text('They paid me'),
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
                  items: _friendCurrencyOptions
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
                    helperText: direction == 'paid'
                        ? '${friend.label} will owe you this amount.'
                        : 'You will owe ${friend.label} this amount.',
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
                  _SettleUpInput(
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

  Future<String?> _openAddFriendDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add friend'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Email',
            hintText: 'friend@example.com',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Find and add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AppPageContainer(
          onRefresh: () => _loadFriends(showLoading: false),
          autoRefresh: widget.autoRefresh,
          children: [
            AppSectionHeader(
              title: 'Friends',
              actionLabel: 'Add friend',
              onAction: _addingFriend ? null : _addFriendFlow,
            ),
            if (_loading)
              const AppBalanceTile(
                title: 'Loading friends...',
                leadingIcon: Icons.person_outline,
              )
            else if (_error != null)
              AppBalanceTile(
                title: 'Failed to load friends',
                subtitle: Text(_error!),
                leadingIcon: Icons.error_outline,
              )
            else if (_friends.isEmpty)
              AppEmptyState(
                title: 'No friends yet',
                subtitle: 'Your friend balances will appear here.',
                actionLabel: 'Add your first friend',
                onAction: _addFriendFlow,
              )
            else
              ..._friends.map((friend) {
                final netByCurrency = Map<String, double>.from(
                  _friendSettlementNetByUid[friend.uid] ?? const {},
                )..removeWhere((currency, amount) => amount.abs() <= 0.005);
                final settled = netByCurrency.isEmpty;
                final allPositive = netByCurrency.values.every(
                  (amount) => amount > 0,
                );
                final allNegative = netByCurrency.values.every(
                  (amount) => amount < 0,
                );
                return _BalanceTile(
                  name: friend.label,
                  subtitle: settled
                      ? 'settled'
                      : allPositive
                      ? 'owes you'
                      : allNegative
                      ? 'you owe'
                      : 'mixed balances',
                  amountText: settled
                      ? null
                      : AppMoney.formatCurrencyAmounts(netByCurrency),
                  positive: !allNegative,
                  removing: _removingFriendUid == friend.uid,
                  onSettleUp: () => _settleUpFlow(friend),
                  onRemove: () => _removeFriendFlow(friend),
                );
              }),
          ],
        ),
        if (_addingFriend || _showFriendAddedSuccess)
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
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: _addingFriend
                          ? const Row(
                              key: ValueKey('adding_friend'),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Text('Adding friend...'),
                              ],
                            )
                          : Column(
                              key: const ValueKey('friend_added'),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.check_circle_rounded,
                                  size: 44,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Friend added',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                        decoration: TextDecoration.none,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ],
                            ),
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

class _BalanceTile extends StatelessWidget {
  const _BalanceTile({
    required this.name,
    required this.subtitle,
    required this.positive,
    this.amountText,
    this.removing = false,
    this.onSettleUp,
    this.onRemove,
  });

  final String name;
  final String subtitle;
  final String? amountText;
  final bool positive;
  final bool removing;
  final VoidCallback? onSettleUp;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final amountLabel = amountText == null
        ? Text(
            'settled',
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          )
        : AppMoneyLabel(text: amountText!, positive: positive);
    return AppCard(
      child: ListTile(
        onTap: removing ? null : onSettleUp,
        leading: const AppAvatar(icon: Icons.person_outline),
        title: Text(name),
        subtitle: Text(subtitle),
        trailing: removing
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  amountLabel,
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Settle up',
                    onPressed: onSettleUp,
                    icon: const Icon(Icons.payments_outlined),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Friend actions',
                    onSelected: (value) {
                      if (value == 'settle') onSettleUp?.call();
                      if (value == 'remove') onRemove?.call();
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'settle', child: Text('Settle up')),
                      PopupMenuItem(
                        value: 'remove',
                        child: Text('Remove friend'),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

class _SettleUpInput {
  const _SettleUpInput({
    required this.amount,
    required this.direction,
    required this.currency,
  });

  final double amount;
  final String direction;
  final String currency;
}
