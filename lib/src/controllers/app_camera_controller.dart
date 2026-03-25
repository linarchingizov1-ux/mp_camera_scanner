import 'package:flutter/widgets.dart';

import 'dart:async';
import 'package:camera/camera.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'dart:io';

enum CameraModeApp { barcode, photo }

abstract class CameraApp {
  Future<void> init();
  Future<void> pause();
  Future<void> resume();
  Future<void> switchCamera();
  Future<void> dispose();
}

class BarcodeResultApp {
  final List<Barcode> barcodes;
  final CameraImage image;
  final DateTime detectedAt;

  const BarcodeResultApp({
    required this.barcodes,
    required this.image,
    required this.detectedAt,
  });
}

class CameraControllerApp extends CameraApp with WidgetsBindingObserver {
  CameraControllerApp({required this.type, required this.cameras})
    : _barcodeScanner = BarcodeScanner(formats: [BarcodeFormat.all]) {
    _currentDescription = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    cameraController = _createController(_currentDescription);
  }

  final CameraModeApp type;
  final List<CameraDescription> cameras;
  final BarcodeScanner _barcodeScanner;

  late CameraController cameraController;
  late CameraDescription _currentDescription;

  final StreamController<BarcodeResultApp> _barcodeStreamController =
      StreamController<BarcodeResultApp>.broadcast();

  Stream<BarcodeResultApp> get barcodes => _barcodeStreamController.stream;

  bool _isDisposed = false;
  bool _isInitialized = false;
  bool _isSwitchingCamera = false;
  bool _isProcessingFrame = false;
  bool _isStreamingStarted = false;
  bool _isPausedManually = false;

  int _frameCount = 0;
  DateTime _lastAnalyzedAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastDetectedAt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastDetectedRawValue;

  bool get isDisposed => _isDisposed;
  bool get cameraInit => _isInitialized && cameraController.value.isInitialized;
  bool get cameraPaused => cameraController.value.isPreviewPaused;
  bool get imageStream => cameraController.value.isStreamingImages;
  CameraDescription get currentDescription => _currentDescription;

  static const int _analyzeEveryNFrame = 2;
  static const Duration _minAnalyzeInterval = Duration(milliseconds: 80);
  static const Duration _sameCodeCooldown = Duration(milliseconds: 1200);

  CameraController _createController(CameraDescription description) {
    return CameraController(
      description,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );
  }

  @override
  Future<void> init() async {
    if (_isDisposed || _isInitialized) return;

    WidgetsBinding.instance.addObserver(this);
    await Future.delayed(const Duration(milliseconds: 350));
    await cameraController.initialize();
    await cameraController.setFocusMode(FocusMode.auto);
    await cameraController.setExposureMode(ExposureMode.auto);

    _isInitialized = true;

    if (type == CameraModeApp.barcode) {
      await _startImageStreamSafely();
    }
  }

  @override
  Future<void> pause() async {
    if (_isDisposed || !cameraInit || _isPausedManually) return;

    _isPausedManually = true;

    await _stopImageStreamSafely();

    if (!cameraController.value.isPreviewPaused) {
      await cameraController.pausePreview();
    }
  }

  @override
  Future<void> resume() async {
    if (_isDisposed || !cameraInit) return;
    if (!_isPausedManually && !cameraController.value.isPreviewPaused) return;

    if (cameraController.value.isPreviewPaused) {
      await cameraController.resumePreview();
    }

    if (type == CameraModeApp.barcode) {
      await _startImageStreamSafely();
    }

    _isPausedManually = false;
  }

  @override
  Future<void> switchCamera() async {
    if (_isDisposed || !cameraInit || _isSwitchingCamera) return;
    if (cameras.length < 2) return;

    _isSwitchingCamera = true;

    try {
      final oldLens = _currentDescription.lensDirection;

      final nextDescription = cameras.firstWhere(
        (c) => c.lensDirection != oldLens,
        orElse: () => _currentDescription,
      );

      await _stopImageStreamSafely();
      await cameraController.dispose();

      _currentDescription = nextDescription;
      cameraController = _createController(_currentDescription);

      await cameraController.initialize();
      await cameraController.setFocusMode(FocusMode.auto);
      await cameraController.setExposureMode(ExposureMode.auto);

      _resetDetectionState();

      if (type == CameraModeApp.barcode) {
        await _startImageStreamSafely();
      }
    } finally {
      _isSwitchingCamera = false;
    }
  }

  Future<void> focusAt(Offset normalizedPoint) async {
    if (_isDisposed || !cameraInit) return;

    final dx = normalizedPoint.dx.clamp(0.0, 1.0);
    final dy = normalizedPoint.dy.clamp(0.0, 1.0);

    try {
      await cameraController.setFocusMode(FocusMode.auto);
      await cameraController.setFocusPoint(Offset(dx, dy));
      await cameraController.setExposurePoint(Offset(dx, dy));
    } catch (e, st) {
      FlutterError('Произошла ошибка при фокусе $e $st');
    }
  }

  Future<void> _startImageStreamSafely() async {
    if (_isDisposed || !cameraInit) return;
    if (_isStreamingStarted || cameraController.value.isStreamingImages) return;

    _isStreamingStarted = true;
    await cameraController.startImageStream(_processImage);
  }

  Future<void> _stopImageStreamSafely() async {
    if (_isDisposed || !cameraInit) return;
    if (!_isStreamingStarted && !cameraController.value.isStreamingImages) {
      return;
    }

    try {
      if (cameraController.value.isStreamingImages) {
        await cameraController.stopImageStream();
      }
    } catch (e, st) {
      FlutterError('Произошла ошибка при старте потока камеры $e $st');
    } finally {
      _isStreamingStarted = false;
      _isProcessingFrame = false;
    }
  }

  void _resetDetectionState() {
    _frameCount = 0;
    _isProcessingFrame = false;
    _lastDetectedRawValue = null;
    _lastDetectedAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastAnalyzedAt = DateTime.fromMillisecondsSinceEpoch(0);
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    final rotation = InputImageRotationValue.fromRawValue(
      _currentDescription.sensorOrientation,
    );
    if (rotation == null) return null;

    if (Platform.isAndroid) {
      if (image.planes.isEmpty) return null;

      return InputImage.fromBytes(
        bytes: image.planes.first.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );
    }

    if (Platform.isIOS) {
      if (image.planes.length != 1) return null;

      return InputImage.fromBytes(
        bytes: image.planes.first.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );
    }

    return null;
  }

  Future<void> _processImage(CameraImage image) async {
    if (_isDisposed || !cameraInit) return;
    if (_isProcessingFrame) return;

    _frameCount++;
    if (_frameCount % _analyzeEveryNFrame != 0) return;

    final now = DateTime.now();
    if (now.difference(_lastAnalyzedAt) < _minAnalyzeInterval) return;
    _lastAnalyzedAt = now;

    final inputImage = _inputImageFromCameraImage(image);
    if (inputImage == null) return;

    _isProcessingFrame = true;

    try {
      final foundBarcodes = await _barcodeScanner.processImage(inputImage);

      if (foundBarcodes.isEmpty) return;
      if (_barcodeStreamController.isClosed) return;

      final first = foundBarcodes.first;
      final rawValue = first.rawValue ?? first.displayValue ?? '';

      final isSameRecentlyDetected =
          rawValue.isNotEmpty &&
          rawValue == _lastDetectedRawValue &&
          now.difference(_lastDetectedAt) < _sameCodeCooldown;

      if (isSameRecentlyDetected) return;

      _lastDetectedRawValue = rawValue;
      _lastDetectedAt = now;

      final rect = first.boundingBox;
      if (!rect.isEmpty) {
        final x = (rect.center.dx / image.width).clamp(0.0, 1.0);
        final y = (rect.center.dy / image.height).clamp(0.0, 1.0);

        await focusAt(Offset(x, y));
      }

      _barcodeStreamController.add(
        BarcodeResultApp(
          barcodes: foundBarcodes,
          image: image,
          detectedAt: now,
        ),
      );
    } catch (e, st) {
      FlutterError('Произошла ошибка в потоке $e $st');
    } finally {
      _isProcessingFrame = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDisposed || !cameraInit) return;

    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _stopImageStreamSafely();
        if (!cameraController.value.isPreviewPaused) {
          cameraController.pausePreview();
        }
        break;

      case AppLifecycleState.resumed:
        if (cameraController.value.isPreviewPaused) {
          cameraController.resumePreview();
        }

        if (type == CameraModeApp.barcode && !_isPausedManually) {
          _startImageStreamSafely();
        }
        break;

      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    WidgetsBinding.instance.removeObserver(this);

    await _stopImageStreamSafely();
    await _barcodeScanner.close();
    await _barcodeStreamController.close();
    await cameraController.dispose();
  }
}
