import 'package:flutter_tts/flutter_tts.dart';
import 'package:ishara/constants/app_constants.dart';

class SpeechService {
  final FlutterTts _tts = FlutterTts();

  bool get isAvailable => true;

  Future<void> initialize() async {
    try {
      await _tts.setLanguage(AppConstants.ttsLanguage);
      await _tts.setSpeechRate(AppConstants.ttsSpeechRate);
      await _tts.setPitch(AppConstants.ttsPitch);
      await _tts.setVolume(AppConstants.ttsVolume);
    } catch (e) {
      // ignore
    }
  }

  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    try {
      await _tts.speak(text);
    } catch (e) {
      // ignore
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (e) {
      // ignore
    }
  }

  Future<void> dispose() async {
    await _tts.stop();
  }
}
