import 'package:ishara/models/landmarks_model.dart';
import 'package:ishara/models/sign_prediction_model.dart';

/// محرك الاستنتاج لنموذج الإشارة
/// الحالة الحالية: Stub — الترجمة تعمل عبر النصوص/الخادم في هذه المرحلة.
class SignModelService {
  bool _isModelLoaded = false;
  List<String> _labels = [];

  bool get isLoaded => _isModelLoaded;

  Future<void> loadModel(List<String> labels) async {
    _labels = labels;
    _isModelLoaded = false;
  }

  Future<SignPrediction?> predict(HandLandmarks landmarks) async {
    if (!_isModelLoaded || _labels.isEmpty) return null;
    return null;
  }

  void dispose() {
    _isModelLoaded = false;
  }
}
