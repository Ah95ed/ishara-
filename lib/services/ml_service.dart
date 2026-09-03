import 'package:ishara/models/landmarks_model.dart';
import 'package:ishara/models/sign_prediction_model.dart';
import 'package:ishara/services/sign_model_service.dart';

class MLService {
  final SignModelService _signModelService = SignModelService();

  bool get isLoaded => _signModelService.isLoaded;

  Future<void> loadModel(List<String> labels) async {
    await _signModelService.loadModel(labels);
  }

  Future<SignPrediction?> predict(HandLandmarks landmarks) async {
    return await _signModelService.predict(landmarks);
  }

  Future<void> dispose() async {
    _signModelService.dispose();
  }
}
