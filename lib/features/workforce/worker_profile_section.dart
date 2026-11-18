import 'package:flutter/material.dart';

import '../../core/widgets/curved_back_button.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import 'worker_profile_repository.dart';

class WorkerProfileSection extends StatefulWidget {
  const WorkerProfileSection({
    super.key,
    required this.workerId,
    required this.load,
    required this.details,
  });

  final String workerId;
  final WorkerProfileLoader? load;
  final Widget Function(String jobRole) details;

  @override
  State<WorkerProfileSection> createState() => _WorkerProfileSectionState();
}

class _WorkerProfileSectionState extends State<WorkerProfileSection> {
  late Future<WorkerProfile?>? _profile = widget.load?.call(widget.workerId);

  @override
  void didUpdateWidget(WorkerProfileSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workerId != widget.workerId ||
        oldWidget.load != widget.load) {
      _profile = widget.load?.call(widget.workerId);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<WorkerProfile?>(
    future: _profile,
    builder: (context, snapshot) {
      final loading = snapshot.connectionState == ConnectionState.waiting;
      final profile = snapshot.data;
      final jobRole = loading
          ? 'Loading…'
          : snapshot.hasError
          ? 'Unavailable'
          : profile?.jobRole ?? 'Not assigned';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          widget.details(jobRole),
          const SizedBox(height: 14),
          SurfaceCard(
            padding: const EdgeInsets.all(6),
            child: Column(
              children: [
                for (final type in _CredentialType.values)
                  ListTile(
                    leading: Icon(type.icon, color: WorkerColors.blue),
                    title: Text(type.title),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(context, type),
                  ),
              ],
            ),
          ),
        ],
      );
    },
  );

  void _open(BuildContext context, _CredentialType type) {
    final theme = Theme.of(context);
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Theme(
          data: theme,
          child: StatefulBuilder(
            builder: (context, setPageState) => Scaffold(
              appBar: AppBar(
                leading: CurvedBackButton.forRoute(context),
                title: Text(type.title),
              ),
              body: SafeArea(
                child: FutureBuilder<WorkerProfile?>(
                  future: _profile,
                  builder: (context, snapshot) => switch ((
                    snapshot.connectionState,
                    snapshot.hasError,
                  )) {
                    (ConnectionState.waiting, _) => const Center(
                      child: CircularProgressIndicator(),
                    ),
                    (_, true) => Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Could not load your ${type.title.toLowerCase()}.',
                          ),
                          TextButton(
                            onPressed: () {
                              setState(
                                () => _profile = widget.load?.call(
                                  widget.workerId,
                                ),
                              );
                              setPageState(() {});
                            },
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    ),
                    _ => _CredentialList(type: type, profile: snapshot.data),
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _CredentialType {
  skills('Skills', Icons.build_outlined),
  certifications('Certifications', Icons.workspace_premium_outlined);

  const _CredentialType(this.title, this.icon);
  final String title;
  final IconData icon;
}

class _CredentialList extends StatelessWidget {
  const _CredentialList({required this.type, required this.profile});

  final _CredentialType type;
  final WorkerProfile? profile;

  @override
  Widget build(BuildContext context) {
    final skills = type == _CredentialType.skills;
    final rows = skills
        ? [
            for (final skill in profile?.skills ?? const <WorkerSkill>[])
              ListTile(leading: Icon(type.icon), title: Text(skill.name)),
          ]
        : [
            for (final certificate
                in profile?.certifications ?? const <WorkerCertification>[])
              ListTile(
                leading: Icon(type.icon),
                title: Text(certificate.name),
                subtitle: switch ((
                  certificate.number,
                  certificate.expiryDate,
                )) {
                  (null, null) => null,
                  (final number, final expiry) => Text(
                    [
                      if (number != null) 'Certificate ID · $number',
                      if (expiry != null) 'Expires · $expiry',
                    ].join('\n'),
                  ),
                },
              ),
          ];
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        if (rows.isEmpty)
          EmptyState(
            title: skills ? 'No skills yet' : 'No certifications yet',
            message:
                '${type.title} will appear here once your administrator adds them.',
            illustration: skills
                ? const ExcludeSemantics(child: _SkillsIllustration())
                : Image.asset(
                    'assets/workforce/no-certifications.png',
                    width: 100,
                    height: 100,
                    fit: BoxFit.contain,
                    excludeFromSemantics: true,
                  ),
          )
        else
          SurfaceCard(
            padding: const EdgeInsets.all(6),
            child: Column(children: rows),
          ),
      ],
    );
  }
}

class _SkillsIllustration extends StatelessWidget {
  const _SkillsIllustration();

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 100,
    child: Stack(
      alignment: Alignment.center,
      children: [
        const CircleAvatar(radius: 41, backgroundColor: WorkerColors.tint),
        const Icon(
          Icons.handyman_outlined,
          size: 44,
          color: WorkerColors.deepBlue,
        ),
        const Positioned(
          right: 8,
          top: 8,
          child: Icon(Icons.auto_awesome, size: 23, color: WorkerColors.blue),
        ),
      ],
    ),
  );
}
