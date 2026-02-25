import 'package:flutter/material.dart';

class FamilyPage extends StatelessWidget {
  const FamilyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            Card(
              child: ListTile(
                title: Text('Family'),
                subtitle: Text(
                  'Family-specific balances and shared expenses will appear here.',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
