import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminPortalView extends StatelessWidget {
  const AdminPortalView({super.key, this.correctiveBuilder});

  final Widget Function(SupabaseClient, String, VoidCallback)?
  correctiveBuilder;

  @override
  Widget build(BuildContext context) => const Center(
    child: Text('Open Uni360 in a desktop browser to manage accounts.'),
  );
}
