import 'package:flutter/material.dart';

const adminPortalRoute = '/admin';

class AdminPortalButton extends StatelessWidget {
  const AdminPortalButton({super.key});

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    icon: const Icon(Icons.desktop_windows_outlined),
    label: const Text('Admin login'),
    onPressed: () => Navigator.of(context).pushNamed(adminPortalRoute),
  );
}
