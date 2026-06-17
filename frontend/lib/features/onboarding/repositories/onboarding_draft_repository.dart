import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

const onboardingSetupDraftBoxName = 'monthly_setup_draft_v1';
const onboardingAccountDraftsKey = 'accountDrafts';

class OnboardingDraftRepository {
  Future<bool> hasSetupDraft() async {
    final box = await _openDraftBox();
    final raw = box?.get(onboardingAccountDraftsKey);
    if (raw == null || raw.trim().isEmpty) {
      return false;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return false;
      return decoded.whereType<Map>().any(_hasContent);
    } catch (_) {
      return true;
    }
  }

  Future<void> clearAccountDraft() async {
    final box = await _openDraftBox();
    await box?.delete(onboardingAccountDraftsKey);
  }

  Future<Box<String>?> _openDraftBox() async {
    try {
      if (!Hive.isBoxOpen(onboardingSetupDraftBoxName)) {
        if (!kIsWeb) return null;
        await Hive.openBox<String>(onboardingSetupDraftBoxName);
      }
      return Hive.box<String>(onboardingSetupDraftBoxName);
    } catch (_) {
      return null;
    }
  }

  bool _hasContent(Map<dynamic, dynamic> item) {
    for (final key in const ['existingId', 'name', 'institution', 'balance']) {
      if ((item[key]?.toString().trim().isNotEmpty ?? false)) {
        return true;
      }
    }
    return false;
  }
}
