import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class PlatformWidget extends StatelessWidget {
  const PlatformWidget({this.ios, this.android, this.web, super.key});

  final Widget? ios;
  final Widget? android;
  final Widget? web;

  @override
  Widget build(BuildContext context) {
    return resolvePlatformWidget(
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
      ios: ios,
      android: android,
      web: web,
    );
  }
}

Widget resolvePlatformWidget({
  required bool isWeb,
  required TargetPlatform platform,
  Widget? ios,
  Widget? android,
  Widget? web,
}) {
  if (isWeb) {
    return web ?? android ?? ios ?? const SizedBox.shrink();
  }

  switch (platform) {
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return ios ?? android ?? web ?? const SizedBox.shrink();
    case TargetPlatform.android:
    case TargetPlatform.fuchsia:
      return android ?? ios ?? web ?? const SizedBox.shrink();
    case TargetPlatform.linux:
    case TargetPlatform.windows:
      return web ?? android ?? ios ?? const SizedBox.shrink();
  }
}
