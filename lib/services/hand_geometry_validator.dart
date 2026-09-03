import 'dart:math';
import 'package:ishara/models/landmarks_model.dart';

class GeometryValidationResult {
  final bool isValid;
  final String reason;

  const GeometryValidationResult({
    required this.isValid,
    required this.reason,
  });

  const GeometryValidationResult.valid()
      : isValid = true,
        reason = 'Valid hand geometry';

  const GeometryValidationResult.invalid(this.reason) : isValid = false;
}

/// طبقة التحقق الهندسي والتشريحي الصارم لمعالم اليد (Hand Geometry Validation Layer)
/// تتحقق من صحة ومطابقة النقاط الـ 21 للمعايير التشريحية لليد البشرية، وترفض أي أجسام عشوائية
class HandGeometryValidator {
  /// التحقق الشامل من البنية الهندسية للنقاط الـ 21
  static GeometryValidationResult validate(HandLandmarks landmarks) {
    final lm = landmarks.landmarks;
    if (lm.length != 21) {
      return const GeometryValidationResult.invalid('Rejected: Incomplete landmarks count (not 21)');
    }

    // 1. فحص حدود الحجم والأبعاد (Bounding Box & Aspect Ratio)
    double minX = 1.0, maxX = 0.0, minY = 1.0, maxY = 0.0;
    for (final pt in lm) {
      if (pt.x < minX) minX = pt.x;
      if (pt.x > maxX) maxX = pt.x;
      if (pt.y < minY) minY = pt.y;
      if (pt.y > maxY) maxY = pt.y;
    }

    final width = maxX - minX;
    final height = maxY - minY;

    if (width < 0.08 || height < 0.08) {
      return const GeometryValidationResult.invalid('Rejected: Hand span too small (degenerate artifact)');
    }

    if (width > 0.90 || height > 0.95) {
      return const GeometryValidationResult.invalid('Rejected: Hand span unnaturally oversized');
    }

    final aspectRatio = width / height;
    if (aspectRatio < 0.18 || aspectRatio > 2.8) {
      return const GeometryValidationResult.invalid('Rejected: Unnatural bounding aspect ratio');
    }

    // 2. فحص موضع المعصم وقاعدة الكف (Wrist to Middle MCP)
    final wrist = lm[0];
    final middleMcp = lm[9];
    final palmLength = _dist(wrist, middleMcp);

    if (palmLength < 0.06 || palmLength > 0.65) {
      return const GeometryValidationResult.invalid('Rejected: Invalid palm dimension (Wrist-MCP distance)');
    }

    // 3. فحص الترتيب التشريحي لقواعد الأصابع (MCP Knuckle Arch)
    // قواعد الأصابع: الإبهام (1)، السبابة (5)، الوسطى (9)، البنصر (13)، الخنصر (17)
    final thumbCmc = lm[1];
    final indexMcp = lm[5];
    final ringMcp = lm[13];
    final pinkyMcp = lm[17];

    final dIndexMiddle = _dist(indexMcp, middleMcp);
    final dMiddleRing = _dist(middleMcp, ringMcp);
    final dRingPinky = _dist(ringMcp, pinkyMcp);

    // المسافات بين المفاصل المتجاورة لا يمكن أن تكون صفرية أو متداخلة بشكل متطابق
    if (dIndexMiddle < 0.015 || dMiddleRing < 0.015 || dRingPinky < 0.015) {
      return const GeometryValidationResult.invalid('Rejected: Collapsed MCP joints (knuckles overlap)');
    }

    // المسافة الإجمالية لعرض قاعدة الكف
    final palmSpan = _dist(indexMcp, pinkyMcp);
    if (palmSpan < 0.04 || palmSpan > 0.55) {
      return const GeometryValidationResult.invalid('Rejected: Invalid palm base width (Index MCP to Pinky MCP)');
    }

    // 4. فحص نسب أطوال عظام الأصابع (Finger Segment Proportions)
    // السبابة (5..8), الوسطى (9..12), البنصر (13..16), الخنصر (17..20)
    const fingers = [
      [5, 6, 7, 8, 'Index'],
      [9, 10, 11, 12, 'Middle'],
      [13, 14, 15, 16, 'Ring'],
      [17, 18, 19, 20, 'Pinky'],
    ];

    for (final f in fingers) {
      final mcp = lm[f[0] as int];
      final pip = lm[f[1] as int];
      final dip = lm[f[2] as int];
      final tip = lm[f[3] as int];
      final name = f[4] as String;

      final lenProximal = _dist(mcp, pip);
      final lenMiddle = _dist(pip, dip);
      final lenDistal = _dist(dip, tip);

      if (lenProximal < 0.008 || lenMiddle < 0.006 || lenDistal < 0.006) {
        return GeometryValidationResult.invalid('Rejected: Zero-length bone segment in $name finger');
      }

      // في التشريح البشري، العظم الطرفي (Distal) لا يتجاوز ضعف طول العظم القاعدي (Proximal)
      if (lenDistal > lenProximal * 2.2) {
        return GeometryValidationResult.invalid('Rejected: Unnatural bone ratio in $name finger');
      }
    }

    // 5. فحص الإبهام (Thumb: 1 -> 2 -> 3 -> 4)
    final thumbMcp = lm[2];
    final thumbIp = lm[3];
    final thumbTip = lm[4];

    final lenThumb1 = _dist(thumbCmc, thumbMcp);
    final lenThumb2 = _dist(thumbMcp, thumbIp);
    final lenThumb3 = _dist(thumbIp, thumbTip);

    if (lenThumb1 < 0.008 || lenThumb2 < 0.006 || lenThumb3 < 0.006) {
      return const GeometryValidationResult.invalid('Rejected: Collapsed thumb segment');
    }

    // اجتازت اليد جميع الفحوصات الهندسية والتشريحية بنجاح
    return const GeometryValidationResult.valid();
  }

  static double _dist(HandLandmark a, HandLandmark b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    final dz = a.z - b.z;
    return sqrt(dx * dx + dy * dy + dz * dz);
  }
}
