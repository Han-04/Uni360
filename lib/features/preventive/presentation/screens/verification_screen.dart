import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/common.dart';
import '../../application/preventive_controller.dart';
import '../../domain/verification_service.dart';
import '../../domain/work_order.dart';

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({
    super.key,
    required this.controller,
    required this.order,
  });
  final PreventiveController controller;
  final WorkOrder order;
  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  bool _busy = false;
  String? _error;
  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on StateError catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller, o = widget.order;
      final location = c.hasLocation(o),
          qr = c.hasQr(o),
          reading = c.readingFor(o);
      return Scaffold(
        appBar: AppBar(title: const Text('Verify your work site')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const InfoBanner(
                  'Demo verification · These controls use sample GPS and QR values. Your device location and camera are not accessed.',
                ),
                const SizedBox(height: 20),
                SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        o.facility.name,
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        o.facility.location,
                        style: const TextStyle(color: AppColors.muted),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Asset ${o.facility.assetTag} · ${o.facility.radiusMeters.round()} m geofence',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SectionHeading('01  Confirm your location'),
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: AppColors.navy,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      for (final size in [150.0, 100.0, 48.0])
                        Container(
                          width: size,
                          height: size,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.teal.withValues(alpha: .15),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: .12),
                            ),
                          ),
                        ),
                      Icon(
                        location
                            ? Icons.verified_user_outlined
                            : Icons.my_location,
                        color: const Color(0xFF7EDBD0),
                        size: 30,
                      ),
                      const Positioned(
                        bottom: 15,
                        child: Text(
                          'SIMULATED LOCATION',
                          style: TextStyle(
                            color: Color(0xFFB5C9DA),
                            fontSize: 10,
                            letterSpacing: 1.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (reading != null) ...[
                  Text(
                    'Within boundary · ${distanceMeters(reading, o.facility).round()} m from site · GPS ±${reading.accuracyMeters.round()} m',
                    style: const TextStyle(color: AppColors.teal, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                ],
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(() => c.verifyLocation(o)),
                  icon: Icon(
                    location ? Icons.check_circle : Icons.location_on_outlined,
                  ),
                  label: Text(
                    location
                        ? 'Location verified · Check again'
                        : 'Verify demo location',
                  ),
                ),
                const SectionHeading('02  Confirm the facility QR'),
                SurfaceCard(
                  child: Column(
                    children: [
                      const Icon(
                        Icons.qr_code_scanner,
                        size: 58,
                        color: AppColors.teal,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        qr
                            ? 'Facility and asset matched'
                            : 'Match the QR code at your assigned work site',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        o.facility.assetTag,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: !location || _busy
                              ? null
                              : () => _run(() => c.verifyQr(o)),
                          icon: Icon(qr ? Icons.check_circle : Icons.qr_code),
                          label: Text(
                            qr
                                ? 'QR verified · Scan again'
                                : 'Simulate matching QR scan',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (_error != null) ...[
                  InfoBanner(_error!, warning: true),
                  const SizedBox(height: 16),
                ],
                FilledButton.icon(
                  onPressed:
                      _busy || !location || (o.facility.requiresQr && !qr)
                      ? null
                      : () {
                          try {
                            c.start(o);
                            Navigator.pop(context);
                            showMessage(
                              context,
                              'Checked in. Your work timer has started.',
                            );
                          } on StateError catch (e) {
                            setState(() => _error = e.message);
                          }
                        },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Check in & start work timer'),
                ),
                const SizedBox(height: 20),
                ExpansionTile(
                  title: const Text(
                    'Try demo failure scenarios',
                    style: TextStyle(fontSize: 13),
                  ),
                  children: [
                    ListTile(
                      title: const Text(
                        'Outside geofence',
                        style: TextStyle(fontSize: 13),
                      ),
                      leading: const Icon(Icons.location_off_outlined),
                      onTap: _busy
                          ? null
                          : () =>
                                _run(() => c.verifyLocation(o, outside: true)),
                    ),
                    ListTile(
                      title: const Text(
                        'Wrong facility QR',
                        style: TextStyle(fontSize: 13),
                      ),
                      leading: const Icon(Icons.wrong_location_outlined),
                      onTap: !location || _busy
                          ? null
                          : () => _run(() => c.verifyQr(o, mismatched: true)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
