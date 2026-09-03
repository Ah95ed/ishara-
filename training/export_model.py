"""
export_model.py — تصدير YOLO Hand Pose Model إلى TFLite للـ Flutter
====================================================================
يقوم بـ:
1. تصدير best.pt إلى TFLite (int8 أو float16)
2. التحقق من صحة النموذج المُصدَّر
3. نسخ النموذج إلى assets/models في مشروع Flutter
4. طباعة تعليمات الاستخدام في Flutter

الاستخدام:
    python export_model.py --model ./runs/train/hand_pose_v1/weights/best.pt
                           --flutter-dir ../
                           --quantize int8

متطلبات:
    pip install ultralytics
    pip install tensorflow  # لـ int8 quantization
"""

import argparse
import shutil
from pathlib import Path
import subprocess
import sys


def export_to_tflite(
    model_path: str,
    imgsz: int = 640,
    quantize: str = "float16",
) -> Path:
    """
    تصدير النموذج إلى TFLite.

    Args:
        model_path: مسار النموذج (.pt)
        imgsz: حجم الصورة
        quantize: نوع التكميم (float16, int8, none)

    Returns:
        مسار ملف TFLite الناتج
    """
    from ultralytics import YOLO

    model = YOLO(model_path)
    model_path = Path(model_path)

    print(f"[INFO] تصدير النموذج: {model_path}")
    print(f"   Image Size: {imgsz}×{imgsz}")
    print(f"   Quantization: {quantize}")

    # معاملات التصدير
    export_kwargs = {
        "format": "tflite",
        "imgsz": imgsz,
        "simplify": True,
        "nms": False,  # NMS يُطبَّق في Flutter
    }

    if quantize == "int8":
        export_kwargs["int8"] = True
        print("   [INFO] INT8 Quantization يتطلب وقتاً أطول...")
    elif quantize == "float16":
        export_kwargs["half"] = True

    # التصدير
    result = model.export(**export_kwargs)

    # إيجاد ملف TFLite الناتج
    tflite_path = model_path.parent / f"{model_path.stem}_saved_model" / f"{model_path.stem}_float{32 if quantize=='none' else 16 if quantize=='float16' else 8}.tflite"

    # YOLO تحفظ بأسماء مختلفة — نبحث عن الملف
    possible_names = [
        model_path.parent / f"{model_path.stem}.tflite",
        model_path.parent / f"{model_path.stem}_saved_model" / f"{model_path.stem}.tflite",
        model_path.parent / f"{model_path.stem}_saved_model" / f"{model_path.stem}_float16.tflite",
        model_path.parent / f"{model_path.stem}_saved_model" / f"{model_path.stem}_float32.tflite",
        model_path.parent / f"{model_path.stem}_saved_model" / f"{model_path.stem}_int8.tflite",
    ]

    found_tflite = None
    for p in possible_names:
        if p.exists():
            found_tflite = p
            break

    if found_tflite is None:
        # بحث موسّع
        for p in model_path.parent.rglob("*.tflite"):
            found_tflite = p
            break

    if found_tflite is None:
        print(f"[ERROR] لم يُعثر على ملف TFLite في {model_path.parent}")
        print("        تأكد من تثبيت tensorflow: pip install tensorflow")
        sys.exit(1)

    print(f"[OK] تم تصدير النموذج: {found_tflite}")
    print(f"     حجم الملف: {found_tflite.stat().st_size / 1024 / 1024:.1f} MB")

    return found_tflite


def validate_tflite(tflite_path: Path):
    """التحقق من صحة النموذج المُصدَّر."""
    try:
        import numpy as np
        import tensorflow as tf

        print(f"\n[INFO] التحقق من النموذج: {tflite_path}")

        interpreter = tf.lite.Interpreter(model_path=str(tflite_path))
        interpreter.allocate_tensors()

        input_details = interpreter.get_input_details()
        output_details = interpreter.get_output_details()

        print(f"   Input shape: {input_details[0]['shape']}")
        print(f"   Input dtype: {input_details[0]['dtype']}")
        print(f"   Outputs: {len(output_details)}")

        for i, out in enumerate(output_details):
            print(f"   Output[{i}] shape: {out['shape']}, dtype: {out['dtype']}")

        # تشغيل Inference وهمي
        input_shape = input_details[0]['shape']
        dummy_input = np.zeros(input_shape, dtype=input_details[0]['dtype'])

        if input_details[0]['dtype'] == np.float32:
            dummy_input = (dummy_input / 255.0).astype(np.float32)

        interpreter.set_tensor(input_details[0]['index'], dummy_input)
        interpreter.invoke()

        print("[OK] النموذج يعمل بشكل صحيح ✅")

        # التحقق من الـ Output shape للـ Pose
        # YOLO Pose output: [batch, num_detections, 5 + num_classes + keypoints*3]
        # لـ Hand Pose: [1, 8400, 5 + 1 + 21*3] = [1, 8400, 69]
        for i, out in enumerate(output_details):
            shape = out['shape']
            if len(shape) == 3 and shape[2] >= 68:
                print(f"   [OK] Output[{i}] يبدو صحيحاً لـ Hand Pose (shape={shape})")
                break
        else:
            print("   [WARNING] Output shape قد لا تكون صحيحة لـ 21-Keypoint Hand Pose")
            print("   تأكد من kpt_shape=[21,3] في hand.yaml")

    except ImportError:
        print("[WARNING] tensorflow غير مثبت — تخطي التحقق")
        print("          pip install tensorflow")
    except Exception as e:
        print(f"[ERROR] فشل التحقق: {e}")


def copy_to_flutter(tflite_path: Path, flutter_dir: Path):
    """نسخ النموذج إلى مشروع Flutter."""
    assets_dir = flutter_dir / "assets" / "models"
    assets_dir.mkdir(parents=True, exist_ok=True)

    target = assets_dir / "hand_pose.tflite"
    shutil.copy2(tflite_path, target)

    print(f"\n[OK] النموذج منسوخ إلى Flutter: {target}")
    print(f"     الحجم: {target.stat().st_size / 1024 / 1024:.1f} MB")

    print("\n📋 تعليمات Flutter:")
    print("   1. تأكد من وجود النموذج في: assets/models/hand_pose.tflite")
    print("   2. pubspec.yaml يحتوي على:")
    print("      assets:")
    print("        - assets/models/")
    print("   3. شغّل: flutter pub get")
    print("   4. ابن التطبيق: flutter run")


def main():
    parser = argparse.ArgumentParser(description="تصدير YOLO Hand Pose Model لـ TFLite")
    parser.add_argument("--model", type=str, required=True,
                        help="مسار النموذج (best.pt)")
    parser.add_argument("--imgsz", type=int, default=640,
                        help="حجم الصورة للتصدير")
    parser.add_argument("--quantize", choices=["none", "float16", "int8"],
                        default="float16",
                        help="نوع التكميم (float16 موصى به للموبايل)")
    parser.add_argument("--flutter-dir", type=str, default="../",
                        help="مسار مجلد مشروع Flutter")
    parser.add_argument("--skip-copy", action="store_true",
                        help="لا تنسخ إلى Flutter (احفظ محلياً فقط)")
    args = parser.parse_args()

    # 1. تصدير
    tflite_path = export_to_tflite(
        model_path=args.model,
        imgsz=args.imgsz,
        quantize=args.quantize,
    )

    # 2. تحقق
    validate_tflite(tflite_path)

    # 3. نسخ إلى Flutter
    if not args.skip_copy:
        flutter_dir = Path(args.flutter_dir)
        if flutter_dir.exists():
            copy_to_flutter(tflite_path, flutter_dir)
        else:
            print(f"[WARNING] مجلد Flutter غير موجود: {flutter_dir}")
            print(f"          النموذج محفوظ في: {tflite_path}")

    print("\n✅ اكتمل التصدير!")
    print("="*60)
    print("الخطوة التالية:")
    print("   1. تأكد من النموذج في assets/models/hand_pose.tflite")
    print("   2. flutter pub get")
    print("   3. flutter run")
    print("   4. اختبر Hard Negative Test (60 ثانية بدون يد)")
    print("="*60)


if __name__ == "__main__":
    main()
