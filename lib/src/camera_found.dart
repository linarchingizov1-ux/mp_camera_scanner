import 'package:camera/camera.dart';

class CameraFound {
  List<CameraDescription>? _cameras;
  CameraFound();

  List<CameraDescription> get cameras => _cameras!;

  Future<void> foundCameraPlatform() async {
    _cameras = await availableCameras();
  }
}
