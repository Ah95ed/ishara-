# Architectural Decision Records (ADRs)

This document records the foundational architectural decisions for Ishara, documenting the technical context, alternatives considered, and rationale.

---

### ADR-01: Move Camera & Real-Time Vision Pipeline to Native Android (Kotlin)
- **Status**: Accepted
- **Context**: The previous pipeline transferred raw YUV camera frames from Flutter plugins across the Dart MethodChannel, introducing memory copies, garbage collection pressure, and queue backlogs that capped processing at 10–12 FPS.
- **Decision**: Transition CameraX capture, ImageAnalysis, Landmark extraction, Motion analysis, Temporal resampling, TFLite inference, and CTC decoding into Native Kotlin.
- **Consequences**:
  - Zero raw image copies to Dart.
  - Camera can run at 30 or 60 FPS smoothly.
  - Dart receives only lightweight discrete state changes and string glosses.

---

### ADR-02: Model Architecture & Weights Frozen (No Retraining, No Z)
- **Status**: Accepted
- **Context**: `ishara_model.tflite` is a trained sequence model with input shape `[1, 128, 86, 2]` and output shape `[1, 29, 684]`.
- **Decision**: Keep the exact model weights, input tensor shape, and class vocabulary unchanged.
- **Rationale**: The model's training contract was defined in `datasetv2.py`. Introducing a Z-axis, modifying tensor dimensions, or retraining would invalidate validation baselines.

---

### ADR-03: 86-Keypoint Layout Frozen
- **Status**: Accepted
- **Context**: The model expects 86 keypoints in a precise sequential order.
- **Decision**: Lock the landmark ordering strictly to:
  - `0..20`: Right Hand (21 points)
  - `21..41`: Left Hand (21 points)
  - `42..60`: Lips (19 sorted face mesh indices)
  - `61..85`: Upper Body & Head (25 pose landmarks)
- **Rationale**: Guaranteed compatibility with training data feature extraction.

---

### ADR-04: Fixed 128-Frame Temporal Resampling for Natural Speed Signing
- **Status**: Accepted
- **Context**: Previously, the system forced users to wait until 128 camera frames had accumulated in a ring buffer, adding 3–4 seconds of unnatural delay for fast or natural signs.
- **Decision**: Do not wait for 128 camera frames. When a natural sign completes (e.g. 25 frames across 900ms), perform linear temporal interpolation along the time axis $t \in [0, 1]$ to resample the $N$ frames into exactly 128 frames for TFLite.
- **Consequences**: Fast signs are recognized immediately; temporal fidelity is maintained without artificial latency.

---

### ADR-05: One-Handed Signs Support
- **Status**: Accepted
- **Context**: Arabic Sign Language contains many single-handed signs (e.g., right hand only or left hand only).
- **Decision**: An active sign is valid if either hand is present and moving (`activeHandMotion = max(rhMotion, lhMotion)`). A missing second hand or missing lips will never automatically reject a sign.

---

### ADR-06: Latest-Frame-Wins Strategy (`STRATEGY_KEEP_ONLY_LATEST`)
- **Status**: Accepted
- **Context**: Deep processing queues create compounding latency backlogs when detectors lag behind camera delivery.
- **Decision**: Configure CameraX `ImageAnalysis` with `STRATEGY_KEEP_ONLY_LATEST`. Every new camera frame immediately replaces any unhandled pending frame. Stale frames exceeding 150ms are dropped.
- **Consequences**: Guarantees lowest possible end-to-end latency and zero memory leaks.

---

### ADR-07: Independent Tracking of Camera FPS, Detector FPS, and Model Rate
- **Status**: Accepted
- **Context**: Conflating camera capture rate with detector throughput causes confusion in performance profiling.
- **Decision**: Separately measure and report:
  1. `cameraDeliveredFps`: Raw frames produced by CameraX.
  2. `landmarkProcessedFps`: Frames successfully processed by ML Kit.
  3. `modelInferenceRate`: Completed inferences per second.
- **Rationale**: High camera FPS provides fresher temporal samples; the model only needs to infer upon completed sign segments.

---

### ADR-08: Body-Relative Motion for Shake Invariance
- **Status**: Accepted
- **Context**: Camera shake from holding a smartphone can trigger false motion detection if screen-space coordinates are used directly.
- **Decision**: Compute hand motion relative to the midpoint of the shoulders normalized by shoulder width ($p_{rel} = \frac{p_{wrist} - p_{anchor}}{||shoulder_R - shoulder_L||}$).
- **Consequences**: Natural camera jitter is filtered out, preventing false sign starts.
