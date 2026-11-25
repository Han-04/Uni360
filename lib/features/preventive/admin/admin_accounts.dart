import 'package:flutter/material.dart';

import '../../../shared/account/presentation/profile_avatar.dart';
import 'admin_data.dart';
import 'admin_widgets.dart';

class AdminAccounts extends StatefulWidget {
  const AdminAccounts({
    super.key,
    required this.data,
    required this.superAdmin,
  });
  final AdminData data;
  final bool superAdmin;

  @override
  State<AdminAccounts> createState() => _AdminAccountsState();
}

class _AdminAccountsState extends State<AdminAccounts> {
  int page = 0;
  String search = '';
  String status = 'all';
  late Future<AdminRow> listing = load();
  String get role => widget.superAdmin ? 'Administrator' : 'Worker';
  AdminData get data => widget.data;

  Future<AdminRow> load() =>
      data.accounts('list', {'search': search, 'page': page, 'status': status});

  void reload() {
    final next = load();
    setState(() {
      listing = next;
    });
  }

  Future<void> edit([AdminRow? row]) async {
    final create = row == null;
    final saved = await adminForm(
      context,
      '${create ? "Create" : "Edit"} ${role.toLowerCase()}',
      {
        'name': row?['full_name'],
        'employeeId': row?['employee_id'],
        'phone': row?['phone'],
      },
      (values, _) => [
        adminText(
          values,
          'name',
          'Full name',
          required: true,
          min: 2,
          max: 120,
        ),
        adminText(values, 'employeeId', 'Employee ID', required: true, max: 40),
        adminText(values, 'phone', 'Phone (optional)', max: 21),
        if (create) ...[
          adminText(values, 'email', 'Email', required: true, max: 254),
          adminText(
            values,
            'password',
            'Temporary password',
            required: true,
            min: 12,
            max: 72,
            secret: true,
          ),
        ],
      ],
      (values) async {
        await data.accounts(create ? 'create' : 'edit', {
          'name': fieldText(values, 'name'),
          'employeeId': fieldText(values, 'employeeId'),
          'phone': fieldText(values, 'phone'),
          if (create) 'email': fieldText(values, 'email'),
          if (create) 'password': values['password'],
          if (!create) 'id': row['user_id'],
        });
      },
      action: create ? 'Create account' : 'Save changes',
    );
    if (saved && mounted) {
      if (create) {
        page = 0;
        search = '';
        status = 'all';
      }
      reload();
      adminMessage(context, create ? 'Account created.' : 'Account updated.');
    }
  }

  Future<void> _deactivateRecord(AdminRow row) async {
    final saved = await adminConfirm(
      context,
      'Deactivate account?',
      '${row['full_name']} will lose Uni360 access. Their account record will be kept.',
      'Deactivate account',
      () async {
        await data.accounts('deactivate', {'id': row['user_id']});
      },
    );
    if (saved && mounted) {
      page = 0;
      reload();
      adminMessage(context, 'Account deactivated.');
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AdminHeading(
        '$role accounts',
        subtitle: 'Create, update and deactivate ${role.toLowerCase()} access.',
        actions: [
          AdminCommandButton(
            onPressed: edit,
            icon: Icons.add,
            label: 'Create ${role.toLowerCase()}',
          ),
        ],
      ),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          AdminSearch(
            'Search by name or employee ID',
            (value) {
              search = value;
              page = 0;
              reload();
            },
            key: ValueKey(search),
            initial: search,
          ),
          SizedBox(
            width: 180,
            child: AdminFilterMenu(
              label: 'Status',
              value: status,
              options: const {
                'all': 'All statuses',
                'active': 'Active',
                'inactive': 'Inactive',
              },
              onChanged: (value) {
                if (value == status) return;
                status = value;
                page = 0;
                reload();
              },
            ),
          ),
        ],
      ),
      AdminLoad(
        listing,
        (result) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdminTable(
              ['Name', 'Employee ID', 'Phone', 'Status', 'Actions'],
              [
                for (final row in adminRows(result['rows']))
                  [
                    if (widget.superAdmin)
                      adminCell(row['full_name'])
                    else
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ExcludeSemantics(
                            child: ProfileAvatar(
                              name: row['full_name'] as String,
                              dimension: 36,
                              photoUrl: row['profile_photo_url'] as String?,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Flexible(child: adminCell(row['full_name'])),
                        ],
                      ),
                    adminCell(row['employee_id']),
                    adminCell(row['phone']),
                    AdminStatusBadge(active: row['is_active'] == true),
                    adminCommandRow([
                      AdminCommandButton.edit(onPressed: () => edit(row)),
                      if (row['is_active'] == true)
                        AdminCommandButton.deactivate(
                          icon: Icons.person_off_outlined,
                          onPressed: () => _deactivateRecord(row),
                        ),
                    ]),
                  ],
              ],
              empty: 'No matching accounts.',
              darkHeading: true,
            ),
            AdminPager(
              page: page,
              next: result['hasNext'] == true,
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
