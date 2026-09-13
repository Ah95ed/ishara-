"""
auto_label.py — Auto-Annotation للـ Custom Frames باستخدام YOLO Pretrained
==========================================================================
يقوم بـ:
1. تشغيل نموذج YOLO11n-pose المُدرَّب على Hand-Keypoints على الصور غير المُعلَّمة
2. حفظ Annotations بتنسيق YOLO Pose (.txt)
3. رفع Annotations بـ confidence منخفض للمراجعة اليدوية
4. إنشاء تقرير يوضح الصور التي تحتاج مراجعة

الاستخدام:
    python auto_label.py --images ./datasets/hand-keypoints/train/images
                         --model yolo11n-pose.pt
                         --conf 0.40

متطلبات:
    pip install ultralytics opencv-python
"""

import argparse
import json
from pathlib import Path
import shutil


def auto_label_images(
    images_dir: Path,
    labels_dir: Path,
    model_path: str,
    conf_threshold: float = 0.40,
    review_conf: float = 0.55,
):
    """
    تشغيل Auto-Labeling على مجلد صور.

    Args:
        images_dir: مجلد الصور المراد تعليمها
        labels_dir: مجلد الـ Labels الناتجة
        model_path: مسار النموذج (.pt)
        conf_threshold: الحد الأدنى لقبول Detection (< هذا = تجاهل)
        review_conf: Detections بثقة < هذا تُعلَّم بـ لون تحذيري في التقرير
    """
    from ultralytics import YOLO

    model = YOLO(model_path)
    labels_dir.mkdir(parents=True, exist_ok=True)

    image_extensions = {'.jpg', '.jpeg', '.png', '.bmp', '.webp'}
    images = [
        p for p in images_dir.rglob('*')
        if p.suffix.lower() in image_extensions
        and not (labels_dir / f"{p.stem}.txt").exists()  # تخطي المُعلَّمة مسبقاً
    ]

    if not images:
        print("[INFO] لا توجد صور تحتاج Auto-Labeling.")
        return

    print(f"[INFO] Auto-Labeling لـ {len(images)} صورة...")

    stats = {
        "total": len(images),
        "labeled": 0,
        "skipped_low_conf": 0,
        "no_hand": 0,
        "needs_review": [],
    }

    for i, img_path in enumerate(images):
        if (i + 1) % 50 == 0:
            print(f"   تقدم: {i+1}/{len(images)}")

        results = model(str(img_path), conf=conf_threshold, verbose=False)
        result = results[0]

        label_path = labels_dir / f"{img_path.stem}.txt"

        # إذا لا يوجد detection → label فارغ (Hard Negative Auto-Detection)
        if result.boxes is None or len(result.boxes) == 0:
            label_path.write_text("")
            stats["no_hand"] += 1
            continue

        img_w = result.orig_shape[1]
        img_h = result.orig_shape[0]

        lines = []
        max_conf = 0.0

        for box_idx in range(len(result.boxes)):
            box = result.boxes[box_idx]
            conf = float(box.conf[0])

            if conf < conf_threshold:
                continue

            max_conf = max(max_conf, conf)

            # BBox بتنسيق YOLO (normalized center x, center y, w, h)
            x1, y1, x2, y2 = box.xyxy[0].tolist()
            cx = ((x1 + x2) / 2) / img_w
            cy = ((y1 + y2) / 2) / img_h
            bw = (x2 - x1) / img_w
            bh = (y2 - y1) / img_h

            # Keypoints
            line = f"0 {cx:.6f} {cy:.6f} {bw:.6f} {bh:.6f}"

            if result.keypoints is not None and box_idx < len(result.keypoints):
                kpts = result.keypoints[box_idx]
                kpts_data = kpts.data[0]  # shape: [21, 3] (x, y, visibility)

                for kpt in kpts_data:
                    kx = float(kpt[0]) / img_w
                    ky = float(kpt[1]) / img_h
                    kv = float(kpt[2])

                    # تطبيع visibility: إذا كان 0 → لا يد/مخفي
                    kv_flag = 2 if kv > 0.5 else (1 if kv > 0.2 else 0)
                    line += f" {kx:.6f} {ky:.6f} {kv_flag}"
            else:
                # لا Keypoints متاحة
                line += " 0 0 0" * 21

            lines.append(line)

        if lines:
            label_path.write_text("\n".join(lines))
            stats["labeled"] += 1

            # وضع علامة للمراجعة اليدوية إذا الثقة منخفضة
            if max_conf < review_conf:
                stats["needs_review"].append({
                    "image": str(img_path),
                    "max_conf": round(max_conf, 3),
                })
        else:
            label_path.write_text("")
            stats["skipped_low_conf"] += 1

    # تقرير النتائج
    print(f"\n📊 نتائج Auto-Labeling:")
    print(f"   إجمالي: {stats['total']}")
    print(f"   مُعلَّمة: {stats['labeled']}")
    print(f"   لا يد (Empty Label): {stats['no_hand']}")
    print(f"   ثقة منخفضة (تجاهل): {stats['skipped_low_conf']}")
    print(f"   تحتاج مراجعة: {len(stats['needs_review'])}")

    # حفظ قائمة الصور للمراجعة
    if stats["needs_review"]:
        review_path = images_dir.parent / "needs_review.json"
        review_path.write_text(
            json.dumps(stats["needs_review"], ensure_ascii=False, indent=2)
        )
        print(f"\n⚠️  صور للمراجعة اليدوية: {review_path}")
        print("   افتح هذه الصور وتحقق من صحة الـ Annotations قبل التدريب.")


def validate_labels(images_dir: Path, labels_dir: Path):
    """التحقق من صحة Labels الموجودة."""
    print("\n[INFO] التحقق من Labels...")

    image_extensions = {'.jpg', '.jpeg', '.png', '.bmp', '.webp'}
    images = [p for p in images_dir.rglob('*') if p.suffix.lower() in image_extensions]

    issues = []
    for img in images:
        lbl = labels_dir / f"{img.stem}.txt"

        if not lbl.exists():
            issues.append(f"❌ لا يوجد label: {img.name}")
            continue

        content = lbl.read_text().strip()
        if not content:
            continue  # صورة بدون يد — صحيح

        for line_num, line in enumerate(content.splitlines()):
            parts = line.split()
            # تنسيق صحيح: class cx cy w h + 21*(x y v) = 5 + 63 = 68 عنصر
            if len(parts) != 68:
                issues.append(
                    f"⚠️  {img.name} سطر {line_num+1}: {len(parts)} عنصر (المطلوب 68)"
                )

    if issues:
        print(f"[WARNING] {len(issues)} مشكلة في Labels:")
        for issue in issues[:20]:
            print(f"   {issue}")
        if len(issues) > 20:
            print(f"   ... و {len(issues) - 20} مشكلة أخرى")
    else:
        print("[OK] جميع Labels صحيحة ✅")


def main():
    parser = argparse.ArgumentParser(description="Auto-Labeling لـ Hand Pose Dataset")
    parser.add_argument("--images", type=str,
                        default="./datasets/hand-keypoints/train/images",
                        help="مجلد الصور المراد تعليمها")
    parser.add_argument("--model", type=str, default="yolo11n-pose.pt",
                        help="نموذج YOLO للـ Auto-Annotation")
    parser.add_argument("--conf", type=float, default=0.40,
                        help="الحد الأدنى للثقة للقبول")
    parser.add_argument("--review-conf", type=float, default=0.55,
                        help="Detections بثقة أقل توضع في قائمة المراجعة")
    parser.add_argument("--validate-only", action="store_true",
                        help="التحقق فقط بدون labeling")
    args = parser.parse_args()

    images_dir = Path(args.images)
    labels_dir = images_dir.parent.parent / "labels" / images_dir.parent.name
    # التنقل الصحيح: images/../labels = train/labels أو val/labels
    labels_dir = images_dir.parent / "labels"

    if not images_dir.exists():
        print(f"[ERROR] مجلد الصور غير موجود: {images_dir}")
        return

    if args.validate_only:
        validate_labels(images_dir, labels_dir)
        return

    auto_label_images(
        images_dir=images_dir,
        labels_dir=labels_dir,
        model_path=args.model,
        conf_threshold=args.conf,
        review_conf=args.review_conf,
    )

    validate_labels(images_dir, labels_dir)


if __name__ == "__main__":
    main()
