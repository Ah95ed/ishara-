import 'package:flutter_test/flutter_test.dart';
import 'package:ishara/services/word_only_filter.dart';

void main() {
  group('WordOnlyFilter Tests (المتطلب 10)', () {
    test('يجب استبعاد أي حرف عربي منفرد قطعياً', () {
      const letters = ['أ', 'ب', 'ت', 'ث', 'ج', 'ح', 'خ', 'د', 'ذ', 'ر', 'ز', 'س', 'ش', 'ص', 'ض', 'ط', 'ظ', 'ع', 'غ', 'ف', 'ق', 'ك', 'ل', 'م', 'ن', 'هـ', 'و', 'ي'];
      for (final letter in letters) {
        expect(WordOnlyFilter.isValidWord(letter), isFalse, reason: 'الحرف $letter يجب ألا يُقبل');
        expect(WordOnlyFilter.filter(letter), isNull);
      }
    });

    test('يجب استبعاد أي حرف إنجليزي أو رقم أو فراغ', () {
      const invalid = ['A', 'B', 'O', '1', '2', '9', ' ', '', '  ', 'Alef', 'Ba2', 'Space', 'Delete', 'BLANK', 'NO_SIGN'];
      for (final item in invalid) {
        expect(WordOnlyFilter.isValidWord(item), isFalse, reason: '$item يجب ألا يُقبل');
        expect(WordOnlyFilter.filter(item), isNull);
      }
    });

    test('يجب قبول الكلمات والـ Glosses الكاملة فقط', () {
      const validWords = [
        'ماء',
        'طعام',
        'مساعدة',
        'السلام',
        'أحبك',
        'شكراً',
        'أنا',
        'أنت',
        'ذهاب',
        'سوق',
        'نعم',
        'لا',
        'مريض',
        'طبيب',
        'بيت',
        'إنهاء',
      ];
      for (final word in validWords) {
        expect(WordOnlyFilter.isValidWord(word), isTrue, reason: 'الكلمة $word يجب أن تُقبل');
        expect(WordOnlyFilter.filter(word), equals(word));
      }
    });
  });
}
