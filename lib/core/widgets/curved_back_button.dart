import 'package:flutter/material.dart';

class CurvedBackButton extends StatelessWidget {
  const CurvedBackButton({super.key, this.onPressed, this.tooltip});

  static const icon = Icon(Icons.reply_rounded);

  final VoidCallback? onPressed;
  final String? tooltip;

  static Widget? forRoute(BuildContext context) =>
      ModalRoute.of(context)?.impliesAppBarDismissal == true
      ? const CurvedBackButton()
      : null;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip ?? MaterialLocalizations.of(context).backButtonTooltip,
    onPressed: onPressed ?? () => Navigator.maybePop(context),
    icon: icon,
  );
}
