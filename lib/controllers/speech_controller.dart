import 'package:flutter/material.dart';
import 'package:ishara/services/speech_service.dart';

class SpeechProvider extends ChangeNotifier {
  final SpeechService _speechService;
  bool _isSpeaking = false;

  SpeechProvider(this._speechService);

  bool get isSpeaking => _isSpeaking;

  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    _isSpeaking = true;
    notifyListeners();
    await _speechService.speak(text);
    _isSpeaking = false;
    notifyListeners();
  }

  Future<void> stop() async {
    await _speechService.stop();
    _isSpeaking = false;
    notifyListeners();
  }

  Future<void> initialize() async {
    await _speechService.initialize();
  }
}
