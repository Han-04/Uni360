import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

class AdminPortalView extends StatelessWidget {
  const AdminPortalView({super.key});

  @override
  Widget build(BuildContext context) => HtmlElementView.fromTagName(
    tagName: 'iframe',
    onElementCreated: (element) {
      final frame = element as web.HTMLIFrameElement;
      final origin = web.window.location.origin;
      frame
        ..title = 'Uni360 Administration'
        ..src = Uri.parse(web.document.baseURI)
            .resolve('admin/index.html')
            .toString()
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%';
      frame.addEventListener(
        'load',
        ((web.Event _) {
          frame.contentWindow?.postMessage(
            {
              'type': 'uni360-admin-config',
              'url': const String.fromEnvironment('SUPABASE_URL'),
              'key': const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
            }.jsify(),
            origin.toJS,
          );
        }).toJS,
      );
    },
  );
}
