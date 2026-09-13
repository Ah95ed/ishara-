import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// خدمة إدارة وتحميل قاموس لغة الإشارة العربية (ishara_vocab.json)
/// يحتوي على 684 فئة مطابقة لتدريب النموذج مع الـ CTC Blank (0 = "_").
class IsharaVocabService {
  static const String vocabAssetPath = 'assets/models/ishara_vocab.json';
  static const int expectedVocabSize = 684;
  static const int blankId = 0;
  static const String blankToken = '_';

  final Map<int, String> _idToGloss = {};
  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;
  int get vocabSize => _idToGloss.length;

  /// تحميل القاموس من ملف الأصول والتحقق الصارم من عدد الفئات
  Future<bool> loadVocab({String? customJsonString}) async {
    if (_isLoaded) return true;

    try {
      final String jsonString;
      if (customJsonString != null) {
        jsonString = customJsonString;
      } else {
        jsonString = await rootBundle.loadString(vocabAssetPath);
      }

      final dynamic decoded = jsonDecode(jsonString);
      if (decoded is! Map) {
        throw const FormatException('Invalid JSON format in vocab file: root is not a Map');
      }

      _idToGloss.clear();
      decoded.forEach((key, value) {
        final int? id = int.tryParse(key.toString());
        if (id != null && value != null) {
          _idToGloss[id] = value.toString();
        }
      });

      // التحقق من الحجم
      if (_idToGloss.length != expectedVocabSize) {
        final errorMsg =
            'CRITICAL ERROR: Vocab size mismatch! Expected: $expectedVocabSize, Got: ${_idToGloss.length}';
        debugPrint('[IsharaVocabService] ❌ $errorMsg');
        _isLoaded = false;
        throw StateError(errorMsg);
      }

      // التحقق من Blank token
      if (_idToGloss[blankId] != blankToken) {
        debugPrint(
          '[IsharaVocabService] ⚠️ Warning: ID 0 is "${_idToGloss[blankId]}" (expected "$blankToken")',
        );
      }

      _isLoaded = true;
      debugPrint('[IsharaVocabService] ✅ Vocab loaded successfully: ${_idToGloss.length} classes');
      return true;
    } catch (e, stack) {
      _isLoaded = false;
      debugPrint('[IsharaVocabService] ❌ Failed to load vocab: $e\n$stack');
      return false;
    }
  }

  /// إرجاع الكلمة (Gloss) المقابلة للمعرّف، مع استبدال الشُرط السفلية بمسافات للقراءة
  String? getGloss(int id, {bool replaceUnderscores = true}) {
    final raw = _idToGloss[id];
    if (raw == null || raw == blankToken) return null;
    if (replaceUnderscores) {
      return raw.replaceAll('_', ' ').trim();
    }
    return raw;
  }

  /// فحص هل المعرف هو رمز الفراغ
  bool isBlank(int id) => id == blankId;

  void clear() {
    _idToGloss.clear();
    _isLoaded = false;
  }
}
