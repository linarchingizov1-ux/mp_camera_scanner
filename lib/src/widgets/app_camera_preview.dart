import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:mp_camera_scanner/src/controllers/app_camera_controller.dart';

import 'dart:ui';

class CameraPreviewApp extends StatelessWidget {
  const CameraPreviewApp({super.key, required this.cameraControllerApp});

  final CameraControllerApp cameraControllerApp;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      child: ValueListenableBuilder<CameraValue>(
        valueListenable: cameraControllerApp.cameraController,
        builder: (context, value, child) {
          final previewSize = value.previewSize;
          final cameraNotReady = !value.isInitialized || previewSize == null;

          if (cameraNotReady) {
            return const _AnimatedSwitch(
              needSwitch: true,
              inWidget: _PlaceholderCamera(),
              outWidget: SizedBox.shrink(),
            );
          }

          final screenSize = MediaQuery.of(context).size;
          final previewRatio = previewSize.height / previewSize.width;
          final screenRatio = screenSize.height / screenSize.width;

          return _AnimatedSwitch(
            needSwitch: false,
            inWidget: const _PlaceholderCamera(),
            outWidget: ClipRect(
              child: OverflowBox(
                alignment: Alignment.center,
                maxWidth: screenRatio > previewRatio
                    ? screenSize.height / previewRatio
                    : screenSize.width,
                maxHeight: screenRatio > previewRatio
                    ? screenSize.height
                    : screenSize.width * previewRatio,
                child: CameraPreview(cameraControllerApp.cameraController),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AnimatedSwitch extends StatelessWidget {
  final Widget inWidget;
  final Widget outWidget;
  final bool needSwitch;

  const _AnimatedSwitch({
    required this.inWidget,
    required this.outWidget,
    required this.needSwitch,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 800),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: needSwitch
          ? const KeyedSubtree(
              key: ValueKey('placeholder'),
              child: _PlaceholderCamera(),
            )
          : KeyedSubtree(key: const ValueKey('camera'), child: outWidget),
    );
  }
}

class _PlaceholderCamera extends StatelessWidget {
  const _PlaceholderCamera();

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
        child: Image.asset(
          'assets/blur_photo.jpg',
          package: 'mp_camera_scanner',
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}
