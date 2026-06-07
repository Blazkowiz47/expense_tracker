import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web manifest has installable PWA metadata', () {
    final manifest =
        jsonDecode(File('web/manifest.json').readAsStringSync())
            as Map<String, dynamic>;

    expect(manifest['name'], 'Expense Tracker');
    expect(manifest['short_name'], isNotEmpty);
    expect(manifest['display'], 'standalone');
    expect(manifest['start_url'], isNotEmpty);
    expect(manifest['scope'], isNotEmpty);
    expect(manifest['prefer_related_applications'], isFalse);

    final icons = manifest['icons'] as List<dynamic>;
    expect(
      icons.any(
        (icon) =>
            icon is Map<String, dynamic> &&
            icon['sizes'] == '192x192' &&
            (icon['purpose'] == null || '${icon['purpose']}'.contains('any')),
      ),
      isTrue,
    );
    expect(
      icons.any(
        (icon) =>
            icon is Map<String, dynamic> &&
            icon['sizes'] == '512x512' &&
            '${icon['purpose']}'.contains('maskable'),
      ),
      isTrue,
    );
  });

  test('web index includes iOS add-to-home metadata', () {
    final index = File('web/index.html').readAsStringSync();

    expect(index, contains('apple-mobile-web-app-capable'));
    expect(index, contains('mobile-web-app-capable'));
    expect(index, contains('apple-mobile-web-app-title'));
    expect(index, contains('apple-touch-icon'));
    expect(index, contains('manifest.json'));
  });

  test(
    'native platform config supports release networking and image picking',
    () {
      final androidManifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final iosInfoPlist = File('ios/Runner/Info.plist').readAsStringSync();

      expect(
        androidManifest,
        contains('android.permission.INTERNET'),
        reason: 'Release Android builds need network access for backend APIs.',
      );
      expect(androidManifest, contains('android:label="Expense Tracker"'));
      expect(iosInfoPlist, contains('<string>Expense Tracker</string>'));
      expect(iosInfoPlist, contains('NSCameraUsageDescription'));
      expect(iosInfoPlist, contains('NSPhotoLibraryUsageDescription'));
    },
  );
}
