import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class SmartText extends StatelessWidget {
  const SmartText(
    this.data, {
    this.selectableOnWeb = true,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.softWrap,
    super.key,
  });

  final String data;
  final bool selectableOnWeb;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb && selectableOnWeb) {
      return SelectableText(
        data,
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
      );
    }

    return Text(
      data,
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      softWrap: softWrap,
    );
  }
}
