import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// نتيجة التحقق من توافق المفردات (Vocabulary Validation Result)
class VocabValidationResult {
  final bool isPass;
  final int totalEntries;
  final bool blankHandlingPass;
  final List<int> missingIds;
  final String? errorCode;
  final String? errorMessage;

  const VocabValidationResult({
    required this.isPass,
    required this.totalEntries,
    required this.blankHandlingPass,
    this.missingIds = const [],
    this.errorCode,
    this.errorMessage,
  });
}

/// IsharaVocabService
/// خدمة تحميل وإدارة قاموس الكلمات والمفردات لنموذج Ishara:
/// - تحميل ملف `assets/models/ishara_vocab.json` الفعلي.
/// - بنية المفردات: Map<int, String> يربط كل Class ID بالـ Gloss المقابل.
/// - Blank ID = 0 هو رمز الفراغ ('_') ويتم التعامل معه بنجاح دون اعتباره خطأ.
/// - التحقق الصارم من النطاق [0..683].
/// - تحويل أي ID غير موجود إلى <UNKNOWN_ID_xxx> وتسجيل MISSING_VOCAB_ID = xxx.
/// - خلو تام من أي كلمات hardcoded أو تصحيحات لغوية أو فلاتر ثقة.
class IsharaVocabService {
  static const String defaultVocabAssetPath = 'assets/models/ishara_vocab.json';
  static const int expectedClasses = 684;
  static const int blankId = 0;

  final String assetPath;
  final Map<int, String> _idToGloss = {};
  bool _isLoaded = false;
  String? _errorCode;
  String? _errorMessage;

  IsharaVocabService({this.assetPath = defaultVocabAssetPath});

  bool get isLoaded => _isLoaded;
  int get entriesCount => _idToGloss.length;
  String? get errorCode => _errorCode;
  String? get errorMessage => _errorMessage;
  Map<int, String> get idToGlossMap => Map.unmodifiable(_idToGloss);

  /// تحميل ملف المفردات من حزمة الأصول (Flutter rootBundle)
  Future<bool> loadVocabulary() async {
    try {
      final jsonString = await rootBundle.loadString(assetPath);
      return loadFromJsonString(jsonString);
    } catch (e) {
      _isLoaded = false;
      _errorCode = 'E_VOCAB_FILE_MISSING';
      _errorMessage = 'Failed to load vocabulary asset from $assetPath: $e';
      debugPrint('[IsharaVocabService] ❌ $_errorCode: $_errorMessage');
      return false;
    }
  }

  /// فك ترميز وتخزين المفردات من نص JSON
  bool loadFromJsonString(String jsonString) {
    try {
      final dynamic decoded = jsonDecode(jsonString);
      if (decoded is! Map) {
        _isLoaded = false;
        _errorCode = 'E_VOCAB_PARSE_FAILED';
        _errorMessage = 'Vocabulary JSON root is not a Map';
        debugPrint('[IsharaVocabService] ❌ $_errorCode: $_errorMessage');
        return false;
      }

      _idToGloss.clear();
      for (final entry in decoded.entries) {
        final keyStr = entry.key.toString();
        final id = int.tryParse(keyStr);
        if (id != null) {
          _idToGloss[id] = entry.value.toString();
        }
      }

      if (_idToGloss.isEmpty) {
        _isLoaded = false;
        _errorCode = 'E_VOCAB_PARSE_FAILED';
        _errorMessage = 'Parsed vocabulary is empty';
        return false;
      }

      _isLoaded = true;
      _errorCode = null;
      _errorMessage = null;

      debugPrint(
        '[IsharaVocabService] ✅ Vocabulary loaded successfully: '
        '${_idToGloss.length} entries. Blank token (ID 0) = "${_idToGloss[0]}"',
      );
      return true;
    } catch (e) {
      _isLoaded = false;
      _errorCode = 'E_VOCAB_PARSE_FAILED';
      _errorMessage = 'Exception during vocabulary parsing: $e';
      debugPrint('[IsharaVocabService] ❌ $_errorCode: $_errorMessage');
      return false;
    }
  }

  /// الحصول على الـ Gloss المقابل لـ Class ID مع التعامل الصارم مع الحالات الشاذة
  String getGloss(int classId) {
    if (classId < 0 || classId >= expectedClasses) {
      debugPrint('[IsharaVocabService] ⚠️ CTC_ID_OUT_OF_RANGE: Class ID $classId is outside [0..${expectedClasses - 1}]');
      return '<CTC_ID_OUT_OF_RANGE_$classId>';
    }

    if (!_isLoaded) {
      return '<VOCAB_NOT_LOADED_ID_$classId>';
    }

    final gloss = _idToGloss[classId];
    if (gloss == null) {
      debugPrint('[IsharaVocabService] ⚠️ MISSING_VOCAB_ID = $classId');
      return '<UNKNOWN_ID_$classId>';
    }

    return gloss;
  }

  /// تحويل قائمة من Decoded IDs إلى قائمة من الـ Glosses الحقيقية
  List<String> mapIdsToGlosses(List<int> decodedIds) {
    return decodedIds.map((id) => getGloss(id)).toList();
  }

  /// فحص وتحقق من صحة تغطية المفردات لمجموعة IDs معينة
  VocabValidationResult validateDecodedIds(List<int> decodedIds) {
    if (!_isLoaded) {
      return VocabValidationResult(
        isPass: false,
        totalEntries: _idToGloss.length,
        blankHandlingPass: false,
        errorCode: _errorCode ?? 'E_VOCAB_FILE_MISSING',
        errorMessage: _errorMessage ?? 'Vocabulary is not loaded',
      );
    }

    final missing = <int>[];
    for (final id in decodedIds) {
      if (id < 0 || id >= expectedClasses || !_idToGloss.containsKey(id)) {
        missing.add(id);
      }
    }

    final blankPass = _idToGloss.containsKey(blankId);

    return VocabValidationResult(
      isPass: missing.isEmpty && blankPass,
      totalEntries: _idToGloss.length,
      blankHandlingPass: blankPass,
      missingIds: missing,
      errorCode: missing.isNotEmpty ? 'E_VOCAB_ID_MISSING' : null,
      errorMessage: missing.isNotEmpty ? 'Missing vocabulary mappings for IDs: $missing' : null,
    );
  }
}
