# دليل تدريب YOLO Hand Pose Model لتطبيق إشارة

## الهدف

تدريب نموذج YOLO11n-pose يقوم بعمليتين في آنٍ واحد:
1. **Hand Detection** — كشف اليد الحقيقية
2. **21 Hand Keypoints** — استخراج النقاط بترتيب MediaPipe

---

## المتطلبات

```bash
pip install ultralytics opencv-python numpy
pip install tensorflow  # للتصدير إلى TFLite
```

للتدريب على GPU:
```bash
pip install torch torchvision --index-url https://download.pytorch.org/whl/cu121
```

---

## هيكل المجلدات

```
training/
├── hand.yaml                    # إعداد Dataset
├── setup_dataset.py             # إعداد وتنزيل Dataset
├── auto_label.py                # Auto-Annotation للـ Custom Frames
├── train.py                     # Fine-Tuning Pipeline
├── hard_negative_mining.py      # Hard Negative Mining
├── export_model.py              # تصدير إلى TFLite
├── validate_model.py            # التحقق من النموذج
│
├── datasets/
│   └── hand-keypoints/
│       ├── train/
│       │   ├── images/          # ← ضع صور التدريب هنا
│       │   └── labels/          # ← Annotations بتنسيق YOLO
│       └── val/
│           ├── images/          # ← ضع صور التحقق هنا
│           └── labels/
│
├── collect_negatives/           # ← صور Hard Negatives (لا يد)
│   ├── walls/
│   ├── screens/
│   ├── keyboards/
│   └── ...
│
├── custom_frames/               # ← مقاطع فيديو مخصصة
│   ├── video_person1.mp4
│   ├── video_person2.mp4
│   └── ...
│
└── runs/
    └── train/
        └── hand_pose_v1/
            └── weights/
                └── best.pt      # ← أفضل نموذج مُدرَّب
```

---

## الخطوات بالتفصيل

### الخطوة 1: جمع البيانات

#### 1أ. صور Hand Negatives (لا يد) ← **الأهم**

ضع صوراً وفيديوهات **بدون يد** في مجلد `collect_negatives/`:

| النوع | الأمثلة |
|---|---|
| جدار | ألوان مختلفة، ملمس مختلف |
| شاشة | حاسوب، تلفزيون، هاتف |
| لوحة مفاتيح | كيبورد عربي/إنجليزي |
| ملابس | قمصان، جاكيتات، بنطلونات |
| أثاث | طاولة، كرسي، سرير |
| صور/ملصقات | لا سيما إذا فيها أشكال تشبه الأصابع |
| أجسام | أقلام، زجاجات، أصابع حلوى |
| خلفيات مزدحمة | أسواق، شوارع، طبيعة |

**الكمية الموصى بها:** 500-2000 صورة (أكثر أفضل)

> ⚠️ هذه الصور هي **أهم جزء في التدريب** — النموذج يجب أن يتعلم:
> **هذا ليس يد → Ignore**

#### 1ب. مقاطع فيديو مخصصة

ضع مقاطع الفيديو في مجلد `custom_frames/`:
- زوايا مختلفة (أمام، جانب، أعلى، أسفل)
- إضاءة مختلفة (قوية، ضعيفة، ملونة)
- يد يمين
- يد يسار
- يدين معاً
- أصابع مفتوحة وإشارات مختلفة
- حركة سريعة
- مسافات مختلفة
- عدة أشخاص مختلفين

**الكمية:** 10-15 مقطع فيديو (كل مقطع 30-60 ثانية)

---

### الخطوة 2: إعداد Dataset

```bash
cd training/

# تنزيل Ultralytics Dataset + إضافة Custom Frames + Hard Negatives
python setup_dataset.py \
    --negatives ./collect_negatives \
    --custom-videos ./custom_frames \
    --frame-step 10
```

---

### الخطوة 3: Auto-Labeling

```bash
# تعليم Custom Frames تلقائياً
python auto_label.py \
    --images ./datasets/hand-keypoints/train/images \
    --model yolo11n-pose.pt \
    --conf 0.40
```

ثم افتح `needs_review.json` وراجع الصور التي لها ثقة منخفضة.

---

### الخطوة 4: التدريب

#### على Google Colab (مجاناً — موصى به):

افتح [Google Colab](https://colab.research.google.com/) وشغّل:

```python
# في Colab
!pip install ultralytics

from google.colab import files

# ارفع ملف hand.yaml وزيب Dataset
# ثم شغّل:
from ultralytics import YOLO
model = YOLO("yolo11n-pose.pt")
model.train(
    data="hand.yaml",
    epochs=150,
    imgsz=640,
    batch=16,
    device=0,
)
```

#### على الجهاز المحلي:

```bash
# GPU
python train.py --device 0 --epochs 150

# CPU (بطيء جداً — للاختبار فقط)
python train.py --device cpu --epochs 10 --batch 4
```

---

### الخطوة 5: Hard Negative Mining

بعد التدريب، شغّل النموذج على Hard Negatives:

```bash
python hard_negative_mining.py \
    --model ./runs/train/hand_pose_v1/weights/best.pt \
    --negatives ./collect_negatives \
    --iterations 2
```

ثم أعد التدريب:
```bash
python train.py \
    --model ./runs/train/hand_pose_v1/weights/best.pt \
    --epochs 30 \
    --name hand_pose_v2
```

---

### الخطوة 6: التحقق من النموذج

```bash
python validate_model.py \
    --model ./runs/train/hand_pose_v1/weights/best.pt \
    --positives ./test_hands \
    --negatives ./collect_negatives
```

معايير القبول:
- ✅ False Positive Rate < 2%
- ✅ True Positive Rate > 90%
- ✅ Valid Keypoints (≥15/21) > 85%

---

### الخطوة 7: التصدير

```bash
python export_model.py \
    --model ./runs/train/hand_pose_v1/weights/best.pt \
    --quantize float16 \
    --flutter-dir ../
```

النموذج سيُنسخ تلقائياً إلى `../assets/models/hand_pose.tflite`

---

## بعد التصدير

```bash
cd ..
flutter pub get
flutter run
```

---

## اختبار النموذج في التطبيق

### اختبار Hard Negative (60 ثانية):
وجّه الكاميرا للأشياء التالية — **يجب ألا تظهر أي نقطة:**
- [ ] حائط
- [ ] شاشة
- [ ] لوحة مفاتيح
- [ ] ملابس
- [ ] أثاث
- [ ] صور

### اختبار Positive:
- [ ] يد واحدة → يظهر Bounding Box + 21 نقطة
- [ ] أخرج اليد → تختفي النقاط فوراً
- [ ] يد يمين
- [ ] يد يسار
- [ ] يدين معاً
- [ ] حركة سريعة
- [ ] إضاءة ضعيفة
- [ ] خلفية مزدحمة

---

## ترتيب الـ 21 Keypoint

| رقم | الاسم |
|-----|-------|
| 0 | wrist |
| 1 | thumb_cmc |
| 2 | thumb_mcp |
| 3 | thumb_ip |
| 4 | thumb_tip |
| 5 | index_mcp |
| 6 | index_pip |
| 7 | index_dip |
| 8 | index_tip |
| 9 | middle_mcp |
| 10 | middle_pip |
| 11 | middle_dip |
| 12 | middle_tip |
| 13 | ring_mcp |
| 14 | ring_pip |
| 15 | ring_dip |
| 16 | ring_tip |
| 17 | pinky_mcp |
| 18 | pinky_pip |
| 19 | pinky_dip |
| 20 | pinky_tip |

---

## مرجع الملفات المُعدَّلة في Flutter

| الملف | التغيير |
|---|---|
| `lib/services/yolo_hand_service.dart` | **جديد** — محرك YOLO TFLite |
| `lib/services/hand_pose_service.dart` | **جديد** — يستبدل LandmarkService |
| `lib/controllers/camera_controller.dart` | تعديل — يستخدم HandPoseService |
| `lib/main.dart` | تعديل — يُنشئ HandPoseService |
| `lib/services/landmark_service.dart` | **موقوف** — محفوظ للمرجع |
| `lib/services/palm_detector_service.dart` | **موقوف** — محفوظ للمرجع |
| `assets/models/hand_pose.tflite` | **مطلوب** — النموذج المُدرَّب |
