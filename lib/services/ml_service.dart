import 'package:ishara/models/landmarks_model.dart';
import 'package:ishara/models/sign_prediction_model.dart';
import 'package:ishara/services/motion_analyzer.dart';
import 'package:ishara/services/sign_model_service.dart';

class MLService {
  final SignModelService _signModelService = SignModelService();

  bool get isLoaded => _signModelService.isLoaded;

  Future<void> loadModel(List<String> labels) async {
    await _signModelService.loadModel(labels);
  }

  Future<SignPrediction?> predict(HandLandmarks landmarks, {MotionFeatures? motionFeatures}) async {
    return await _signModelService.predict(landmarks, motionFeatures: motionFeatures);
  }

  Future<void> dispose() async {
    _signModelService.dispose();
  }
}
