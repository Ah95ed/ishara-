import 'package:flutter/material.dart';

enum CameraState {
  initial,
  loading,
  ready,
  streaming,
  error,
}

class CameraStateModel extends ChangeNotifier {
  CameraState _state = CameraState.initial;
  String? _errorMessage;

  CameraState get state => _state;
  String? get errorMessage => _errorMessage;
  bool get isReady => _state == CameraState.ready || _state == CameraState.streaming;
  bool get hasError => _state == CameraState.error;

  void setState(CameraState newState, [String? error]) {
    _state = newState;
    _errorMessage = error;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
