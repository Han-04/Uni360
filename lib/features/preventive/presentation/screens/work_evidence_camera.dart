import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../../core/widgets/curved_back_button.dart';

import '../../data/assigned_work_repository.dart';

class WorkEvidenceCamera extends StatefulWidget {
  const WorkEvidenceCamera({super.key});

  @override
  State<WorkEvidenceCamera> createState() => _WorkEvidenceCameraState();
}

class _WorkEvidenceCameraState extends State<WorkEvidenceCamera>
    with WidgetsBindingObserver {
  CameraController? _camera;
  Future<void> _closing = Future.value();
  int _request = 0;
  bool _paused = false, _taking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _open();
  }

  Future<void> _open() async {
    final request = ++_request;
    setState(() => _error = null);
    try {
      await _closing;
      if (!mounted || request != _request) return;
      final devices = await availableCameras();
      if (!mounted || request != _request) return;
      if (devices.isEmpty) {
        throw CameraException(
          'NoCamera',
          'This device has no available camera.',
        );
      }
      final selected = devices.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => devices.first,
      );
      final camera = CameraController(
        selected,
        ResolutionPreset.high,
        enableAudio: false,
      );
      _camera = camera;
      await camera.initialize();
      if (mounted && request == _request) setState(() {});
    } on CameraException catch (error) {
      if (!mounted || request != _request) return;
      _release();
      setState(
        () => _error = switch (error.code) {
          'CameraAccessDenied' || 'CameraAccessDeniedWithoutPrompt' =>
            'Allow camera access for Uni360 in device settings.',
          'CameraAccessRestricted' =>
            'Camera access is restricted on this device.',
          'NoCamera' => 'This device has no available camera.',
          _ => 'Could not open the camera. Try again.',
        },
      );
    } on Exception {
      if (!mounted || request != _request) return;
      _release();
      setState(() => _error = 'Could not open the camera. Try again.');
    }
  }

  void _release() {
    ++_request;
    final camera = _camera;
    _camera = null;
    if (camera != null) {
      _closing = camera.dispose().catchError((Object _) {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _paused = true;
      _release();
      setState(() {});
    } else if (state == AppLifecycleState.resumed && _paused) {
      _paused = false;
      _open();
    }
  }

  Future<void> _take() async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized || _taking) return;
    setState(() {
      _taking = true;
      _error = null;
    });
    try {
      final photo = await camera.takePicture();
      if (await photo.length() > AssignedWorkRepository.maxPhotoBytes) {
        if (mounted) {
          setState(
            () => _error = 'This photo is over 10 MB. Try taking another.',
          );
        }
        return;
      }
      final bytes = await photo.readAsBytes();
      if (mounted) Navigator.pop<Uint8List>(context, bytes);
    } on Exception {
      if (mounted) {
        setState(() => _error = 'Could not take the photo. Try again.');
      }
    } finally {
      if (mounted) setState(() => _taking = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    final ready = camera != null && camera.value.isInitialized;
    return Scaffold(
      appBar: AppBar(
        leading: CurvedBackButton.forRoute(context),
        title: const Text('Take evidence photo'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: ready
                    ? CameraPreview(camera)
                    : _error == null
                    ? const CircularProgressIndicator()
                    : const Icon(Icons.no_photography_outlined, size: 44),
              ),
            ),
            if (_error case final error?)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(error, textAlign: TextAlign.center),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: _taking
                    ? null
                    : ready
                    ? _take
                    : _error != null
                    ? _open
                    : null,
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(ready ? 'Capture photo' : 'Retry camera'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
