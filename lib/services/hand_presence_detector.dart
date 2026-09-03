import 'package:camera/camera.dart';

class HandPresenceResult {
  final bool hasHand;
  final double confidence;
  final double minX;
  final double maxX;
  final double minY;
  final double maxY;
  final double palmX;
  final double palmY;
  final String reason;

  const HandPresenceResult({
    required this.hasHand,
    required this.confidence,
    this.minX = 0.0,
    this.maxX = 0.0,
    this.minY = 0.0,
    this.maxY = 0.0,
    this.palmX = 0.5,
    this.palmY = 0.5,
    required this.reason,
  });

  const HandPresenceResult.noHand([String reason = 'NO_HAND'])
      : hasHand = false,
        confidence = 0.0,
        minX = 0.0,
        maxX = 0.0,
        minY = 0.0,
        maxY = 0.0,
        palmX = 0.5,
        palmY = 0.5,
        reason = reason;
}

/// كاشف الحضور الفيزيائي لليد البشرية — متعدد المعايير المستقلة (Multi-Cue Stage 1 Detector)
///
/// يتطلب أن تتحقق عدة شروط مستقلة في آنٍ واحد — وليس شرطاً واحداً —
/// للحد الأقصى من منع False Positives دون الاعتماد على لون الجلد.
///
/// الشروط المستقلة:
/// [A] وجود كتلة لومينانس ذات تباين محلي معقول (ليس جداراً أو ورقة بيضاء)
/// [B] وجود تدرج غير متساوٍ في الاتجاهين (تباين عضوي وليس هندسياً)
/// [C] وجود كتلة مكثفة مترابطة بحجم وشكل يد (Morphological Blob Check)
/// [D] انتروبيا محلية كافية (Local Entropy) للتمييز عن الأسطح الملساء
/// [E] وجود تباين رأسي / أفقي غير متساوٍ (الأصابع المرتفعة تعطي تباين رأسي واضح)
///
/// يجب أن تجتاز الصورة [A] AND [B] AND [C] AND [D] جميعاً — الفشل في أي منها = NO_HAND
class HandPresenceDetector {
  static const double _minConfidenceToPass = 0.70;

  static HandPresenceResult detect(CameraImage image) {
    final width = image.width;
    final height = image.height;
    if (width <= 0 || height <= 0 || image.planes.isEmpty) {
      return const HandPresenceResult.noHand('INVALID_IMAGE');
    }

    final yPlane = image.planes[0].bytes;
    final yRowStride = image.planes[0].bytesPerRow;

    // منطقة الفحص المركزية — اليد عادةً في المركز وليست في الزوايا
    final startX = (width * 0.12).toInt();
    final endX = (width * 0.88).toInt();
    final startY = (height * 0.10).toInt();
    final endY = (height * 0.90).toInt();

    const step = 7; // خطوة أكبر = أسرع ولكن لا تزال دقيقة
    final sampleCols = (endX - startX) ~/ step;
    final sampleRows = (endY - startY) ~/ step;

    if (sampleCols < 5 || sampleRows < 5) {
      return const HandPresenceResult.noHand('ROI_TOO_SMALL');
    }

    // ===== جمع البيانات الأولية =====
    int sampledPoints = 0;

    // [A] كتلة لومينانس
    int luminanceCandidates = 0;
    double sumCX = 0, sumCY = 0;
    double blobMinX = 1.0, blobMaxX = 0.0, blobMinY = 1.0, blobMaxY = 0.0;

    // [B] تدرج عضوي (Sobel)
    int organicGradientPixels = 0;
    int hardEdgePixels = 0; // حواف حادة جداً (شاشة، كيبورد)

    // [D] انتروبيا محلية
    int entropyBuckets = 0;
    final brightnessBins = List<int>.filled(8, 0); // 8 مجموعات لقياس التوزيع

    // [E] تباين رأسي مقابل أفقي
    int verticalGradSum = 0;
    int horizontalGradSum = 0;

    for (int r = 1; r < sampleRows - 1; r++) {
      final py = startY + r * step;
      final prevPy = py - step;
      final nextPy = py + step;

      if (prevPy < 0 || nextPy >= height) continue;

      final rowOffset = py * yRowStride;
      final prevRowOffset = prevPy * yRowStride;
      final nextRowOffset = nextPy * yRowStride;

      for (int c = 1; c < sampleCols - 1; c++) {
        final px = startX + c * step;
        final prevPx = px - step;
        final nextPx = px + step;

        if (prevPx < 0 || nextPx >= width) continue;

        final idx = rowOffset + px;
        final idxLeft = rowOffset + prevPx;
        final idxRight = rowOffset + nextPx;
        final idxUp = prevRowOffset + px;
        final idxDown = nextRowOffset + px;

        if (idx >= yPlane.length || idxRight >= yPlane.length ||
            idxLeft < 0 || idxDown >= yPlane.length || idxUp < 0) continue;

        final center = yPlane[idx] & 0xFF;
        final left = yPlane[idxLeft] & 0xFF;
        final right = yPlane[idxRight] & 0xFF;
        final up = yPlane[idxUp] & 0xFF;
        final down = yPlane[idxDown] & 0xFF;

        sampledPoints++;
        brightnessBins[(center ~/ 32).clamp(0, 7)]++;

        // [B] تدرج سوبل بسيط
        final gx = (right - left).abs();
        final gy = (down - up).abs();
        final gradMag = gx + gy;

        verticalGradSum += gy;
        horizontalGradSum += gx;

        if (gradMag > 18 && gradMag < 130) {
          organicGradientPixels++;
        } else if (gradMag >= 130) {
          hardEdgePixels++;
        }

        // [A] تمييز مناطق اللومينانس المحتملة (ليست ظلاماً تاماً أو بياضاً متوهجاً)
        if (center >= 38 && center <= 228) {
          final localContrast = (center - ((left + right + up + down) ~/ 4)).abs();
          if (localContrast >= 6) {
            luminanceCandidates++;
            final normX = px / width;
            final normY = py / height;
            sumCX += normX;
            sumCY += normY;
            if (normX < blobMinX) blobMinX = normX;
            if (normX > blobMaxX) blobMaxX = normX;
            if (normY < blobMinY) blobMinY = normY;
            if (normY > blobMaxY) blobMaxY = normY;
          }
        }
      }
    }

    if (sampledPoints < 30) return const HandPresenceResult.noHand('INSUFFICIENT_SAMPLES');

    // ===== [A] فحص كثافة الكتلة النشطة =====
    final double luminanceRatio = luminanceCandidates / sampledPoints;
    if (luminanceRatio < 0.06) {
      return const HandPresenceResult.noHand('NO_HAND'); // المشهد فارغ أو معتم
    }

    // ===== [B] فحص التدرج العضوي مقابل الحواف الهندسية الحادة =====
    final double organicRatio = organicGradientPixels / sampledPoints;
    final double hardEdgeRatio = hardEdgePixels / sampledPoints;

    // الكيبورد والشاشة لها حواف حادة كثيرة (hardEdge > 15%)
    if (hardEdgeRatio > 0.15) {
      return const HandPresenceResult.noHand('NON_ORGANIC_TEXTURE');
    }

    // الجدار والورقة البيضاء لها تدرج عضوي ضئيل جداً
    if (organicRatio < 0.05) {
      return const HandPresenceResult.noHand('FLAT_UNIFORM_SURFACE');
    }

    // ===== [C] فحص الشكل الهندسي للكتلة (Morphological Blob Check) =====
    if (luminanceCandidates < 80) {
      return const HandPresenceResult.noHand('BLOB_TOO_SPARSE');
    }

    final blobW = blobMaxX - blobMinX;
    final blobH = blobMaxY - blobMinY;

    // اليد لها حجم نسبي معقول — لا صغيرة جداً ولا تملأ الكادر كله
    if (blobW < 0.10 || blobH < 0.10) {
      return const HandPresenceResult.noHand('BLOB_TOO_SMALL');
    }
    if (blobW > 0.90 || blobH > 0.90) {
      return const HandPresenceResult.noHand('BLOB_TOO_LARGE');
    }

    // نسبة العرض إلى الارتفاع — اليد وأصابعها (مضمومة أو مفرودة) في نطاق معقول
    if (blobH < 0.001) return const HandPresenceResult.noHand('DEGENERATE_BLOB');
    final aspect = blobW / blobH;
    if (aspect < 0.20 || aspect > 2.8) {
      return const HandPresenceResult.noHand('INVALID_BLOB_ASPECT');
    }

    // ===== [D] فحص الانتروبيا المحلية (Local Brightness Entropy) =====
    // سطح ملساء وحيد (جدار، ورقة) تتركز كل بياناته في bin أو اثنين
    int nonZeroBins = 0;
    int maxBinCount = 0;
    for (final b in brightnessBins) {
      if (b > 0) nonZeroBins++;
      if (b > maxBinCount) maxBinCount = b;
    }
    final dominanceFactor = maxBinCount / sampledPoints;
    entropyBuckets = nonZeroBins;

    // إذا كان 70%+ من البيكسلات في نفس bin الإضاءة → سطح متجانس وليس يداً
    if (dominanceFactor > 0.70) {
      return const HandPresenceResult.noHand('UNIFORM_BRIGHTNESS_NO_HAND');
    }

    if (entropyBuckets < 3) {
      return const HandPresenceResult.noHand('LOW_BRIGHTNESS_ENTROPY');
    }

    // ===== [E] فحص التباين الرأسي (Vertical vs Horizontal Gradient Asymmetry) =====
    // الأصابع الممتدة للأعلى تعطي تباين رأسي أقوى من الأفقي.
    // الكيبورد والأثاث الأفقي: تباين أفقي غالباً أقوى أو متساوٍ
    // (هذا الشرط اختياري ولكن يُضيف طبقة تمييز إضافية)
    final double avgVert = verticalGradSum / sampledPoints;
    final double avgHoriz = horizontalGradSum / sampledPoints;
    // يُطبَّق فقط إذا كان التباين العام منخفضاً جداً (للأسطح المشبوهة)
    if (avgVert < 3.0 && avgHoriz < 3.0) {
      return const HandPresenceResult.noHand('MINIMAL_SPATIAL_ACTIVITY');
    }

    // ===== الثقة النهائية المجمعة =====
    // نحتاج أن يكون organicRatio و luminanceRatio و entropy جميعها بمستوى جيد
    final double scoreOrganic = (organicRatio / 0.30).clamp(0.0, 1.0);
    final double scoreLuminance = (luminanceRatio / 0.25).clamp(0.0, 1.0);
    final double scoreEntropy = ((entropyBuckets - 2) / 5.0).clamp(0.0, 1.0);

    final double rawScore = (scoreOrganic * 0.45) + (scoreLuminance * 0.30) + (scoreEntropy * 0.25);

    if (rawScore < _minConfidenceToPass) {
      return HandPresenceResult.noHand('MULTI_CUE_SCORE_TOO_LOW: ${rawScore.toStringAsFixed(2)}');
    }

    // نطبّع النتيجة ونضمن أنها دائماً فوق 0.85 عند النجاح (لأن الشروط صارمة جداً)
    final double finalConf = (0.83 + rawScore * 0.15).clamp(0.83, 0.97);

    final palmX = luminanceCandidates > 0 ? (sumCX / luminanceCandidates) : 0.5;
    final palmY = luminanceCandidates > 0 ? (sumCY / luminanceCandidates) : 0.5;

    return HandPresenceResult(
      hasHand: true,
      confidence: finalConf,
      minX: blobMinX,
      maxX: blobMaxX,
      minY: blobMinY,
      maxY: blobMaxY,
      palmX: palmX,
      palmY: palmY,
      reason: 'HAND_DETECTED',
    );
  }
}
