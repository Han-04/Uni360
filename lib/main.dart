import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/uni360_app.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/phone_viewport.dart';
import 'features/preventive/data/assigned_work_repository.dart';
import 'features/workforce/worker_profile_repository.dart';
import 'shared/account/supabase_account_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  const url = String.fromEnvironment('SUPABASE_URL');
  const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  final projectUri = Uri.tryParse(url);
  if (projectUri == null ||
      projectUri.scheme != 'https' ||
      projectUri.host.isEmpty ||
      !publishableKey.startsWith('sb_publishable_')) {
    runApp(const _SetupRequired());
    return;
  }
  await Supabase.initialize(
    url: url,
    publishableKey: publishableKey,
    authOptions: const FlutterAuthClientOptions(
      localStorage: EmptyLocalStorage(),
      detectSessionInUri: false,
    ),
  );
  final client = Supabase.instance.client;
  final work = AssignedWorkRepository(client);
  runApp(
    Uni360App(
      accounts: SupabaseAccountRepository(client),
      loadWorkerProfile: WorkerProfileRepository(client).load,
      loadAssignedWork: work.load,
      workActions: work,
    ),
  );
}

class _SetupRequired extends StatelessWidget {
  const _SetupRequired();

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Uni360',
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    builder: (context, child) => PhoneViewport(child: child!),
    home: const Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Uni360 needs a Supabase project URL and publishable key. See the project setup guide.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    ),
  );
}
