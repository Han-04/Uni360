import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/widgets/curved_back_button.dart';
import 'corrective_widgets.dart';

class CorrectiveFacilityScanner extends StatefulWidget {
  const CorrectiveFacilityScanner({super.key});

  @override
  State<CorrectiveFacilityScanner> createState() =>
      _CorrectiveFacilityScannerState();
}

class _CorrectiveFacilityScannerState extends State<CorrectiveFacilityScanner> {
  final _scanner = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  bool _finished = false;

  @override
  void dispose() {
    unawaited(_scanner.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: CurvedBackButton.forRoute(context),
      title: const Text('Scan facility QR'),
    ),
    body: Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _scanner,
          onDetect: (capture) {
            if (_finished) return;
            for (final barcode in capture.barcodes) {
              if (barcode.rawValue case final String value
                  when value.isNotEmpty) {
                _finished = true;
                Navigator.of(context).pop(value);
                break;
              }
            }
          },
          errorBuilder: (_, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                error.errorCode == MobileScannerErrorCode.permissionDenied
                    ? 'Allow camera access in device settings to scan the facility QR.'
                    : 'The QR scanner could not start. Go back and try again.',
              ),
            ),
          ),
        ),
        const Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: CorrectiveMessage(
                'Point the camera at the Uni360 QR code displayed at this facility.',
                icon: Icons.qr_code,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
