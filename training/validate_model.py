"""
validate_model.py — التحقق من أداء النموذج قبل دمجه في Flutter
==============================================================
اختبار:
1. False Positive Rate على صور Hard Negatives
2. True Positive Rate على صور يد حقيقية
3. التحقق من صحة الـ 21 Keypoints

الاستخدام:
    python validate_model.py --model best.pt
                             --positives ./test_hands/
                             --negatives ./collect_negatives/
"""

import argparse
from pathlib import Path
import json


def run_validation(
    model_path: str,
    positives_dir: Path,
    negatives_dir: Path,
    conf_threshold: float = 0.50,
):
    """تشغيل الاختبار الكامل."""
    from ultralytics import YOLO

    model = YOLO(model_path)
    image_extensions = {'.jpg', '.jpeg', '.png', '.bmp', '.webp'}

    print("=" * 60)
    print("🧪 اختبار النموذج قبل التكامل مع Flutter")
    print("=" * 60)

    # ===== اختبار 1: False Positive على صور لا يد فيها =====
    if negatives_dir.exists():
        neg_images = [p for p in negatives_dir.rglob('*') if p.suffix.lower() in image_extensions]
        print(f"\n[Test 1] False Positive Test: {len(neg_images)} صورة Hard Negative")

        fp_count = 0
        fp_details = []
        for img in neg_images:
            results = model(str(img), conf=conf_threshold, verbose=False)
            if results[0].boxes is not None and len(results[0].boxes) > 0:
                fp_count += 1
                fp_details.append(str(img.name))

        fp_rate = fp_count / max(len(neg_images), 1)
        print(f"   False Positives: {fp_count}/{len(neg_images)} ({fp_rate:.1%})")

        if fp_rate == 0:
            print("   ✅ ممتاز — لا false positives!")
        elif fp_rate < 0.02:
            print("   ✅ جيد جداً — أقل من 2%")
        elif fp_rate < 0.05:
            print("   ⚠️  مقبول — أقل من 5%")
        else:
            print("   ❌ مرتفع — يحتاج مزيد من Hard Negative Mining")
            print("   أعلى False Positives:")
            for fp in fp_details[:5]:
                print(f"      {fp}")

    # ===== اختبار 2: True Positive على صور يد حقيقية =====
    if positives_dir.exists():
        pos_images = [p for p in positives_dir.rglob('*') if p.suffix.lower() in image_extensions]
        print(f"\n[Test 2] True Positive Test: {len(pos_images)} صورة يد حقيقية")

        tp_count = 0
        kp_valid_count = 0

        for img in pos_images:
            results = model(str(img), conf=conf_threshold, verbose=False)
            if results[0].boxes is not None and len(results[0].boxes) > 0:
                tp_count += 1

                # التحقق من الـ Keypoints
                if results[0].keypoints is not None:
                    kpts = results[0].keypoints[0].data[0]  # [21, 3]
                    visible_kpts = sum(1 for k in kpts if float(k[2]) > 0.3)
                    if visible_kpts >= 15:
                        kp_valid_count += 1

        tp_rate = tp_count / max(len(pos_images), 1)
        kp_rate = kp_valid_count / max(len(pos_images), 1)
        print(f"   True Positives: {tp_count}/{len(pos_images)} ({tp_rate:.1%})")
        print(f"   Valid Keypoints (≥15): {kp_valid_count}/{len(pos_images)} ({kp_rate:.1%})")

        if tp_rate > 0.90 and kp_rate > 0.85:
            print("   ✅ النموذج جاهز للدمج!")
        elif tp_rate > 0.75:
            print("   ⚠️  النموذج مقبول — يمكن التحسين لاحقاً")
        else:
            print("   ❌ النموذج يحتاج مزيداً من التدريب")

    print("\n" + "="*60)


def main():
    parser = argparse.ArgumentParser(description="التحقق من أداء النموذج")
    parser.add_argument("--model", type=str, required=True)
    parser.add_argument("--positives", type=str, default="./test_hands",
                        help="مجلد صور يد حقيقية للاختبار")
    parser.add_argument("--negatives", type=str, default="./collect_negatives",
                        help="مجلد صور Hard Negatives")
    parser.add_argument("--conf", type=float, default=0.50)
    args = parser.parse_args()

    run_validation(
        model_path=args.model,
        positives_dir=Path(args.positives),
        negatives_dir=Path(args.negatives),
        conf_threshold=args.conf,
    )


if __name__ == "__main__":
    main()
