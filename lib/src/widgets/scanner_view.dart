import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mp_camera_scanner/mp_camera_scanner.dart';

class ScannerView extends StatefulWidget {
  final CameraControllerApp controller;
  final ValueChanged<BarcodeResultApp>? onDetected;

  const ScannerView({super.key, required this.controller, this.onDetected});

  @override
  State<ScannerView> createState() => _ScannerViewState();
}

class _ScannerViewState extends State<ScannerView> {
  StreamSubscription? _subscription;

  CameraControllerApp get camera => widget.controller;

  @override
  void initState() {
    super.initState();

    _subscription = widget.controller.barcodes.listen((result) {
      widget.onDetected?.call(result);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CameraPreviewApp(cameraControllerApp: camera);
  }
}
