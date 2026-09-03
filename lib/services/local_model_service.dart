import 'package:flutter/material.dart';
import 'package:ishara/models/sign_prediction_model.dart';

class LocalModelService extends ChangeNotifier {
  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;

  Future<void> initialize() async {
    await Future.delayed(const Duration(milliseconds: 300));
    _isLoaded = true;
  }

  Future<SignPrediction?> predict(dynamic input) async {
    if (!_isLoaded) return null;
    return null;
  }

  @override
  Future<void> dispose() async {
    _isLoaded = false;
    super.dispose();
  }
}
