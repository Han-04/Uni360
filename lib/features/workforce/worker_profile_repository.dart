import 'package:supabase_flutter/supabase_flutter.dart';

typedef WorkerProfileLoader = Future<WorkerProfile?> Function(String workerId);

class WorkerProfile {
  const WorkerProfile({
    required this.jobRole,
    required this.workload,
    required this.employmentStatus,
    required this.skills,
    this.certifications = const [],
  });

  final String? jobRole;
  final int workload;
  final String employmentStatus;
  final List<WorkerSkill> skills;
  final List<WorkerCertification> certifications;
}

class WorkerSkill {
  const WorkerSkill({required this.name});
  final String name;
}

class WorkerCertification {
  const WorkerCertification({
    required this.name,
    required this.number,
    required this.expiryDate,
    this.loadDocumentUrl,
  });
  final String name;
  final String? number, expiryDate;
  final Future<String> Function()? loadDocumentUrl;
}

class WorkerProfileRepository {
  const WorkerProfileRepository(this._client);
  final SupabaseClient _client;

  Future<WorkerProfile?> load(String workerId) async {
    final row = await _client
        .schema('maintenance_api')
        .from('worker_profile')
        .select('''
      job_role,current_workload,employment_status,
      worker_skill(skill(skill_name)),
      worker_certification(certification_name,certification_no,expiry_date,document_path)
      ''')
        .eq('worker_id', workerId)
        .maybeSingle();
    if (row == null) return null;
    return WorkerProfile(
      jobRole: row['job_role'] as String?,
      workload: row['current_workload'] as int,
      employmentStatus: row['employment_status'] as String,
      skills: [
        for (final item
            in (row['worker_skill'] as List).cast<Map<String, dynamic>>())
          WorkerSkill(name: item['skill']['skill_name'] as String),
      ],
      certifications: [
        for (final item
            in (row['worker_certification'] as List)
                .cast<Map<String, dynamic>>())
          _certification(item),
      ],
    );
  }

  WorkerCertification _certification(Map<String, dynamic> row) {
    final path = row['document_path'] as String?;
    return WorkerCertification(
      name: row['certification_name'] as String,
      number: row['certification_no'] as String?,
      expiryDate: row['expiry_date'] as String?,
      loadDocumentUrl: path == null
          ? null
          : () => _client.storage
                .from('worker-certificates')
                .createSignedUrl(path, 300),
    );
  }
}
