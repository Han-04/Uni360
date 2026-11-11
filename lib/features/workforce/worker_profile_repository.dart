import 'package:supabase_flutter/supabase_flutter.dart';

typedef WorkerProfileLoader = Future<WorkerProfile?> Function(String workerId);

class WorkerProfile {
  const WorkerProfile({
    required this.jobRole,
    required this.zone,
    required this.standby,
    required this.workload,
    required this.employmentStatus,
    required this.skills,
    required this.shifts,
    this.certifications = const [],
  });

  final String? jobRole, zone;
  final bool standby;
  final int workload;
  final String employmentStatus;
  final List<WorkerSkill> skills;
  final List<WorkerCertification> certifications;
  final List<WorkerShift> shifts;
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
    required this.verified,
  });
  final String name;
  final String? number, expiryDate;
  final bool verified;
}

class WorkerShift {
  const WorkerShift({
    required this.availability,
    required this.start,
    required this.end,
    required this.status,
    required this.leaveStatus,
  });
  final String availability, status, leaveStatus;
  final DateTime start, end;
}

class WorkerProfileRepository {
  const WorkerProfileRepository(this._client);
  final SupabaseClient _client;

  Future<WorkerProfile?> load(String workerId) async {
    final row = await _client
        .from('worker_profile')
        .select('''
      job_role,assigned_zone,standby_status,current_workload,employment_status,
      worker_skill(skill(skill_name)),
      worker_certification(certification_name,certification_no,expiry_date,verified),
      worker_availability(availability,shift_start,shift_end,availability_status,leave_status)
      ''')
        .eq('worker_id', workerId)
        .order(
          'shift_start',
          referencedTable: 'worker_availability',
          ascending: false,
        )
        .maybeSingle();
    if (row == null) return null;
    return WorkerProfile(
      jobRole: row['job_role'] as String?,
      zone: row['assigned_zone'] as String?,
      standby: row['standby_status'] as bool,
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
          WorkerCertification(
            name: item['certification_name'] as String,
            number: item['certification_no'] as String?,
            expiryDate: item['expiry_date'] as String?,
            verified: item['verified'] as bool,
          ),
      ],
      shifts: [
        for (final item
            in (row['worker_availability'] as List)
                .cast<Map<String, dynamic>>())
          WorkerShift(
            availability: item['availability'] as String,
            start: DateTime.parse(item['shift_start'] as String).toLocal(),
            end: DateTime.parse(item['shift_end'] as String).toLocal(),
            status: item['availability_status'] as String,
            leaveStatus: item['leave_status'] as String,
          ),
      ],
    );
  }
}
