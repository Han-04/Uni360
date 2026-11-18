import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web/web.dart' as web;

import '../account.dart';

class AdminPortalView extends StatefulWidget {
  const AdminPortalView({super.key, this.correctiveBuilder});

  final Widget Function(SupabaseClient, String, VoidCallback)?
  correctiveBuilder;

  @override
  State<AdminPortalView> createState() => _AdminPortalViewState();
}

class _AdminPortalViewState extends State<AdminPortalView> {
  static const _url = String.fromEnvironment('SUPABASE_URL');
  static const _key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  final _origin = web.window.location.origin;
  late final JSFunction _messageHandler = _onMessage.toJS;
  late final JSFunction _loadHandler = ((web.Event _) => _configure()).toJS;
  web.HTMLIFrameElement? _frame;
  SupabaseClient? _client;
  String? _accessToken, _administratorId;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    web.window.addEventListener('message', _messageHandler);
  }

  @override
  void dispose() {
    web.window.removeEventListener('message', _messageHandler);
    _frame?.removeEventListener('load', _loadHandler);
    _accessToken = null;
    unawaited(_client?.dispose());
    super.dispose();
  }

  void _configure() {
    _clearSession();
    _frame?.contentWindow?.postMessage(
      {
        'type': 'uni360-admin-config',
        'url': _url,
        'key': _key,
        'corrective': widget.correctiveBuilder != null,
      }.jsify(),
      _origin.toJS,
    );
  }

  void _onMessage(web.MessageEvent event) {
    final source = _frame?.contentWindow;
    if (source == null ||
        event.origin != _origin ||
        !identical(event.source, source) ||
        widget.correctiveBuilder == null) {
      return;
    }
    switch (event.data.dartify()) {
      case {'type': 'uni360-admin-sign-out'}:
        _clearSession();
      case {
        'type': 'uni360-admin-token-refreshed',
        'userId': final String userId,
        'accessToken': final String token,
      }:
        if (userId == _administratorId && token.isNotEmpty) {
          _accessToken = token;
        }
      case {
            'type': 'uni360-admin-open-corrective',
            'userId': final String userId,
            'accessToken': final String token,
          }
          when userId.isNotEmpty && token.isNotEmpty:
        unawaited(_openCorrective(userId, token));
    }
  }

  void _clearSession() {
    if (_administratorId == null) return;
    _accessToken = null;
    _administratorId = null;
    final portal = ModalRoute.of(context);
    if (portal?.isActive == true && portal?.isCurrent == false) {
      Navigator.of(context).popUntil((route) => identical(route, portal));
    }
  }

  Future<void> _openCorrective(String userId, String token) async {
    final portal = ModalRoute.of(context);
    if (_opening || portal?.isCurrent != true) return;

    _opening = true;
    _administratorId = userId;
    _accessToken = token;
    try {
      // The iframe owns the sign-in and token refresh for the desktop portal.
      final client = _client ??= SupabaseClient(
        _url,
        _key,
        accessToken: () async => _accessToken,
      );
      final account = await client
          .from('account')
          .select('role,is_active')
          .eq('user_id', userId)
          .maybeSingle();
      if (!mounted || _administratorId != userId || portal?.isCurrent != true) {
        return;
      }
      if (account?['is_active'] != true ||
          !AccountRole.values.any(
            (role) => role.isAdministrator && role.value == account?['role'],
          )) {
        _showError('An active administrator account is required.');
        _clearSession();
        return;
      }
      unawaited(_showCorrective(client, userId));
    } on Exception {
      if (mounted && portal?.isCurrent == true && _administratorId == userId) {
        _clearSession();
        _showError('Could not open Corrective Maintenance. Try again.');
      }
    } finally {
      _opening = false;
    }
  }

  Future<void> _showCorrective(SupabaseClient client, String userId) async {
    final builder = widget.correctiveBuilder!;
    final portalNavigator = Navigator.of(context);
    final correctiveNavigator = GlobalKey<NavigatorState>();
    final frame = _frame;
    if (frame != null) frame.inert = true;
    try {
      // Keep the iframe in the DOM while corrective screens are open.
      await portalNavigator.push<void>(
        PageRouteBuilder<void>(
          opaque: false,
          pageBuilder: (_, _, _) => NavigatorPopHandler<void>(
            onPopWithResult: (_) => correctiveNavigator.currentState?.pop(),
            child: Navigator(
              key: correctiveNavigator,
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (_) => builder(client, userId, portalNavigator.pop),
              ),
            ),
          ),
        ),
      );
    } finally {
      if (frame != null) frame.inert = false;
    }
  }

  void _showError(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) => HtmlElementView.fromTagName(
    tagName: 'iframe',
    onElementCreated: (element) {
      final frame = _frame = element as web.HTMLIFrameElement;
      frame
        ..title = 'Uni360 Administration'
        ..src = Uri.parse(web.document.baseURI)
            .resolve('admin/index.html')
            .toString()
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%';
      frame.addEventListener('load', _loadHandler);
    },
  );
}
