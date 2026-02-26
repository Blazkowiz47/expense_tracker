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
    final query = await _openAddFriendDialog();
    if (query == null || query.isEmpty) return;

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Friend added.')));
      await _loadFriends();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
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
    return Align(
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
              onAction: _addFriendFlow,
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
                  subtitle: friend.email.isNotEmpty ? friend.email : friend.uid,
                ),
              ),
          ],
        ),
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

class _ListSectionHeader extends StatelessWidget {
  const _ListSectionHeader({
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onAction;

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
  const _BalanceTile({required this.name, required this.subtitle});

  final String name;
  final String subtitle;

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
      ),
    );
  }
}
