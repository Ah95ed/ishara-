"""
setup_dataset.py — إعداد وتنزيل Hand Keypoints Dataset
=======================================================
يقوم بـ:
1. تنزيل Ultralytics Hand-Keypoints Dataset (آلاف الصور المُعلَّمة)
2. دمجه مع Custom Frames في مجلد datasets/hand-keypoints
3. إنشاء ملفات labels فارغة لصور Hard Negatives
4. التحقق من سلامة Dataset قبل التدريب

الاستخدام:
    python setup_dataset.py [--negatives ./collect_negatives]
"""

import argparse
import shutil
import os
from pathlib import Path
import random


def download_ultralytics_dataset():
    """تنزيل Hand-Keypoints Dataset من Ultralytics."""
    try:
        from ultralytics.utils.downloads import download
        from ultralytics import settings
        import yaml

        print("[INFO] جارٍ تنزيل Ultralytics Hand-Keypoints Dataset...")

        # استخدام YOLO لتنزيل Dataset تلقائياً عبر training run وهمي
        from ultralytics import YOLO
        model = YOLO("yolo11n-pose.pt")

        # تنزيل Dataset فقط بدون تدريب
        model.train(
            data="hand-keypoints.yaml",
            epochs=0,          # صفر epochs — تنزيل Dataset فقط
            imgsz=640,
            batch=1,
        )
        print("[OK] تم تنزيل Dataset.")

    except Exception as e:
        print(f"[WARNING] لم يتم تنزيل Dataset تلقائياً: {e}")
        print("[INFO] يمكنك تنزيله يدوياً من:")
        print("       https://universe.roboflow.com/hand-keypoints")
        print("       أو: https://github.com/hukenovs/hagrid")
        print("[INFO] ضع الصور في: training/datasets/hand-keypoints/train/images/")
        print("       والـ Labels في: training/datasets/hand-keypoints/train/labels/")


def add_negatives(negatives_dir: Path, output_base: Path, split_ratio: float = 0.15):
    """
    إضافة صور Hard Negatives (لا يد) إلى Dataset.

    الصور تُضاف مع ملفات labels فارغة (== لا detections).

    Args:
        negatives_dir: مجلد يحتوي على صور لا يد فيها
        output_base: مجلد datasets/hand-keypoints
        split_ratio: نسبة الصور التي تذهب للـ Validation (15%)
    """
    image_extensions = {'.jpg', '.jpeg', '.png', '.bmp', '.webp'}
    neg_images = [
        p for p in negatives_dir.rglob('*')
        if p.suffix.lower() in image_extensions
    ]

    if not neg_images:
        print(f"[INFO] لا توجد صور في {negatives_dir} — تخطي.")
        return

    print(f"[INFO] إضافة {len(neg_images)} صورة Hard Negative...")

    # خلط عشوائي
    random.shuffle(neg_images)
    split_idx = max(1, int(len(neg_images) * split_ratio))

    val_images = neg_images[:split_idx]
    train_images = neg_images[split_idx:]

    def copy_negative(src: Path, split: str):
        dst_img = output_base / split / "images" / f"neg_{src.name}"
        dst_lbl = output_base / split / "labels" / f"neg_{src.stem}.txt"

        shutil.copy2(src, dst_img)
        # ملف label فارغ = لا detections = NO HAND
        dst_lbl.write_text("")

    for img in train_images:
        copy_negative(img, "train")
    for img in val_images:
        copy_negative(img, "val")

    print(f"[OK] {len(train_images)} صورة للـ Train، {len(val_images)} للـ Val.")


def add_custom_frames(custom_dir: Path, output_base: Path, frame_step: int = 10):
    """
    استخراج Frames من مقاطع فيديو مخصصة وإضافتها لـ Dataset.

    تستخرج إطاراً كل `frame_step` إطار لتجنب التكرار.

    Args:
        custom_dir: مجلد يحتوي على مقاطع فيديو (.mp4, .mov, etc.)
        output_base: مجلد datasets/hand-keypoints
        frame_step: استخرج إطار كل N إطار
    """
    try:
        import cv2
    except ImportError:
        print("[ERROR] مكتبة OpenCV غير مثبتة. شغّل: pip install opencv-python")
        return

    video_extensions = {'.mp4', '.mov', '.avi', '.mkv', '.webm'}
    videos = [
        p for p in custom_dir.rglob('*')
        if p.suffix.lower() in video_extensions
    ]

    if not videos:
        print(f"[INFO] لا توجد مقاطع فيديو في {custom_dir} — تخطي.")
        return

    print(f"[INFO] استخراج Frames من {len(videos)} مقطع فيديو (كل {frame_step} إطار)...")

    output_dir = output_base / "train" / "images"
    total_extracted = 0

    for video_path in videos:
        cap = cv2.VideoCapture(str(video_path))
        frame_idx = 0
        extracted = 0

        while cap.isOpened():
            ret, frame = cap.read()
            if not ret:
                break

            if frame_idx % frame_step == 0:
                out_name = f"custom_{video_path.stem}_{frame_idx:06d}.jpg"
                out_path = output_dir / out_name
                cv2.imwrite(str(out_path), frame, [cv2.IMWRITE_JPEG_QUALITY, 95])
                extracted += 1

            frame_idx += 1

        cap.release()
        print(f"   {video_path.name}: {extracted} إطار مستخرج")
        total_extracted += extracted

    print(f"[OK] إجمالي الإطارات المستخرجة: {total_extracted}")
    print(f"[INFO] يجب الآن تشغيل auto_label.py لإضافة Annotations لهذه الإطارات.")


def verify_dataset(base: Path) -> bool:
    """التحقق من سلامة Dataset قبل التدريب."""
    print("\n[INFO] التحقق من سلامة Dataset...")

    errors = 0
    for split in ["train", "val"]:
        img_dir = base / split / "images"
        lbl_dir = base / split / "labels"

        if not img_dir.exists():
            print(f"[ERROR] مجلد غير موجود: {img_dir}")
            errors += 1
            continue

        images = list(img_dir.glob("*.jpg")) + list(img_dir.glob("*.png")) + list(img_dir.glob("*.jpeg"))
        labels = list(lbl_dir.glob("*.txt")) if lbl_dir.exists() else []

        print(f"   {split}: {len(images)} صورة، {len(labels)} label")

        # التحقق من وجود label لكل صورة
        missing_labels = 0
        for img in images:
            lbl = lbl_dir / f"{img.stem}.txt"
            if not lbl.exists():
                missing_labels += 1

        if missing_labels > 0:
            print(f"   [WARNING] {missing_labels} صورة بدون label في {split}")

        if len(images) < 10:
            print(f"   [ERROR] عدد الصور قليل جداً في {split} ({len(images)})")
            errors += 1

    return errors == 0


def main():
    parser = argparse.ArgumentParser(description="إعداد Hand Keypoints Dataset")
    parser.add_argument("--negatives", type=str, default="./collect_negatives",
                        help="مجلد صور Hard Negatives (لا يد)")
    parser.add_argument("--custom-videos", type=str, default="./custom_frames",
                        help="مجلد مقاطع الفيديو المخصصة")
    parser.add_argument("--frame-step", type=int, default=10,
                        help="استخرج إطار كل N إطار من الفيديو")
    parser.add_argument("--skip-download", action="store_true",
                        help="تخطي تنزيل Ultralytics Dataset")
    args = parser.parse_args()

    base = Path("./datasets/hand-keypoints")
    base_train_img = base / "train" / "images"
    base_train_lbl = base / "train" / "labels"
    base_val_img   = base / "val"   / "images"
    base_val_lbl   = base / "val"   / "labels"

    for d in [base_train_img, base_train_lbl, base_val_img, base_val_lbl]:
        d.mkdir(parents=True, exist_ok=True)

    # 1. تنزيل Dataset
    if not args.skip_download:
        download_ultralytics_dataset()

    # 2. استخراج Custom Frames
    custom_dir = Path(args.custom_videos)
    if custom_dir.exists():
        add_custom_frames(custom_dir, base, frame_step=args.frame_step)

    # 3. إضافة Hard Negatives
    neg_dir = Path(args.negatives)
    if neg_dir.exists():
        add_negatives(neg_dir, base)

    # 4. التحقق
    ok = verify_dataset(base)

    if ok:
        print("\n✅ Dataset جاهز للتدريب!")
        print("   الخطوة التالية: python auto_label.py")
    else:
        print("\n⚠️  Dataset يحتاج إصلاحاً قبل التدريب.")


if __name__ == "__main__":
    main()
