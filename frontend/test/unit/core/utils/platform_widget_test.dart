import 'package:expense_tracker/core/utils/platform_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolvePlatformWidget', () {
    test('uses web widget on web when supplied', () {
      final widget = resolvePlatformWidget(
        isWeb: true,
        platform: TargetPlatform.android,
        ios: const Text('ios'),
        android: const Text('android'),
        web: const Text('web'),
      );

      expect(widget, isA<Text>());
      expect((widget as Text).data, 'web');
    });

    test('falls back to android then ios on web', () {
      final widget = resolvePlatformWidget(
        isWeb: true,
        platform: TargetPlatform.iOS,
        ios: const Text('ios'),
        android: const Text('android'),
      );

      expect(widget, isA<Text>());
      expect((widget as Text).data, 'android');
    });

    test('uses android then ios fallback on android', () {
      final widget = resolvePlatformWidget(
        isWeb: false,
        platform: TargetPlatform.android,
        ios: const Text('ios'),
      );

      expect(widget, isA<Text>());
      expect((widget as Text).data, 'ios');
    });

    test('uses ios then android fallback on ios', () {
      final widget = resolvePlatformWidget(
        isWeb: false,
        platform: TargetPlatform.iOS,
        android: const Text('android'),
      );

      expect(widget, isA<Text>());
      expect((widget as Text).data, 'android');
    });

    test('uses web fallback first on desktop targets', () {
      final widget = resolvePlatformWidget(
        isWeb: false,
        platform: TargetPlatform.windows,
        ios: const Text('ios'),
        android: const Text('android'),
        web: const Text('web'),
      );

      expect(widget, isA<Text>());
      expect((widget as Text).data, 'web');
    });
  });
}
