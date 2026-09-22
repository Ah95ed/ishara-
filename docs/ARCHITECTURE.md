# Ishara Architecture: Real-Time Native Vision & Recognition Engine

## 1. High-Level Architecture Overview

Ishara utilizes a hybrid architecture combining a high-performance **Native Android (Kotlin)** vision engine with a reactive **Flutter** UI shell.

```
                      ┌────────────────────────────────────────┐
                      │            Flutter UI Shell            │
                      │  (HomeView, Buttons, Status, Results)  │
                      └──────────────────┬─────────────────────┘
                                         │ MethodChannel (Commands: start, stop, switch, getMetrics)
                                         │ EventChannel (Stream: state, progress, result, report)
                                         ▼
                      ┌────────────────────────────────────────┐
                      │      IsharaFlutterBridge (Kotlin)      │
                      └──────────────────┬─────────────────────┘
                                         │
        ┌────────────────────────────────┼────────────────────────────────┐
        ▼                                ▼                                ▼
┌─────────────────┐             ┌─────────────────┐             ┌──────────────────┐
│ CameraX Engine  │             │ Landmark Engine │             │  PlatformView    │
│                 │             │                 │             │  (Native Preview │
│ • Probe FPS/Res │             │ • Hands (21+21) │             │   Texture/View)  │
│ • Keep Latest   │             │ • Lips (19)     │             └──────────────────┘
│ • Thread Pool   │             │ • Pose/Body(25) │
└───────┬─────────┘             └────────┬────────┘
        │ YUV420 ImageProxy              │
        ▼ (Zero/Low copy)                ▼
┌─────────────────────────────────────────────────┐
│        KeypointMapper86 + Raw Landmark          │
└───────────────────────┬─────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────┐
│        MotionAnalyzer (Body-Relative)           │
│ • Shoulder Center Anchor & Width Scale          │
│ • Adaptive Baseline EMA + Jitter Rejection      │
└───────────────────────┬─────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────┐
│        SignSegmenter (State Machine)            │
│ • IDLE ➔ STARTING ➔ SIGNING ➔ ENDING ➔ PROC     │
│ • Hysteresis (startThreshold > endThreshold)    │
│ • Pre-roll (250-350ms) + Post-roll (150-250ms)  │
│ • Quiet Duration (250-450ms)                    │
│ • Safety Timeout (12s max)                      │
└───────────────────────┬─────────────────────────┘
                        │ Active Frames [N, 86, 2] (Raw & Norm)
                        ▼
┌─────────────────────────────────────────────────┐
│        TemporalResampler                        │
│ • Natural speed: N frames (e.g. 25 or 40)       │
│ • Linear time interpolation (t) ➔ 128 frames    │
│ • Preserves original segment metadata           │
└───────────────────────┬─────────────────────────┘
                        │ Tensor [1, 128, 86, 2]
                        ▼
┌─────────────────────────────────────────────────┐
│        IsharaModelRunner (TFLite Background)    │
│ • Validation: Float32, NaN=0, Inf=0             │
│ • Runs TFLite Interpreter ➔ [1, 29, 684]        │
└───────────────────────┬─────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────┐
│        CtcDecoder + VocabularyLoader            │
│ • Greedy Argmax ➔ Collapse Consecutive          │
│ • Remove Blank (0) ➔ Map to Arabic Glosses      │
└───────────────────────┬─────────────────────────┘
                        │
                        ▼
             Final Gloss Event to Flutter
```

---

## 2. Subsystem Responsibilities

### 2.1 Native Android (Kotlin) Responsibilities
1. **Camera Acquisition (`native/camera`)**:
   - CameraX integration with Camera2 interoperability.
   - Dynamic hardware capability probe (`CameraCapabilityProbe`) for FPS ranges and resolutions.
   - FPS & resolution selection strategy (`CameraFpsSelector`).
   - `STRATEGY_KEEP_ONLY_LATEST` with zero-leak `ImageProxy.close()` in `try/finally` (`CameraFrameAnalyzer`).
2. **Landmark Extraction (`native/vision`)**:
   - Background execution on `visionExecutor` (no UI blocking).
   - Google ML Kit Pose Detection & Face Mesh Detection.
   - Strict 86-keypoint mapping (`KeypointMapper86`):
     - `0..20`: Right Hand (21)
     - `21..41`: Left Hand (21)
     - `42..60`: Lips (19)
     - `61..85`: Body/Head (25)
   - 5-step normalization matching `datasetv2.py` (`KeypointNormalizer`).
   - Carry-forward imputation for missing points.
   - Coverage analysis (`FrameQualityAnalyzer`).
3. **Motion Analysis & Segmentation (`native/sign`)**:
   - Body-relative motion using shoulder center anchor and width scale (`MotionAnalyzer`).
   - Adaptive baseline EMA during `IDLE` state.
   - 5-state machine (`SignSegmenter`): `IDLE` $\rightarrow$ `STARTING` $\rightarrow$ `SIGNING` $\rightarrow$ `ENDING` $\rightarrow$ `PROCESSING`.
   - Hysteresis thresholds (`startThreshold > endThreshold`).
   - Circular Pre-roll buffer (250–350ms) to capture motion onset.
   - Post-roll buffer (150–250ms) to capture final handshape.
4. **Temporal Resampling (`native/sign`)**:
   - Uniform linear interpolation on time axis $t \in [0, 1]$ (`TemporalResampler`).
   - Resamples arbitrary segment length $N$ into fixed $128 \times 86 \times 2$.
5. **Model Inference & CTC Decoding (`native/model`)**:
   - Pre-allocated direct byte buffers for input `[1, 128, 86, 2]` and output `[1, 29, 684]`.
   - Dedicated single-thread model runner with `AtomicBoolean` preventing overlapping inference (`IsharaModelRunner`).
   - Input tensor validation: Float32, NaN=0, Inf=0.
   - Greedy CTC decoder with consecutive collapse and blank ID removal (`CtcDecoder`).
   - Vocabulary loader mapping IDs to Arabic glosses (`VocabularyLoader`).
6. **Flutter Bridge & Preview (`native/bridge`)**:
   - Command channel (`MethodChannel`) and event stream (`EventChannel`).
   - PlatformView hosting CameraX `PreviewView` (`NativeCameraPreviewView`).

### 2.2 Flutter Responsibilities
1. **User Interface & Presentation**:
   - Simple, clean camera preview via PlatformView.
   - Status indicators (`جاهز`, `جاري أداء الإشارة...`, `جاري التحليل...`).
   - Final gloss display (`بنت - اخ - صغير`).
   - Copy diagnostic report button and new sign button.
2. **Navigation & Settings**:
   - Camera lens switching.
   - Legacy Flutter Vision toggle for benchmark comparison.
   - Diagnostic inspection screens.
