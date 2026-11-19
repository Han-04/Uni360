import 'package:flutter/material.dart';

import '../../../core/widgets/curved_back_button.dart';

import '../../../core/theme/app_theme.dart';
import 'admin_data.dart';

export 'admin_filter_menu.dart';

const _tableCardElevation = 5.0;
const _tableCardShadow = Color(0x52172940);

class AdminHeading extends StatelessWidget {
  const AdminHeading(
    this.title, {
    super.key,
    this.subtitle,
    this.actions = const [],
  });
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 24,
      runSpacing: 12,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (subtitle case final text?)
              Text(text, style: const TextStyle(color: AppColors.muted)),
          ],
        ),
        if (actions.isNotEmpty)
          Wrap(spacing: 8, runSpacing: 8, children: actions),
      ],
    ),
  );
}

class AdminLoad<T> extends StatelessWidget {
  const AdminLoad(this.future, this.builder, {super.key, required this.retry});

  final Future<T> future;
  final Widget Function(T) builder;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const LinearProgressIndicator();
      }
      if (snapshot.hasError) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              adminError(snapshot.error!),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            TextButton(onPressed: retry, child: const Text('Retry')),
          ],
        );
      }
      return builder(snapshot.data as T);
    },
  );
}

class AdminTable extends StatelessWidget {
  const AdminTable(
    this.headers,
    this.rows, {
    super.key,
    required this.empty,
    this.framed = true,
    this.darkHeading = false,
    this.emptyState,
  });
  final List<String> headers;
  final List<List<Widget>> rows;
  final String empty;
  final bool framed;
  final bool darkHeading;
  final Widget? emptyState;

  @override
  Widget build(BuildContext context) {
    final table = LayoutBuilder(
      builder: (context, size) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: size.maxWidth),
            child: DataTable(
              headingRowColor: WidgetStatePropertyAll(
                darkHeading ? Colors.black : AppColors.background,
              ),
              headingTextStyle: darkHeading
                  ? Theme.of(context).textTheme.titleSmall
                        ?.copyWith(color: Colors.white)
                  : null,
              dataRowMinHeight: 56,
              dataRowMaxHeight: 78,
              columns: [
                for (final name in headers) DataColumn(label: Text(name)),
              ],
              rows: [
                if (rows.isEmpty && emptyState == null)
                  DataRow(
                    cells: [
                      DataCell(Text(empty)),
                      for (var i = 1; i < headers.length; i++) DataCell.empty,
                    ],
                  )
                else
                  for (final row in rows)
                    DataRow(cells: row.map(DataCell.new).toList()),
              ],
            ),
          ),
        );
      },
    );
    final content = rows.isEmpty && emptyState != null
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [table, emptyState!],
          )
        : table;
    return framed
        ? Card(
            color: Colors.white,
            margin: const EdgeInsets.symmetric(vertical: 8),
            elevation: darkHeading ? _tableCardElevation : null,
            shadowColor: darkHeading ? _tableCardShadow : null,
            clipBehavior: Clip.antiAlias,
            child: content,
          )
        : content;
  }
}

class AdminSectionCard extends StatelessWidget {
  const AdminSectionCard(
    this.title, {
    super.key,
    this.subtitle,
    this.actions = const [],
    required this.child,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AdminHeading(title, subtitle: subtitle, actions: actions),
      Card(
        color: Colors.white,
        margin: EdgeInsets.zero,
        elevation: _tableCardElevation,
        shadowColor: _tableCardShadow,
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    ],
  );
}

class AdminIllustratedEmptyState extends StatelessWidget {
  const AdminIllustratedEmptyState(
    this.message, {
    super.key,
    required this.asset,
  });

  final String message;
  final String asset;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      children: [
        Image.asset(
          asset,
          width: 160,
          height: 104,
          fit: BoxFit.contain,
          excludeFromSemantics: true,
        ),
        const SizedBox(height: 8),
        Text(message, style: Theme.of(context).textTheme.titleSmall),
      ],
    ),
  );
}

Widget adminCell(Object? value) => ConstrainedBox(
  constraints: const BoxConstraints(maxWidth: 300),
  child: Text(
    value == null || value == '' ? '—' : '$value',
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
  ),
);

Widget adminActions(List<Widget> children) =>
    Wrap(spacing: 2, runSpacing: 2, children: children);

Widget adminAction(String label, VoidCallback onTap) =>
    TextButton(onPressed: onTap, child: Text(label));

class AdminCommandButton extends StatelessWidget {
  const AdminCommandButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  static final _style =
      FilledButton.styleFrom(
        overlayColor: Colors.black,
        side: const BorderSide(color: Colors.black26),
      ).copyWith(
        backgroundColor: WidgetStateProperty.fromMap({
          WidgetState.disabled: const Color(0xFFF0F0F0),
          WidgetState.hovered: Colors.black,
          WidgetState.any: Colors.white,
        }),
        foregroundColor: WidgetStateProperty.fromMap({
          WidgetState.disabled: const Color(0xFF666666),
          WidgetState.hovered: Colors.white,
          WidgetState.any: Colors.black,
        }),
      );

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: onPressed,
    style: _style,
    icon: icon == null ? null : Icon(icon),
    label: Text(label),
  );
}

Widget adminBackAction(String label, VoidCallback onTap) => TextButton.icon(
  onPressed: onTap,
  icon: CurvedBackButton.icon,
  label: Text(label),
);

class AdminPager extends StatelessWidget {
  const AdminPager({
    super.key,
    required this.page,
    required this.next,
    required this.change,
  });
  final int page;
  final bool next;
  final ValueChanged<int> change;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text('Page ${page + 1}'),
      TextButton(
        onPressed: page > 0 ? () => change(page - 1) : null,
        child: const Text('Previous'),
      ),
      TextButton(
        onPressed: next ? () => change(page + 1) : null,
        child: const Text('Next'),
      ),
    ],
  );
}

class AdminSearch extends StatefulWidget {
  const AdminSearch(this.label, this.onSearch, {super.key, this.initial = ''});
  final String label, initial;
  final ValueChanged<String> onSearch;

  @override
  State<AdminSearch> createState() => _AdminSearchState();
}

class _AdminSearchState extends State<AdminSearch> {
  late final controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      SizedBox(
        width: 310,
        child: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: widget.label,
            prefixIcon: const Icon(Icons.search),
          ),
          onSubmitted: (value) => widget.onSearch(value.trim()),
        ),
      ),
      AdminCommandButton(
        label: 'Search',
        onPressed: () => widget.onSearch(controller.text.trim()),
      ),
    ],
  );
}

typedef AdminFormBody = List<Widget> Function(
  AdminRow values,
  VoidCallback refresh,
);

Future<bool> adminForm(
  BuildContext context,
  String title,
  AdminRow initial,
  AdminFormBody fields,
  Future<void> Function(AdminRow values) save, {
  String action = 'Save changes',
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AdminForm(title, action, initial, fields, save),
    ) ??
    false;

class _AdminForm extends StatefulWidget {
  const _AdminForm(
    this.title,
    this.action,
    this.initial,
    this.fields,
    this.save,
  );
  final String title, action;
  final AdminRow initial;
  final AdminFormBody fields;
  final Future<void> Function(AdminRow) save;

  @override
  State<_AdminForm> createState() => _AdminFormState();
}

class _AdminFormState extends State<_AdminForm> {
  final _form = GlobalKey<FormState>();
  late final values = {...widget.initial};
  bool busy = false;
  String? error;

  Future<void> submit() async {
    if (busy || !_form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.save(values);
      if (mounted) Navigator.pop(context, true);
    } catch (failure) {
      if (mounted) {
        setState(() {
          busy = false;
          error = adminError(failure);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                IgnorePointer(
                  ignoring: busy,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: widget.fields(values, () {
                      if (mounted) setState(() {});
                    }),
                  ),
                ),
                if (busy) const LinearProgressIndicator(),
                if (error case final message?)
                  Text(
                    message,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: busy ? null : submit,
          child: Text(widget.action),
        ),
      ],
    ),
  );
}

Widget adminText(
  AdminRow values,
  String key,
  String label, {
  bool required = false,
  bool secret = false,
  int? max,
  int min = 1,
  int lines = 1,
  int? minimumNumber,
  int? maximumNumber,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 12),
  child: TextFormField(
    key: ValueKey(key),
    initialValue: values[key]?.toString() ?? '',
    decoration: InputDecoration(labelText: label),
    maxLines: lines,
    obscureText: secret,
    keyboardType: minimumNumber != null ? TextInputType.number : null,
    onChanged: (value) => values[key] = value,
    validator: (value) {
      final text = secret ? value ?? '' : (value ?? '').trim();
      if (!required && text.isEmpty) return null;
      if (text.length < min) {
        return min == 1 ? 'Enter $label.' : 'Enter at least $min characters.';
      }
      if (max != null && text.length > max) {
        return 'Use at most $max characters.';
      }
      if (minimumNumber != null) {
        final number = int.tryParse(text);
        if (number == null ||
            number < minimumNumber ||
            number > maximumNumber!) {
          return 'Enter a whole number from $minimumNumber to $maximumNumber.';
        }
      }
      return null;
    },
  ),
);

Widget adminSelect(
  AdminRow values,
  String key,
  String label,
  Map<String, String> choices,
  VoidCallback refresh, {
  bool required = false,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 12),
  child: DropdownButtonFormField<String>(
    key: ValueKey(key),
    initialValue: choices.containsKey(values[key])
        ? values[key] as String
        : null,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final item in choices.entries)
        DropdownMenuItem(
          value: item.key,
          child: Text(item.value, overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: (value) {
      values[key] = value;
      refresh();
    },
    validator: (value) =>
        required && (value == null || value.isEmpty) ? 'Choose $label.' : null,
  ),
);

Widget adminCheck(
  AdminRow values,
  String key,
  String label,
  VoidCallback refresh,
) => CheckboxListTile(
  contentPadding: EdgeInsets.zero,
  controlAffinity: ListTileControlAffinity.leading,
  value: values[key] == true,
  title: Text(label),
  onChanged: (value) {
    values[key] = value;
    refresh();
  },
);

Future<DateTime?> pickAdminDate(BuildContext context, DateTime date) =>
    showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );

Widget adminDate(
  BuildContext context,
  AdminRow values,
  String key,
  String label,
  VoidCallback refresh, {
  bool clearable = false,
}) {
  final date = values[key] as DateTime?;
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Wrap(
      spacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: () async {
            final picked = await pickAdminDate(context, date ?? adminToday());
            if (picked != null) {
              values[key] = DateTime.utc(picked.year, picked.month, picked.day);
              refresh();
            }
          },
          icon: const Icon(Icons.event_outlined),
          label: Text(
            '$label · ${date == null ? "Choose date" : isoDate(date)}',
          ),
        ),
        if (clearable && date != null)
          TextButton(
            onPressed: () {
              values[key] = null;
              refresh();
            },
            child: const Text('Clear'),
          ),
      ],
    ),
  );
}

String fieldText(AdminRow values, String key) =>
    (values[key]?.toString() ?? '').trim();

String? optionalField(AdminRow values, String key) {
  final text = fieldText(values, key);
  return text.isEmpty ? null : text;
}

Future<bool> adminConfirm(
  BuildContext context,
  String title,
  String description,
  String action,
  Future<void> Function() save,
) => adminForm(
  context,
  title,
  {},
  (_, _) => [Text(description)],
  (_) => save(),
  action: action,
);

void adminMessage(BuildContext context, String message) {
  final wide = MediaQuery.sizeOf(context).width >= 820;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      width: wide ? 420 : null,
    ),
  );
}

Future<void> adminDetails(
  BuildContext context,
  String title,
  List<Widget> body,
) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(title),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: body,
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
