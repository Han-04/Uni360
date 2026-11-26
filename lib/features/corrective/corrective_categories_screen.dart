import 'package:flutter/material.dart';

import '../preventive/admin/admin_widgets.dart';
import 'corrective_repository.dart';
import 'corrective_widgets.dart';

class CorrectiveCategoriesScreen extends StatefulWidget {
  const CorrectiveCategoriesScreen(
    this.repository, {
    super.key,
    required this.onConfigureSite,
  });
  final CorrectiveRepository repository;
  final VoidCallback onConfigureSite;

  @override
  State<CorrectiveCategoriesScreen> createState() =>
      _CorrectiveCategoriesScreenState();
}

class _CorrectiveCategoriesScreenState
    extends State<CorrectiveCategoriesScreen> {
  late Future<List<CorrectiveRow>> _categories = widget.repository.categories();
  bool _saving = false;
  String? _error;

  void _refresh() => setState(() {
    _categories = widget.repository.categories();
  });

  Future<void> _edit(CorrectiveRow? existing) async {
    var name = existing?['name'] as String? ?? '';
    var team = existing?['team'] as String? ?? '';
    var role = existing?['worker_role'] as String? ?? '';
    var active = existing?['active'] as bool? ?? true;
    final form = GlobalKey<FormState>();
    final settings = await showDialog<CorrectiveRow>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(existing == null ? 'Add a maintenance category' : name),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (existing == null) ...[
                      TextFormField(
                        maxLength: 60,
                        decoration: const InputDecoration(
                          labelText: 'Category name',
                        ),
                        onChanged: (value) => name = value.trim(),
                        validator: (value) => (value?.trim().length ?? 0) < 2
                            ? 'Enter a category name.'
                            : null,
                      ),
                      correctiveGap(),
                    ],
                    TextFormField(
                      initialValue: team,
                      maxLength: 80,
                      decoration: const InputDecoration(
                        labelText: 'Routing team',
                      ),
                      onChanged: (value) => team = value.trim(),
                      validator: (value) => (value?.trim().length ?? 0) < 2
                          ? 'Enter the routing team.'
                          : null,
                    ),
                    correctiveGap(),
                    TextFormField(
                      initialValue: role,
                      maxLength: 80,
                      decoration: const InputDecoration(
                        labelText: 'Workforce role (optional)',
                      ),
                      onChanged: (value) => role = value.trim(),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: active,
                      title: const Text('Available for new reports'),
                      onChanged: (value) => update(() => active = value),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) {
                  Navigator.pop(context, {
                    'team': team,
                    'worker_role': role.isEmpty ? null : role,
                    'active': active,
                  });
                }
              },
              child: const Text('Save category'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || settings == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.saveCategory(
        name,
        settings,
        creating: existing == null,
      );
      if (mounted) _refresh();
    } on Exception catch (error) {
      if (mounted) setState(() => _error = correctiveError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1080),
      child: FutureBuilder(
        future: _categories,
        builder: (context, snapshot) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const AdminHeading('Corrective settings'),
            CorrectivePanel(
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.qr_code_2),
                title: const Text('Facility check-in settings'),
                subtitle: const Text(
                  'Set where workers check in and create the facility QR code.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: widget.onConfigureSite,
              ),
            ),
            correctiveGap(20),
            AdminHeading(
              'Maintenance categories',
              actions: [
                FilledButton.icon(
                  onPressed: _saving ? null : () => _edit(null),
                  icon: const Icon(Icons.add),
                  label: const Text('Add category'),
                ),
              ],
            ),
            if (_error case final error?) CorrectiveMessage(error),
            if (snapshot.hasError)
              CorrectiveMessage(
                correctiveError(snapshot.error!),
                onRetry: _refresh,
              )
            else if (!snapshot.hasData)
              const LinearProgressIndicator()
            else
              for (final category in snapshot.data!) ...[
                CorrectivePanel(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    onTap: _saving ? null : () => _edit(category),
                    title: Text(category['name'] as String),
                    subtitle: Text(
                      '${category['team']} · ${category['worker_role'] ?? 'Role selected at dispatch'}',
                    ),
                    trailing: Text(
                      category['active'] == true ? 'Active' : 'Inactive',
                    ),
                  ),
                ),
                correctiveGap(8),
              ],
          ],
        ),
      ),
    ),
  );
}
