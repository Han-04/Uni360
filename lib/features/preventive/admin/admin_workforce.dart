import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/link.dart';
import 'package:uuid/uuid.dart';

import 'admin_availability.dart';
import 'admin_data.dart';
import 'admin_widgets.dart';

class AdminWorkforce extends StatefulWidget {
  const AdminWorkforce({super.key, required this.data});
  final AdminData data;

  @override
  State<AdminWorkforce> createState() => _AdminWorkforceState();
}

class _AdminWorkforceState extends State<AdminWorkforce> {
  AdminData get data => widget.data;
  int page = 0;
  String search = '';
  late var listing = data.workers();
  AdminRow? worker;

  void reload() {
    final next = data.workers(search, page);
    setState(() {
      listing = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (worker case final selected?) {
      return _WorkerProfile(
        data: data,
        worker: selected,
        back: () => setState(() {
          worker = null;
          listing = data.workers(search, page);
        }),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AdminHeading(
          'Workforce management',
          subtitle: 'Manage worker profiles, skills, certifications and date availability.',
        ),
        AdminSearch('Search by name or employee ID', (value) {
          search = value;
          page = 0;
          reload();
        }, initial: search),
        AdminLoad(
          listing,
          (rows) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AdminTable(
                ['Worker', 'Employee ID', 'Job role', 'Employment', 'Actions'],
                [
                  for (final row in rows.take(25))
                    [
                      adminCell(row['full_name']),
                      adminCell(row['employee_id']),
                      adminCell(row['job_role']),
                      adminCell(row['employment_status']),
                      adminAction(
                        'Open profile',
                        () => setState(() => worker = row),
                      ),
                    ],
                ],
                empty: 'No matching workers.',
              ),
              AdminPager(
                page: page,
                next: rows.length > 25,
                change: (number) {
                  page = number;
                  reload();
                },
              ),
            ],
          ),
          retry: reload,
        ),
      ],
    );
  }
}

class _WorkerProfile extends StatefulWidget {
  const _WorkerProfile({
    required this.data,
    required this.worker,
    required this.back,
  });
  final AdminData data;
  final AdminRow worker;
  final VoidCallback back;

  @override
  State<_WorkerProfile> createState() => _WorkerProfileState();
}

class _WorkerProfileState extends State<_WorkerProfile> {
  AdminData get data => widget.data;
  String get workerId => widget.worker['worker_id'] as String;
  late var details = load();

  Future<(AdminRow, List<AdminRow>, List<AdminRow>)> load() async {
    final (profile, skills, certificates) = await (
      data
          .table('worker_profile')
          .select(
            'worker_id,job_role,employment_status,current_workload,daily_work_limit_minutes',
          )
          .eq('worker_id', workerId)
          .single(),
      data
          .table('worker_skill')
          .select('worker_skill_id,skill(skill_name)')
          .eq('worker_id', workerId),
      data
          .table('worker_certification')
          .select(
            'certification_id,certification_name,certification_no,expiry_date,document_path',
          )
          .eq('worker_id', workerId)
          .order('certification_name', ascending: true)
          .order('certification_id'),
    ).wait;
    skills.sort(
      (a, b) => '${a['skill']?['skill_name']}'.compareTo(
        '${b['skill']?['skill_name']}',
      ),
    );
    return (profile, skills, certificates);
  }

  void reload() {
    final next = load();
    setState(() {
      details = next;
    });
  }

  Future<void> editProfile(AdminRow profile) async {
    final saved = await adminForm(
      context,
      'Edit worker profile',
      profile,
      (values, _) => [
        adminText(values, 'job_role', 'Job role', max: 120),
        adminText(
          values,
          'employment_status',
          'Employment status',
          required: true,
          max: 60,
        ),
        adminText(
          values,
          'current_workload',
          'Current workload',
          required: true,
          minimumNumber: 0,
          maximumNumber: 2147483647,
        ),
        adminText(
          values,
          'daily_work_limit_minutes',
          'Daily work limit (minutes)',
          required: true,
          minimumNumber: 1,
          maximumNumber: 1440,
        ),
      ],
      (values) async {
        await data.write(
          data
              .table('worker_profile')
              .update({
                'job_role': optionalField(values, 'job_role'),
                'employment_status': fieldText(values, 'employment_status'),
                'current_workload': int.parse(
                  fieldText(values, 'current_workload'),
                ),
                'daily_work_limit_minutes': int.parse(
                  fieldText(values, 'daily_work_limit_minutes'),
                ),
              })
              .eq('worker_id', workerId),
          'worker_id',
        );
      },
    );
    if (saved && mounted) {
      reload();
      adminMessage(context, 'Worker profile saved.');
    }
  }

  Future<void> addSkill() async {
    final saved = await adminForm(
      context,
      'Add skill',
      {},
      (values, _) => [
        adminText(values, 'name', 'Skill name', required: true, max: 120),
      ],
      (values) async {
        await data.client.rpc(
          'add_worker_skill',
          params: {
            'target_worker': workerId,
            'name': fieldText(values, 'name'),
          },
        );
      },
      action: 'Add skill',
    );
    if (saved && mounted) {
      reload();
      adminMessage(context, 'Skill added.');
    }
  }

  static const _mime = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'pdf': 'application/pdf',
  };
  static const _uuid = Uuid();
  StorageFileApi get documents =>
      data.client.storage.from('worker-certificates');

  Future<void> editCertificate([AdminRow? row]) async {
    final id = (row?['certification_id'] as String?) ?? _uuid.v4();
    final oldPath = row?['document_path'] as String?;
    final saved = await adminForm(
      context,
      row == null ? 'Add certification' : 'Edit certification',
      {...?row, 'expiry': DateTime.tryParse('${row?['expiry_date']}')},
      (values, refresh) => [
        adminText(
          values,
          'certification_name',
          'Certification name',
          required: true,
          max: 160,
        ),
        adminText(values, 'certification_no', 'Certificate ID', max: 120),
        adminDate(
          context,
          values,
          'expiry',
          'Expiry date',
          refresh,
          clearable: true,
        ),
        OutlinedButton.icon(
          onPressed: () async {
            try {
              final file = await openFile(
                acceptedTypeGroups: [
                  XTypeGroup(
                    label: 'Certificate files',
                    extensions: _mime.keys.toList(),
                    mimeTypes: _mime.values.toSet().toList(),
                  ),
                ],
              );
              if (file != null) {
                values['file'] = file;
                values.remove('file_error');
                refresh();
              }
            } catch (_) {
              values['file_error'] = 'Could not open the file picker.';
              refresh();
            }
          },
          icon: const Icon(Icons.upload_file),
          label: Text(
            values['file'] is XFile
                ? (values['file'] as XFile).name
                : oldPath == null
                ? 'Upload certificate'
                : 'Replace document',
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const Text('JPG, PNG, WebP or PDF, up to 10 MB.'),
        if (values['file_error'] case final String error) Text(error),
      ],
      (values) async {
        String? path = oldPath;
        if (values['file'] case final XFile file) {
          final ext = file.name.split('.').last.toLowerCase();
          final type = _mime[ext];
          final size = await file.length();
          if (type == null || size == 0 || size > 10485760) {
            throw const FormatException(
              'Choose a JPG, PNG, WebP or PDF file up to 10 MB.',
            );
          }
          path = '$workerId/$id/${_uuid.v4()}.${ext == "jpeg" ? "jpg" : ext}';
          await documents.uploadBinary(
            path,
            await file.readAsBytes(),
            fileOptions: FileOptions(contentType: type, cacheControl: '0'),
          );
        }
        final payload = {
          'certification_name': fieldText(values, 'certification_name'),
          'certification_no': optionalField(values, 'certification_no'),
          'expiry_date': values['expiry'] == null
              ? null
              : isoDate(values['expiry'] as DateTime),
          'document_path': path,
        };
        final table = data.table('worker_certification');
        try {
          await data.write(
            row == null
                ? table.insert({
                    ...payload,
                    'worker_id': workerId,
                    'certification_id': id,
                  })
                : table
                      .update(payload)
                      .eq('worker_id', workerId)
                      .eq('certification_id', id),
            'certification_id',
          );
        } on PostgrestException {
          if (path != null && path != oldPath) await removeDocument(path);
          rethrow;
        }
        if (oldPath != null && oldPath != path) await removeDocument(oldPath);
      },
    );
    if (saved && mounted) {
      reload();
      adminMessage(context, 'Certification saved.');
    }
  }

  Future<void> removeDocument(String path) async {
    try {
      await documents.remove([path]);
    } on StorageException {
      // A failed cleanup does not undo the saved certificate.
    }
  }

  void viewCertificate(AdminRow row) {
    final path = row['document_path'] as String;
    Future<String> getUrl() => documents.createSignedUrl(path, 300);
    var future = getUrl();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(row['certification_name'] as String),
        content: SizedBox(
          width: 520,
          child: StatefulBuilder(
            builder: (context, render) => AdminLoad(
              future,
              (url) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!path.toLowerCase().endsWith('.pdf'))
                    Flexible(
                      child: Image.network(
                        url,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) =>
                            const Text('Could not preview this certificate.'),
                      ),
                    ),
                  Link(
                    uri: Uri.parse(url),
                    target: LinkTarget.blank,
                    builder: (context, open) => TextButton.icon(
                      onPressed: open,
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Open document'),
                    ),
                  ),
                ],
              ),
              retry: () {
                final next = getUrl();
                render(() {
                  future = next;
                });
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      adminBackAction('All workers', widget.back),
      AdminHeading(
        widget.worker['full_name'] as String,
        subtitle: widget.worker['employee_id'] as String,
      ),
      AdminLoad(details, (result) {
        final (profile, skills, certificates) = result;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdminHeading(
              'Worker profile',
              actions: [
                OutlinedButton(
                  onPressed: () => editProfile(profile),
                  child: const Text('Edit profile'),
                ),
              ],
            ),
            AdminTable(
              ['Job role', 'Employment', 'Workload', 'Daily work limit'],
              [
                [
                  adminCell(profile['job_role']),
                  adminCell(profile['employment_status']),
                  adminCell(profile['current_workload']),
                  adminCell('${profile['daily_work_limit_minutes']} min'),
                ],
              ],
              empty: 'No profile record.',
            ),
            const SizedBox(height: 16),
            AdminHeading(
              'Skills',
              actions: [
                FilledButton(
                  onPressed: addSkill,
                  child: const Text('Add Skill'),
                ),
              ],
            ),
            if (skills.isEmpty) const Text('No skills added.'),
            Wrap(
              spacing: 8,
              children: [
                for (final row in skills)
                  if (row['skill']?['skill_name'] case final String name)
                    Chip(label: Text(name)),
              ],
            ),
            const SizedBox(height: 16),
            AdminHeading(
              'Certifications',
              actions: [
                FilledButton(
                  onPressed: editCertificate,
                  child: const Text('Add Certifications'),
                ),
              ],
            ),
            AdminTable(
              ['Name', 'Certificate ID', 'Expiry', 'Actions'],
              [
                for (final row in certificates)
                  [
                    adminCell(row['certification_name']),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        adminCell(row['certification_no']),
                        if (row['document_path'] != null)
                          IconButton(
                            onPressed: () => viewCertificate(row),
                            icon: const Icon(Icons.description_outlined),
                            tooltip: 'View certificate document',
                          ),
                      ],
                    ),
                    adminCell(row['expiry_date']),
                    adminAction(
                      'Edit certification',
                      () => editCertificate(row),
                    ),
                  ],
              ],
              empty: 'No certifications added.',
            ),
          ],
        );
      }, retry: reload),
      const SizedBox(height: 22),
      AdminAvailability(data: data, workerId: workerId),
    ],
  );
}
