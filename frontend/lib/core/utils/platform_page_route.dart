import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

Route<T> platformPageRoute<T>({
  required WidgetBuilder builder,
  RouteSettings? settings,
}) {
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS)) {
    return CupertinoPageRoute<T>(builder: builder, settings: settings);
  }

  return MaterialPageRoute<T>(builder: builder, settings: settings);
}
