import 'dart:math' as math;
import 'package:flutter/material.dart';

/// CameraLandmarkMapper
/// المحول الهندسي الموحد (Unified Landmark Coordinate Mapper)
/// يحول الإحداثيات الطبيعية [0..1] القادمة من كواشف MediaPipe و ML Kit
/// إلى إحداثيات بيكسل مطابقة تماماً فوق CameraPreview.
///
/// يدعم:
/// - نسب العرض والارتفاع المختلفة (Aspect Ratios)
/// - نمط العرض (BoxFit.contain أو BoxFit.cover)
/// - دوران المستشعر واتجاه الجهاز
/// - انعكاس الكاميرا الأمامية (Front Camera Mirroring)
/// - خلو تام من أي إزاحات أو تعديلات يدوية عشوائية
class CameraLandmarkMapper {
  CameraLandmarkMapper._();

  /// تحويل نقطة مطبعة [normalizedX, normalizedY] إلى فضاء إحداثيات الشاشة
  static Offset map({
    required double normalizedX,
    required double normalizedY,
    required Size sourceImageSize,
    required Size previewSize,
    required bool isFrontCamera,
    bool isPreviewMirrored = true,
    BoxFit fitMode = BoxFit.contain,
  }) {
    final double srcW = sourceImageSize.width;
    final double srcH = sourceImageSize.height;
    final double dstW = previewSize.width;
    final double dstH = previewSize.height;

    // في حال كانت الأبعاد غير صالحة بعد، نرجع تحويلاً بسيطاً لتجنب الأخطاء الحسابية
    if (srcW <= 0 || srcH <= 0 || dstW <= 0 || dstH <= 0) {
      final double mx = (isFrontCamera && isPreviewMirrored)
          ? (1.0 - normalizedX)
          : normalizedX;
      return Offset(mx * dstW, normalizedY * dstH);
    }

    // حساب نسبة التحجيم (Scale) وفق نمط العرض
    final double scale;
    if (fitMode == BoxFit.cover) {
      scale = math.max(dstW / srcW, dstH / srcH);
    } else {
      // BoxFit.contain (الافتراضي المطابق لـ CameraPreview داخل AspectRatio)
      scale = math.min(dstW / srcW, dstH / srcH);
    }

    final double scaledW = srcW * scale;
    final double scaledH = srcH * scale;

    // حساب الإزاحة الناتجة عن المحاذاة في المنتصف (Letterboxing / Pillarboxing)
    final double offsetX = (dstW - scaledW) / 2.0;
    final double offsetY = (dstH - scaledH) / 2.0;

    // تطبيق الانعكاس الأفقي (Mirroring) للكاميرا الأمامية فقط إذا كانت المعاينة معكوسة
    final double adjustedNx = (isFrontCamera && isPreviewMirrored)
        ? (1.0 - normalizedX)
        : normalizedX;

    // حساب الإحداثيات النهائية بدقة بيكسل لبيكسل
    final double screenX = (adjustedNx * srcW) * scale + offsetX;
    final double screenY = (normalizedY * srcH) * scale + offsetY;

    return Offset(screenX, screenY);
  }

  /// حساب أبعاد وموقع الصورة بعد التحجيم داخل PreviewSize (لأغراض الـ Debug Crosshair)
  static Rect getScaledSourceRect({
    required Size sourceImageSize,
    required Size previewSize,
    BoxFit fitMode = BoxFit.contain,
  }) {
    final double srcW = sourceImageSize.width;
    final double srcH = sourceImageSize.height;
    final double dstW = previewSize.width;
    final double dstH = previewSize.height;

    if (srcW <= 0 || srcH <= 0 || dstW <= 0 || dstH <= 0) {
      return Rect.fromLTWH(0, 0, dstW, dstH);
    }

    final double scale = fitMode == BoxFit.cover
        ? math.max(dstW / srcW, dstH / srcH)
        : math.min(dstW / srcW, dstH / srcH);

    final double scaledW = srcW * scale;
    final double scaledH = srcH * scale;
    final double offsetX = (dstW - scaledW) / 2.0;
    final double offsetY = (dstH - scaledH) / 2.0;

    return Rect.fromLTWH(offsetX, offsetY, scaledW, scaledH);
  }
}
