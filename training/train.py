"""
train.py — Pipeline تدريب YOLO11n-pose على 21 Hand Keypoints
=============================================================
يقوم بـ:
1. Fine-tuning YOLO11n-pose على Hand-Keypoints Dataset
2. تطبيق Data Augmentation المناسب (تدوير، قص، تغيير إضاءة)
3. حفظ أفضل نموذج تلقائياً (best.pt)
4. تقييم النموذج على Validation Set
5. إنشاء تقرير الأداء

الاستخدام:
    python train.py                  # تدريب كامل
    python train.py --epochs 50      # تدريب أقل
    python train.py --resume         # استئناف من آخر checkpoint

متطلبات:
    pip install ultralytics

للتدريب على GPU (موصى به):
    pip install torch torchvision --index-url https://download.pytorch.org/whl/cu121
"""

import argparse
import os
from pathlib import Path
import time


def train_model(
    data_yaml: str,
    model_name: str,
    epochs: int,
    imgsz: int,
    batch: int,
    device: str,
    resume: bool,
    project: str,
    name: str,
):
    """
    تدريب YOLO11n-pose على Hand Keypoints Dataset.

    Args:
        data_yaml: مسار ملف hand.yaml
        model_name: اسم النموذج الابتدائي (pretrained)
        epochs: عدد epochs التدريب
        imgsz: حجم الصورة للتدريب
        batch: حجم الـ Batch
        device: الجهاز (0=GPU, cpu)
        resume: استئناف من آخر checkpoint
        project: مجلد حفظ النتائج
        name: اسم تجربة التدريب
    """
    from ultralytics import YOLO

    print("=" * 60)
    print("🚀 بدء تدريب YOLO11n-pose على Hand Keypoints")
    print("=" * 60)
    print(f"   النموذج الابتدائي: {model_name}")
    print(f"   Epochs: {epochs}")
    print(f"   Image Size: {imgsz}")
    print(f"   Batch Size: {batch}")
    print(f"   Device: {device}")
    print(f"   Dataset: {data_yaml}")
    print("=" * 60)

    # تحميل النموذج الابتدائي (Pretrained Transfer Learning)
    if resume:
        # استئناف من آخر checkpoint
        last_checkpoint = Path(project) / name / "weights" / "last.pt"
        if last_checkpoint.exists():
            model = YOLO(str(last_checkpoint))
            print(f"[INFO] استئناف من: {last_checkpoint}")
        else:
            print(f"[WARNING] لم يُعثر على checkpoint، سيبدأ من {model_name}")
            model = YOLO(model_name)
    else:
        model = YOLO(model_name)

    start_time = time.time()

    # تدريب النموذج
    results = model.train(
        data=data_yaml,
        epochs=epochs,
        imgsz=imgsz,
        batch=batch,
        device=device,
        project=project,
        name=name,

        # ========================
        # Data Augmentation
        # ========================
        hsv_h=0.015,       # تغيير Hue (إضاءة مختلفة)
        hsv_s=0.7,         # تغيير Saturation
        hsv_v=0.4,         # تغيير Value (سطوع)
        degrees=30.0,      # تدوير ±30 درجة
        translate=0.1,     # إزاحة ±10%
        scale=0.5,         # تكبير/تصغير ±50%
        shear=5.0,         # قص ±5 درجة
        perspective=0.0,   # لا Perspective (قد يُشوّه الـ Keypoints)
        flipud=0.0,        # لا قلب رأسي (يُشوّه الأصابع)
        fliplr=0.5,        # قلب أفقي 50% (يد يمين → يد يسار)
        mosaic=0.5,        # Mosaic Augmentation 50%
        mixup=0.1,         # MixUp خفيف
        copy_paste=0.0,    # لا Copy-Paste

        # ========================
        # تحسينات التدريب
        # ========================
        optimizer="AdamW",   # AdamW أفضل من SGD للـ Fine-tuning
        lr0=0.001,           # Learning Rate ابتدائية
        lrf=0.01,            # نسبة Learning Rate النهائية
        warmup_epochs=3,     # Warmup
        cos_lr=True,         # Cosine LR Schedule
        weight_decay=0.0005,

        # ========================
        # مقاييس الأداء
        # ========================
        plots=True,          # رسم منحنيات التدريب
        save=True,
        save_period=10,      # حفظ كل 10 epochs
        patience=20,         # Early Stopping بعد 20 epoch بدون تحسن

        # ========================
        # إعدادات خاصة بالـ Pose
        # ========================
        pose=12.0,           # وزن Keypoint Loss (أعلى = تركيز أكبر على الـ Keypoints)
        kobj=2.0,            # وزن Keypoint Object Loss

        # ========================
        # Verbose
        # ========================
        verbose=True,
    )

    elapsed = time.time() - start_time
    print(f"\n✅ انتهى التدريب في {elapsed/60:.1f} دقيقة")

    # مسار أفضل نموذج
    best_model = Path(project) / name / "weights" / "best.pt"
    if best_model.exists():
        print(f"\n📦 أفضل نموذج محفوظ في: {best_model}")
        print_metrics(results)
    else:
        print(f"[WARNING] لم يُحفظ النموذج في: {best_model}")

    return best_model


def print_metrics(results):
    """طباعة مقاييس الأداء النهائية."""
    try:
        print("\n📊 مقاييس الأداء النهائية:")
        box_map50 = results.results_dict.get("metrics/mAP50(B)", 0)
        box_map = results.results_dict.get("metrics/mAP50-95(B)", 0)
        pose_map50 = results.results_dict.get("metrics/mAP50(P)", 0)
        pose_map = results.results_dict.get("metrics/mAP50-95(P)", 0)

        print(f"   Hand Detection mAP@50:    {box_map50:.3f}")
        print(f"   Hand Detection mAP@50-95: {box_map:.3f}")
        print(f"   Pose Keypoints mAP@50:    {pose_map50:.3f}")
        print(f"   Pose Keypoints mAP@50-95: {pose_map:.3f}")

        # تقييم الجودة
        if pose_map50 > 0.90:
            print("\n✅ الأداء ممتاز — جاهز للـ Export")
        elif pose_map50 > 0.75:
            print("\n⚠️  الأداء جيد — يمكن Export مع مزيد من التدريب")
        else:
            print("\n❌ الأداء ضعيف — يحتاج مزيد من البيانات أو التدريب")
    except Exception as e:
        print(f"[WARNING] لم يمكن طباعة المقاييس: {e}")


def main():
    parser = argparse.ArgumentParser(description="تدريب YOLO11n-pose على Hand Keypoints")
    parser.add_argument("--data", type=str, default="hand.yaml",
                        help="مسار ملف Dataset YAML")
    parser.add_argument("--model", type=str, default="yolo11n-pose.pt",
                        help="النموذج الابتدائي (pretrained)")
    parser.add_argument("--epochs", type=int, default=150,
                        help="عدد Epochs التدريب")
    parser.add_argument("--imgsz", type=int, default=640,
                        help="حجم الصورة للتدريب")
    parser.add_argument("--batch", type=int, default=16,
                        help="حجم Batch (-1 = تلقائي حسب الذاكرة)")
    parser.add_argument("--device", type=str, default="0",
                        help="الجهاز: 0=GPU, cpu=CPU, mps=Apple Silicon")
    parser.add_argument("--resume", action="store_true",
                        help="استئناف من آخر checkpoint")
    parser.add_argument("--project", type=str, default="./runs/train",
                        help="مجلد حفظ نتائج التدريب")
    parser.add_argument("--name", type=str, default="hand_pose_v1",
                        help="اسم تجربة التدريب")
    args = parser.parse_args()

    best_model = train_model(
        data_yaml=args.data,
        model_name=args.model,
        epochs=args.epochs,
        imgsz=args.imgsz,
        batch=args.batch,
        device=args.device,
        resume=args.resume,
        project=args.project,
        name=args.name,
    )

    print("\n" + "="*60)
    print("الخطوة التالية:")
    print(f"   1. python hard_negative_mining.py --model {best_model}")
    print(f"   2. python export_model.py --model {best_model}")
    print("="*60)


if __name__ == "__main__":
    main()
