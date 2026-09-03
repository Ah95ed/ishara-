import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ishara/models/landmarks_model.dart';
import 'package:ishara/models/sign_prediction_model.dart';
import 'package:ishara/services/ml_service.dart';
import 'package:ishara/services/speech_service.dart';
import 'package:ishara/services/temporal_stabilizer.dart';
import 'package:ishara/services/word_buffer_service.dart';

class SignProvider extends ChangeNotifier {
  final MLService _mlService;
  final SpeechService _speechService;
  final WordBufferService _wordBuffer = WordBufferService();
  final TemporalStabilizer _temporalStabilizer = TemporalStabilizer();

  SignPrediction? _currentRealtimePrediction;
  SignPrediction? _lastStablePrediction;
  SignStabilityState _stabilityState = SignStabilityState.detecting;
  bool _isProcessing = false;
  bool _autoSpeakEnabled = false;
  bool _autoTranslateEnabled = true;

  void Function(SignPrediction prediction)? onStableSignDetected;
  void Function(SignStabilityState state, String? label, double confidence)? onStabilityStateChanged;
  Future<void> Function(List<String> words, List<SignPrediction> sequence)? onAutoTranslate;

  SignProvider(this._mlService, this._speechService) {
    _wordBuffer.addListener(notifyListeners);
    _wordBuffer.onSentenceReady = (words, sequence) {
      if (_autoTranslateEnabled && onAutoTranslate != null && words.isNotEmpty) {
        onAutoTranslate!(words, sequence);
      }
    };

    // ربط مستشعر الثبات الزمني
    _temporalStabilizer.onStableSign = (stablePrediction) {
      _lastStablePrediction = stablePrediction;
      _wordBuffer.pushPrediction(stablePrediction);
      if (onStableSignDetected != null) {
        onStableSignDetected!(stablePrediction);
      }
      notifyListeners();
    };

    _temporalStabilizer.onStateChanged = (state, label, confidence) {
      _stabilityState = state;
      if (onStabilityStateChanged != null) {
        onStabilityStateChanged!(state, label, confidence);
      }
      notifyListeners();
    };
  }

  List<String> get wordTokens => _wordBuffer.words;
  List<SignPrediction> get predictionSequence => _wordBuffer.predictionSequence;
  String get textBuffer => _wordBuffer.sentenceRaw;
  SignPrediction? get currentRealtimePrediction => _currentRealtimePrediction;
  SignPrediction? get lastStablePrediction => _lastStablePrediction;
  SignStabilityState get stabilityState => _stabilityState;
  bool get isProcessing => _isProcessing;
  bool get hasText => _wordBuffer.isNotEmpty;
  bool get isModelLoaded => _mlService.isLoaded;
  bool get autoSpeakEnabled => _autoSpeakEnabled;
  bool get autoTranslateEnabled => _autoTranslateEnabled;

  void toggleAutoSpeak() {
    _autoSpeakEnabled = !_autoSpeakEnabled;
    notifyListeners();
  }

  void toggleAutoTranslate() {
    _autoTranslateEnabled = !_autoTranslateEnabled;
    notifyListeners();
  }

  Future<void> loadModel(List<String> labels) async {
    await _mlService.loadModel(labels);
  }

  Future<void> processLandmarks(HandLandmarks? landmarks) async {
    if (landmarks == null || !landmarks.isValid) {
      _currentRealtimePrediction = null;
      _temporalStabilizer.processPrediction(null);
      _wordBuffer.resetCurrentHand();
      notifyListeners();
      return;
    }

    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final prediction = await _mlService.predict(landmarks);
      _currentRealtimePrediction = prediction;

      // تمرير التنبؤ إلى الـ TemporalStabilizer لإجراء التصويت والتثبيت
      _temporalStabilizer.processPrediction(prediction);

      notifyListeners();
    } finally {
      _isProcessing = false;
    }
  }

  void addWord(String word) {
    final pred = SignPrediction(
      label: word,
      confidence: 1.0,
      timestamp: DateTime.now(),
    );
    _lastStablePrediction = pred;
    _wordBuffer.pushPrediction(pred);
    if (onStableSignDetected != null) {
      onStableSignDetected!(pred);
    }
  }

  void removeWordAt(int index) {
    if (index >= 0 && index < _wordBuffer.length) {
      _wordBuffer.deleteLastWord();
    }
  }

  void deleteLastWord() {
    _wordBuffer.deleteLastWord();
  }

  void clearText() {
    _wordBuffer.clear();
    _temporalStabilizer.reset();
    _currentRealtimePrediction = null;
    _lastStablePrediction = null;
    _stabilityState = SignStabilityState.detecting;
    notifyListeners();
  }

  Future<void> speakText(String text) async {
    if (text.trim().isEmpty) return;
    await _speechService.speak(text.trim());
  }

  Future<void> stopSpeaking() async {
    await _speechService.stop();
  }

  @override
  void dispose() {
    _wordBuffer.dispose();
    _mlService.dispose();
    _speechService.dispose();
    super.dispose();
  }
}
