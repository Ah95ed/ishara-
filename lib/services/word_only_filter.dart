import 'package:characters/characters.dart';

/// مرشح الكلمات الصارم (Word-Only Filter)
///
/// المتطلب 10: استبعاد أي تنبؤ بحرف منفرد أو رقم (مثل: أ، ب، O، A، 1).
/// لا يظهر على الشاشة، لا يدخل Gloss Buffer، ولا يرسل إلى Gloss2Text.
/// يقبل كلمات أو Glosses كاملة فقط.
class WordOnlyFilter {
  WordOnlyFilter._();

  // قائمة الحروف الأبجدية العربية الفردية
  static const Set<String> _singleArabicLetters = {
    'أ',
    'ا',
    'إ',
    'آ',
    'ب',
    'ت',
    'ث',
    'ج',
    'ح',
    'خ',
    'د',
    'ذ',
    'ر',
    'ز',
    'س',
    'ش',
    'ص',
    'ض',
    'ط',
    'ظ',
    'ع',
    'غ',
    'ف',
    'ق',
    'ك',
    'ل',
    'م',
    'ن',
    'هـ',
    'ه',
    'و',
    'ي',
    'ى',
    'ئ',
    'ء',
    'ؤ',
    'ة',
  };

  // الأسماء التقنية للأحرف في نماذج الـ Dataset
  static const Set<String> _technicalLetterNames = {
    'alef',
    'ba2',
    'ta2',
    'tha2',
    'jim',
    '7a2',
    'kha2',
    'dal',
    'thal',
    'ra2',
    'zayn',
    'sin',
    'chin',
    'ssad',
    'ddad',
    'tta2',
    'ttha2',
    '3ayn',
    'ghayn',
    'fa2',
    '9af',
    'kaf',
    'lam',
    'mim',
    'noon',
    'ha2',
    'waw',
    'ya2',
    'space',
    'delete',
    'blank',
    'no_sign',
    'unknown',
    'none',
  };

  /// التحقق مما إذا كان النص يمثل كلمة كاملة صالحة للترجمة (Gloss)
  static bool isValidWord(String? text) {
    if (text == null) return false;
    final clean = text.trim();
    if (clean.isEmpty) return false;

    // 1. استبعاد أي نص طوله حرف واحد فقط (أ، ب، A، 1...)
    if (clean.characters.length <= 1) {
      return false;
    }

    // 2. استبعاد الحروف العربية المنفردة حتى لو كان معها مسافات أو تشكيل
    final withoutDiacritics = _stripDiacritics(clean);
    if (withoutDiacritics.characters.length <= 1) {
      return false;
    }
    if (_singleArabicLetters.contains(withoutDiacritics)) {
      return false;
    }

    // 3. استبعاد التسميات التقنية للأحرف باللاتينية
    final lower = clean.toLowerCase();
    if (_technicalLetterNames.contains(lower)) {
      return false;
    }

    // 4. استبعاد الأرقام المنفردة أو العلامات غير المعنوية
    if (RegExp(r'^[\d\s\p{P}]+$', unicode: true).hasMatch(clean)) {
      return false;
    }

    return true;
  }

  /// ترشيح الكلمة: يعيد الكلمة المنظفة إذا كانت مقبولة، أو null إن كانت حرفاً أو رمزاً مستبعداً
  static String? filter(String? text) {
    if (isValidWord(text)) {
      return text!.trim();
    }
    return null;
  }

  static String _stripDiacritics(String text) {
    // إزالة حركات التشكيل العربية (فتحة، ضمة، كسرة، تنوين، شدة، سكون)
    return text.replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '');
  }
}
