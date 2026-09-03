"""
hard_negative_mining.py — Hard Negative Mining للحد من False Positives
======================================================================
يقوم بـ:
1. تشغيل النموذج على مجلد صور Hard Negatives (لا يد)
2. جمع الصور التي أعطى فيها النموذج False Positive (تعرّف على يد خطأ)
3. حفظها كـ Hard Negatives في Dataset
4. إعادة التدريب (Fine-Tuning على الـ Failures)
5. تكرار حتى تنخفض False Positives بشكل ملحوظ

الاستخدام:
    python hard_negative_mining.py --model ./runs/train/hand_pose_v1/weights/best.pt
                                   --negatives ./collect_negatives
                                   --iterations 3

الفكرة:
    النموذج يخطئ على بعض الأشياء (ملابس، كيبورد، شاشة...)
    نجمع هذه الأخطاء → نضيفها كـ No-Hand Samples → نعيد التدريب
    الهدف: تعليم النموذج "هذا ليس يد"
"""

import argparse
import shutil
from pathlib import Path
import json


def run_hard_negative_mining(
    model_path: str,
    negatives_dir: Path,
    output_dir: Path,
    conf_threshold: float = 0.25,
    max_per_iteration: int = 500,
) -> int:
    """
    اكتشاف False Positives على صور Hard Negatives.

    Returns:
        عدد الصور التي تعرّف فيها النموذج على يد خطأ (False Positives)
    """
    from ultralytics import YOLO

    model = YOLO(model_path)

    image_extensions = {'.jpg', '.jpeg', '.png', '.bmp', '.webp'}
    neg_images = [
        p for p in negatives_dir.rglob('*')
        if p.suffix.lower() in image_extensions
    ]

    if not neg_images:
        print(f"[INFO] لا توجد صور في {negatives_dir}")
        return 0

    print(f"[INFO] اختبار النموذج على {len(neg_images)} صورة Hard Negative...")

    false_positives = []
    output_dir.mkdir(parents=True, exist_ok=True)

    for i, img_path in enumerate(neg_images[:max_per_iteration]):
        if (i + 1) % 100 == 0:
            print(f"   تقدم: {i+1}/{min(len(neg_images), max_per_iteration)}")

        results = model(str(img_path), conf=conf_threshold, verbose=False)
        result = results[0]

        # إذا النموذج اكتشف يد في صورة لا يد فيها → False Positive
        if result.boxes is not None and len(result.boxes) > 0:
            max_conf = float(result.boxes.conf.max())
            false_positives.append({
                "image": str(img_path),
                "detected_conf": round(max_conf, 3),
                "detections": len(result.boxes),
            })

            # حفظ نسخة من الصورة لـ Dataset Hard Negatives
            dst_img = output_dir / f"hn_{img_path.name}"
            shutil.copy2(img_path, dst_img)

            # Label فارغ (لا يد)
            dst_lbl_dir = output_dir.parent / "labels" / output_dir.name
            dst_lbl_dir.mkdir(parents=True, exist_ok=True)
            (dst_lbl_dir / f"hn_{img_path.stem}.txt").write_text("")

    # تقرير False Positives
    print(f"\n📊 نتائج Hard Negative Mining:")
    print(f"   إجمالي الصور المُختبرة: {min(len(neg_images), max_per_iteration)}")
    print(f"   False Positives (يد وهمية): {len(false_positives)}")

    false_positive_rate = len(false_positives) / min(len(neg_images), max_per_iteration)
    print(f"   معدل الخطأ: {false_positive_rate:.1%}")

    if false_positives:
        # حفظ تقرير
        report_path = negatives_dir / "false_positives_report.json"
        report_path.write_text(
            json.dumps({
                "false_positive_rate": false_positive_rate,
                "total_tested": min(len(neg_images), max_per_iteration),
                "false_positives": sorted(
                    false_positives, key=lambda x: x["detected_conf"], reverse=True
                )
            }, ensure_ascii=False, indent=2)
        )
        print(f"\n📄 تقرير محفوظ: {report_path}")

        # أعلى الـ False Positives
        print("\n🔍 أعلى 5 False Positives (بأعلى ثقة):")
        for fp in sorted(false_positives, key=lambda x: x["detected_conf"], reverse=True)[:5]:
            print(f"   {Path(fp['image']).name}: conf={fp['detected_conf']}")

        if false_positive_rate < 0.05:
            print("\n✅ معدل الخطأ < 5% — النموذج جيد!")
        elif false_positive_rate < 0.15:
            print("\n⚠️  معدل الخطأ مقبول — يُنصح بإعادة تدريب واحدة")
        else:
            print("\n❌ معدل الخطأ مرتفع — يجب إعادة التدريب مع Hard Negatives")

    return len(false_positives)


def integrate_hard_negatives_to_dataset(
    mined_dir: Path,
    dataset_dir: Path,
):
    """
    دمج الصور المكتشفة كـ False Positives في Training Dataset.
    """
    image_extensions = {'.jpg', '.jpeg', '.png', '.bmp', '.webp'}
    mined_images = [
        p for p in mined_dir.rglob('*')
        if p.suffix.lower() in image_extensions
    ]

    if not mined_images:
        print("[INFO] لا توجد Hard Negatives جديدة للدمج.")
        return

    target_img_dir = dataset_dir / "train" / "images"
    target_lbl_dir = dataset_dir / "train" / "labels"
    target_img_dir.mkdir(parents=True, exist_ok=True)
    target_lbl_dir.mkdir(parents=True, exist_ok=True)

    added = 0
    for img in mined_images:
        dst_img = target_img_dir / img.name
        dst_lbl = target_lbl_dir / f"{img.stem}.txt"

        if not dst_img.exists():
            shutil.copy2(img, dst_img)
            dst_lbl.write_text("")  # Label فارغ = لا يد
            added += 1

    print(f"[OK] تم إضافة {added} Hard Negative جديد للـ Dataset.")


def main():
    parser = argparse.ArgumentParser(description="Hard Negative Mining")
    parser.add_argument("--model", type=str, required=True,
                        help="مسار النموذج (best.pt)")
    parser.add_argument("--negatives", type=str, default="./collect_negatives",
                        help="مجلد صور Hard Negatives")
    parser.add_argument("--dataset", type=str,
                        default="./datasets/hand-keypoints",
                        help="مجلد Dataset للتدريب")
    parser.add_argument("--conf", type=float, default=0.25,
                        help="الحد الأدنى للثقة لاعتبار Detection خطأ")
    parser.add_argument("--iterations", type=int, default=1,
                        help="عدد دورات Mining")
    parser.add_argument("--max-images", type=int, default=500,
                        help="أقصى عدد صور لاختبارها لكل دورة")
    args = parser.parse_args()

    negatives_dir = Path(args.negatives)
    dataset_dir = Path(args.dataset)

    if not negatives_dir.exists():
        print(f"[ERROR] مجلد Hard Negatives غير موجود: {negatives_dir}")
        return

    for iteration in range(args.iterations):
        print(f"\n{'='*60}")
        print(f"دورة Hard Negative Mining: {iteration + 1}/{args.iterations}")
        print(f"{'='*60}")

        # مجلد للحفظ
        mined_output = negatives_dir / f"mined_iter_{iteration + 1}"

        # تشغيل Mining
        fp_count = run_hard_negative_mining(
            model_path=args.model,
            negatives_dir=negatives_dir,
            output_dir=mined_output,
            conf_threshold=args.conf,
            max_per_iteration=args.max_images,
        )

        if fp_count == 0:
            print("\n✅ لا توجد False Positives — النموذج ممتاز!")
            break

        # دمج Hard Negatives في Dataset
        integrate_hard_negatives_to_dataset(mined_output, dataset_dir)

        if iteration < args.iterations - 1:
            print("\n[INFO] يجب إعادة التدريب الآن:")
            print(f"   python train.py --data hand.yaml --model {args.model} --epochs 30")
            print(f"   ثم أعد تشغيل: python hard_negative_mining.py ...")

    print("\n" + "="*60)
    print("الخطوة التالية:")
    print("   python export_model.py --model <best.pt>")
    print("="*60)


if __name__ == "__main__":
    main()
