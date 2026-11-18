import 'package:flutter/material.dart';
import 'package:url_launcher/link.dart';

import 'worker_leave_repository.dart';

class LeaveDocumentButton extends StatelessWidget {
  const LeaveDocumentButton({
    super.key,
    required this.leave,
    required this.repository,
  });

  final WorkerLeave leave;
  final WorkerLeaveRepository repository;

  @override
  Widget build(BuildContext context) {
    final path = leave.documentPath;
    final name = leave.documentName;
    if (path == null || name == null) return const SizedBox.shrink();
    return TextButton.icon(
      icon: const Icon(Icons.description_outlined),
      label: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      onPressed: () {
        final url = repository.documentUrl(path);
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Supporting document'),
            content: FutureBuilder<String>(
              future: url,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Text('Could not open the document. Try again.');
                }
                final link = snapshot.data;
                if (link == null) return const LinearProgressIndicator();
                return Link(
                  uri: Uri.parse(link),
                  target: LinkTarget.blank,
                  builder: (context, open) => TextButton.icon(
                    onPressed: open,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Open supporting document'),
                  ),
                );
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      },
    );
  }
}
