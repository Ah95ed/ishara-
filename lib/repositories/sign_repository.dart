import 'package:flutter/services.dart';
import 'package:ishara/constants/app_constants.dart';

class SignRepository {
  final List<String> _labels = [];

  List<String> get labels => List.unmodifiable(_labels);

  Future<void> loadLabels() async {
    _labels.clear();
    try {
      final content = await rootBundle.loadString(AppConstants.labelsAssetPath);
      final lines = content.split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      _labels.addAll(lines);
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> loadModelMetadata() async {
    return {
      'version': '2.0.0',
      'engine': 'Strict Geometric Matcher',
      'labelsCount': _labels.length,
    };
  }
}
