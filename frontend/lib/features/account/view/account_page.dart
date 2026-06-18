import 'package:expense_tracker/app/routes/app_routes.dart';
import 'package:expense_tracker/core/ui/app_ui.dart';
import 'package:expense_tracker/core/widgets/selectable_error_message.dart';
import 'package:expense_tracker/features/auth/cubit/auth_cubit.dart';
import 'package:expense_tracker/features/accounts/models/financial_account.dart';
import 'package:expense_tracker/features/accounts/repositories/api_accounts_repository.dart';
import 'package:expense_tracker/features/credit_cards/models/credit_card.dart';
import 'package:expense_tracker/features/credit_cards/repositories/api_credit_cards_repository.dart';
import 'package:expense_tracker/features/dashboard/bloc/dashboard_snapshot_cubit.dart';
import 'package:expense_tracker/features/profile/models/user_profile.dart';
import 'package:expense_tracker/features/profile/repositories/user_profile_repository.dart';
import 'package:expense_tracker/features/theme/view/theme_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;

class AccountPage extends StatelessWidget {
  const AccountPage({this.profileRepository, super.key});

  final UserProfileRepository? profileRepository;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DashboardSnapshotCubit, DashboardSnapshotState>(
      builder: (context, state) {
        if (state is DashboardSnapshotFailure) {
          return SelectableErrorMessage(state.message);
        }

        if (state is! DashboardSnapshotLoaded) {
          return const Center(child: CircularProgressIndicator());
        }

        final user = context.select((AuthCubit? cubit) => cubit?.state.user);
        if (user == null) {
          return const SelectableErrorMessage('No authenticated user found.');
        }
        final repo = profileRepository ?? UserProfileRepository();

        return StreamBuilder<UserProfile>(
          stream: repo.watchProfile(user),
          builder: (context, profileSnapshot) {
            final profile =
                profileSnapshot.data ??
                UserProfile(
                  uid: user.uid,
                  displayName: user.displayName,
                  email: user.email,
                  photoUrl: user.photoUrl,
                  defaultPaymentMethod: user.defaultPaymentMethod,
                );

            return AppPageContainer(
              children: [
                _ProfileCard(
                  profile: profile,
                  onEdit: () async {
                    await Navigator.of(
                      context,
                    ).pushNamed<void>(AppRoutes.accountEdit);
                  },
                ),
                const SizedBox(height: 16),
                const _SectionLabel('Preferences'),
                _DefaultPaymentMethodTile(
                  profile: profile,
                  profileRepository: repo,
                  accountsRepository: ApiAccountsRepository(
                    client: http.Client(),
                  ),
                  creditCardsRepository: ApiCreditCardsRepository(
                    client: http.Client(),
                  ),
                ),
                const SizedBox(height: 8),
                _SettingsTile(
                  title: 'Theme',
                  subtitle: 'Adjust colors and contrast for this device.',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ThemeSettingsPage(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                const _SectionLabel('Account'),
                _SettingsTile(
                  title: 'Sign out',
                  subtitle:
                      'Use a different account or finish on another device.',
                  onTap: context.read<AuthCubit?>() == null
                      ? null
                      : () => context.read<AuthCubit>().signOut(),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _DefaultPaymentMethodTile extends StatefulWidget {
  const _DefaultPaymentMethodTile({
    required this.profile,
    required this.profileRepository,
    required this.accountsRepository,
    required this.creditCardsRepository,
  });

  final UserProfile profile;
  final UserProfileRepository profileRepository;
  final ApiAccountsRepository accountsRepository;
  final ApiCreditCardsRepository creditCardsRepository;

  @override
  State<_DefaultPaymentMethodTile> createState() =>
      _DefaultPaymentMethodTileState();
}

class _DefaultPaymentMethodTileState extends State<_DefaultPaymentMethodTile> {
  static const _accountPrefix = 'account:';
  static const _cardPrefix = 'credit_card:';
  var _saving = false;
  String? _selected;
  List<FinancialAccount> _accounts = const [];
  List<CreditCardAccount> _cards = const [];

  String get _value => _selected ?? widget.profile.defaultPaymentMethod;

  @override
  void initState() {
    super.initState();
    _selected = widget.profile.defaultPaymentMethod;
    _loadSources();
  }

  @override
  void didUpdateWidget(covariant _DefaultPaymentMethodTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.defaultPaymentMethod !=
        widget.profile.defaultPaymentMethod) {
      _selected = widget.profile.defaultPaymentMethod;
    }
  }

  Future<void> _loadSources() async {
    try {
      final results = await Future.wait([
        widget.accountsRepository.fetchAccounts(),
        widget.creditCardsRepository.fetchCards(),
      ]);
      if (!mounted) return;
      setState(() {
        _accounts = results[0] as List<FinancialAccount>;
        _cards = results[1] as List<CreditCardAccount>;
      });
    } catch (_) {}
  }

  List<String> get _choices {
    final choices = <String>[
      'cash',
      'upi',
      'bank_transfer',
      ..._accounts
          .where((account) => !account.archived)
          .map((account) => '$_accountPrefix${account.id}'),
      ..._cards
          .where((card) => !card.archived)
          .map((card) => '$_cardPrefix${card.id}'),
    ];
    if (!choices.contains(_value)) choices.add(_value);
    return choices;
  }

  String _labelFor(String value) {
    if (value.startsWith(_accountPrefix)) {
      final id = value.substring(_accountPrefix.length);
      for (final account in _accounts) {
        if (account.id == id) {
          final bank = account.institution.trim();
          return bank.isEmpty ? account.name : '${account.name} - $bank';
        }
      }
      return 'Bank account';
    }
    if (value.startsWith(_cardPrefix)) {
      final id = value.substring(_cardPrefix.length);
      for (final card in _cards) {
        if (card.id == id) {
          final issuer = card.issuer.trim();
          return issuer.isEmpty ? card.name : '${card.name} - $issuer';
        }
      }
      return 'Credit card';
    }
    switch (value) {
      case 'cash':
        return 'Cash';
      case 'upi':
        return 'UPI';
      case 'bank_transfer':
        return 'Bank transfer';
      default:
        return value;
    }
  }

  Future<void> _choose() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text(
                'Default payment method',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            for (final choice in _choices)
              ListTile(
                title: Text(_labelFor(choice)),
                leading: Icon(
                  choice == _value
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                onTap: () => Navigator.of(context).pop(choice),
              ),
          ],
        ),
      ),
    );
    if (selected == null || selected == _value) return;
    if (!mounted) return;
    final user = context.read<AuthCubit?>()?.state.user;
    if (user == null) return;
    setState(() {
      _saving = true;
      _selected = selected;
    });
    try {
      await widget.profileRepository.updateDefaultPaymentMethod(
        user: user,
        paymentMethod: selected,
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsTile(
      title: 'Default payment',
      subtitle: _saving ? 'Saving...' : _labelFor(_value),
      onTap: _saving ? null : _choose,
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile, required this.onEdit});

  final UserProfile profile;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    const avatarSize = 44.0;
    return AppCard(
      child: ListTile(
        onTap: onEdit,
        leading: SizedBox(
          width: avatarSize,
          height: avatarSize,
          child: ClipOval(
            child: profile.photoUrl?.isNotEmpty == true
                ? Image.network(
                    profile.photoUrl!,
                    key: ValueKey(profile.photoUrl),
                    webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                    errorBuilder: (context, error, stackTrace) =>
                        _AccountAvatarFallback(),
                  )
                : const _AccountAvatarFallback(),
          ),
        ),
        title: Text(profile.displayName),
        subtitle: Text(profile.email),
        trailing: TextButton(onPressed: onEdit, child: const Text('Edit')),
      ),
    );
  }
}

class _AccountAvatarFallback extends StatelessWidget {
  const _AccountAvatarFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppMoney.positiveColor.withValues(alpha: 0.18),
      alignment: Alignment.center,
      child: const Icon(Icons.person),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({required this.title, this.subtitle, this.onTap});

  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: ListTile(
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: onTap == null ? null : const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}
