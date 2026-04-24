import 'package:expense_tracker/data/models/group.dart';
import 'package:expense_tracker/features/groups/repositories/api_groups_repository.dart';
import 'package:expense_tracker/features/groups/view/groups_page.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class FamilyPage extends StatelessWidget {
  const FamilyPage({this.repository, this.client, super.key});

  final ApiGroupsRepository? repository;
  final http.Client? client;

  @override
  Widget build(BuildContext context) {
    return GroupsPage(
      groupType: GroupType.family,
      repository: repository,
      client: client,
    );
  }
}
