import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Uses the device's full screen on phones and a portrait phone viewport on
/// larger displays. The navigator lives inside, so every route and dialog fits.
class PhoneViewport extends StatelessWidget {
  const PhoneViewport({super.key, required this.child, this.fullWidth = false});

  static const maxWidth = 430.0;
  static const maxPreviewHeight = 932.0;
  final Widget child;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = fullWidth
          ? constraints.maxWidth
          : math.min(constraints.maxWidth, maxWidth);
      final height = !fullWidth && constraints.maxWidth > maxWidth
          ? math.min(constraints.maxHeight, maxPreviewHeight)
          : constraints.maxHeight;
      return ColoredBox(
        color: AppColors.navy,
        child: Center(
          child: SizedBox(
            width: width,
            height: height,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(size: Size(width, height)),
              child: ClipRect(child: child),
            ),
          ),
        ),
      );
    },
  );
}
