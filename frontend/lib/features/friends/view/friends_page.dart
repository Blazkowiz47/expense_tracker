import 'package:expense_tracker/features/friends/models/friend_contact.dart';
import 'package:expense_tracker/features/friends/repositories/api_friends_repository.dart';
import 'package:expense_tracker/features/friends/utils/settlement_balance_calculator.dart';
import 'package:expense_tracker/data/models/expense.dart';
import 'package:expense_tracker/data/models/expense_core.dart';
import 'package:expense_tracker/data/repositories/expenses_repository.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key});

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  late final http.Client _client;
  late final ApiFriendsRepository _repository;
  late final ExpenseRepository _expenseRepository;

  List<FriendContact> _friends = const [];
  Map<String, double> _friendSettlementNetByUid = const {};
  bool _loading = true;
  bool _addingFriend = false;
  bool _showFriendAddedSuccess = false;
  String? _removingFriendUid;
  String? _error;

  @override
  void initState() {
    super.initState();
    _client = http.Client();
    _repository = ApiFriendsRepository(client: _client);
    _expenseRepository = ExpenseRepository(client: _client);
    _loadFriends();
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    setState(() {
      _loading = true;
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
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<Map<String, double>> _loadSettlementBalances() async {
    await _expenseRepository.refresh();
    final expenses = _expenseRepository.getExpenses();
    return calculateFriendSettlementNetByUid(expenses);
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
      final title = input.direction == 'received'
          ? 'Settlement received'
          : 'Settlement paid';
      final description =
          'Settle up with ${friend.label} [uid:${friend.uid}][dir:${input.direction}]';
      await _expenseRepository.createExpense(
        Expense(
          core: ExpenseCore(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            title: title,
            amount: input.amount,
            currency: 'INR',
            category: 'Settlement',
            createdAt: DateTime.now(),
          ),
          description: description,
        ),
      );
      final settlementMap = await _loadSettlementBalances();
      if (!mounted) return;
      setState(() => _friendSettlementNetByUid = settlementMap);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Settlement of INR ${input.amount.toStringAsFixed(2)} recorded with ${friend.label}.',
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
                    prefixText: 'INR ',
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
                Navigator.of(
                  context,
                ).pop(_SettleUpInput(amount: amount, direction: direction));
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
            child: const Text('Find & add'),
          ),
        ],
      ),
    );
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
                  title: 'Friends',
                  amount: '${_friends.length}',
                  amountColor: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                _ListSectionHeader(
                  title: 'Friends',
                  actionLabel: 'Add friend',
                  onAction: _addingFriend ? null : _addFriendFlow,
                ),
                if (_loading)
                  const Card(child: ListTile(title: Text('Loading friends...')))
                else if (_error != null)
                  Card(
                    child: ListTile(
                      title: const Text('Failed to load friends'),
                      subtitle: Text(_error!),
                    ),
                  )
                else if (_friends.isEmpty)
                  _BalanceTile(
                    name: 'No friends yet',
                    subtitle: 'Add by email or phone number.',
                    balanceLabel: 'You are all settled up',
                    balanceColor: Theme.of(context).colorScheme.outline,
                  )
                else
                  ..._friends.map((friend) {
                    final net = _friendSettlementNetByUid[friend.uid] ?? 0;
                    final balanceLabel = net > 0.005
                        ? 'You are owed INR ${net.toStringAsFixed(2)}'
                        : net < -0.005
                        ? 'You owe INR ${(-net).toStringAsFixed(2)}'
                        : 'You are all settled up';
                    final balanceColor = net > 0.005
                        ? Theme.of(context).colorScheme.primary
                        : net < -0.005
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.outline;
                    return _BalanceTile(
                      name: friend.label,
                      subtitle: friend.contactHint.isNotEmpty
                          ? friend.contactHint
                          : 'No email/phone',
                      balanceLabel: balanceLabel,
                      balanceColor: balanceColor,
                      removing: _removingFriendUid == friend.uid,
                      onSettleUp: () => _settleUpFlow(friend),
                      onRemove: () => _removeFriendFlow(friend),
                    );
                  }),
              ],
            ),
          ),
        ),
        if (_addingFriend || _showFriendAddedSuccess)
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

class _ListSectionHeader extends StatelessWidget {
  const _ListSectionHeader({
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

class _BalanceTile extends StatelessWidget {
  const _BalanceTile({
    required this.name,
    required this.subtitle,
    required this.balanceLabel,
    required this.balanceColor,
    this.removing = false,
    this.onSettleUp,
    this.onRemove,
  });

  final String name;
  final String subtitle;
  final String balanceLabel;
  final Color balanceColor;
  final bool removing;
  final VoidCallback? onSettleUp;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest,
          child: const Icon(Icons.person_outline),
        ),
        title: Text(name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(subtitle),
            const SizedBox(height: 2),
            Text(
              balanceLabel,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: balanceColor),
            ),
          ],
        ),
        trailing: removing
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Settle up',
                    onPressed: onSettleUp,
                    icon: const Icon(Icons.handshake_outlined),
                  ),
                  IconButton(
                    tooltip: 'Remove friend',
                    onPressed: onRemove,
                    icon: const Icon(Icons.person_remove_outlined),
                  ),
                ],
              ),
      ),
    );
  }
}

class _SettleUpInput {
  const _SettleUpInput({required this.amount, required this.direction});

  final double amount;
  final String direction;
}
