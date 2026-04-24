import 'package:expense_tracker/core/ui/app_avatar.dart';
import 'package:expense_tracker/core/ui/app_card.dart';
import 'package:flutter/material.dart';

class AppBalanceTile extends StatelessWidget {
  const AppBalanceTile({
    required this.title,
    this.subtitle,
    this.leadingIcon,
    this.leadingLabel,
    this.trailing,
    this.onTap,
    super.key,
  });

  final String title;
  final Widget? subtitle;
  final IconData? leadingIcon;
  final String? leadingLabel;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: ListTile(
        onTap: onTap,
        leading: AppAvatar(icon: leadingIcon, label: leadingLabel),
        title: Text(title),
        subtitle: subtitle,
        trailing: trailing,
      ),
    );
  }
}
