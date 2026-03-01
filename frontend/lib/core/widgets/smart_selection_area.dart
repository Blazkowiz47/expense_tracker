import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class SmartSelectionArea extends StatelessWidget {
  const SmartSelectionArea({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return child;
    }
    return SelectionArea(child: child);
  }
}
