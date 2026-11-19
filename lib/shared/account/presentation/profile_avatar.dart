import 'dart:typed_data';

import 'package:flutter/material.dart';

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.name,
    required this.dimension,
    this.photoUrl,
    this.preview,
  });

  final String name;
  final double dimension;
  final String? photoUrl;
  final Uint8List? preview;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part.characters.first)
        .join()
        .toUpperCase();
    final fallback = Center(
      child: Text(
        initials,
        style: TextStyle(
          color: colors.onPrimary,
          fontSize: dimension * .35,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    return ClipOval(
      child: ColoredBox(
        color: colors.primary,
        child: SizedBox.square(
          dimension: dimension,
          child: switch ((preview, photoUrl)) {
            (final bytes?, _) => Image.memory(
              bytes,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
            ),
            (_, final url?) => Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
            ),
            _ => fallback,
          },
        ),
      ),
    );
  }
}
