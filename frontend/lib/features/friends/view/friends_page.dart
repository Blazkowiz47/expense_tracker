import 'package:expense_tracker/features/friends/models/friend_contact.dart';
import 'package:expense_tracker/features/friends/repositories/api_friends_repository.dart';
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

  List<FriendContact> _friends = const [];
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
      if (!mounted) return;
      setState(() => _friends = friends);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
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
                  const _BalanceTile(
                    name: 'No friends yet',
                    subtitle: 'Add by email or phone number.',
                  )
                else
                  ..._friends.map(
                    (friend) => _BalanceTile(
                      name: friend.label,
                      subtitle: friend.contactHint.isNotEmpty
                          ? friend.contactHint
                          : 'No email/phone',
                      removing: _removingFriendUid == friend.uid,
                      onRemove: () => _removeFriendFlow(friend),
                    ),
                  ),
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
    this.removing = false,
    this.onRemove,
  });

  final String name;
  final String subtitle;
  final bool removing;
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
        subtitle: Text(subtitle),
        trailing: removing
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              )
            : IconButton(
                tooltip: 'Remove friend',
                onPressed: onRemove,
                icon: const Icon(Icons.person_remove_outlined),
              ),
      ),
    );
  }
}
