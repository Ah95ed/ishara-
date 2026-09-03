import 'package:flutter/material.dart';
import 'package:ishara/models/landmarks_model.dart';

/// لوحة تشخيص وعرض الـ 21 نقطة
///
/// عند عدم وجود يد:
/// Hands: 0
///
/// عند وجود يد:
/// Hands: 1
/// Landmarks: 21
/// Point 0: x, y, z
/// ...
/// Point 20: x, y, z
class HandLandmarksDebugPanel extends StatelessWidget {
  final HandLandmarks? landmarks;
  final bool rawHandDetected;
  final double handDetectorConfidence;
  final double mediaPipePresenceConfidence;
  final double trackingConfidence;
  final int frameId;
  final int resultFrameId;
  final bool isStaleResult;
  final bool geometryValid;
  final bool isRealHand;
  final String rejectionReason;
  final int consecutiveValidFrames;
  final double fps;
  final double latencyMs;
  final bool isFrontCamera;

  const HandLandmarksDebugPanel({
    super.key,
    required this.landmarks,
    required this.rawHandDetected,
    required this.handDetectorConfidence,
    required this.mediaPipePresenceConfidence,
    required this.trackingConfidence,
    required this.frameId,
    required this.resultFrameId,
    required this.isStaleResult,
    required this.geometryValid,
    required this.isRealHand,
    required this.rejectionReason,
    required this.consecutiveValidFrames,
    required this.fps,
    required this.latencyMs,
    required this.isFrontCamera,
  });

  static const List<String> _landmarkLabels = [
    'wrist',
    'thumb_cmc',
    'thumb_mcp',
    'thumb_ip',
    'thumb_tip',
    'index_mcp',
    'index_pip',
    'index_dip',
    'index_tip',
    'middle_mcp',
    'middle_pip',
    'middle_dip',
    'middle_tip',
    'ring_mcp',
    'ring_pip',
    'ring_dip',
    'ring_tip',
    'pinky_mcp',
    'pinky_pip',
    'pinky_dip',
    'pinky_tip',
  ];

  @override
  Widget build(BuildContext context) {
    final bool hasValidHand = isRealHand && landmarks != null && landmarks!.isValid;
    final int handsCount = hasValidHand ? (landmarks?.detectedHandsCount ?? 1) : 0;
    final int landmarksCount = hasValidHand ? landmarks!.landmarks.length : 0;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. شريط الحالة البسيط والمباشر
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: hasValidHand ? Colors.teal.shade800 : Colors.blueGrey.shade900,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      hasValidHand ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                      color: hasValidHand ? Colors.greenAccent : Colors.grey,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Hands: $handsCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: hasValidHand ? Colors.greenAccent : Colors.grey.shade700,
                    ),
                  ),
                  child: Text(
                    'Landmarks: $landmarksCount',
                    style: TextStyle(
                      color: hasValidHand ? Colors.greenAccent : Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 2. تفاصيل التشخيص
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Confidence: ${hasValidHand ? (landmarks!.confidence * 100).toStringAsFixed(0) : 0}%',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    color: hasValidHand ? Colors.teal.shade800 : Colors.grey.shade600,
                  ),
                ),
                Text(
                  'FPS: ${fps.toStringAsFixed(1)}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: Colors.blueGrey,
                  ),
                ),
                Text(
                  hasValidHand
                      ? 'Handedness: ${landmarks!.handedness == Handedness.right ? "Right" : "Left"}'
                      : 'Status: NO_HAND',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    color: hasValidHand ? Colors.green.shade800 : Colors.red.shade800,
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // 3. قائمة النقاط الـ 21 (Point 0 .. Point 20)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: hasValidHand
                ? ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: 21,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 12, endIndent: 12),
                    itemBuilder: (context, index) {
                      final lm = landmarks!.landmarks[index];
                      final label = index < _landmarkLabels.length
                          ? _landmarkLabels[index]
                          : 'pt_$index';
                      final isTip = index == 4 ||
                          index == 8 ||
                          index == 12 ||
                          index == 16 ||
                          index == 20;

                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 3.5),
                        color: isTip
                            ? Colors.amber.withValues(alpha: 0.08)
                            : Colors.transparent,
                        child: Row(
                          children: [
                            SizedBox(
                              width: 120,
                              child: Text(
                                'Point $index ($label):',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontFamily: 'monospace',
                                  fontWeight:
                                      isTip ? FontWeight.bold : FontWeight.w600,
                                  color: isTip
                                      ? Colors.amber.shade900
                                      : Colors.blueGrey.shade900,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Spacer(),
                            _coord('x', lm.x, Colors.red.shade700),
                            const SizedBox(width: 4),
                            _coord('y', lm.y, Colors.green.shade700),
                            const SizedBox(width: 4),
                            _coord('z', lm.z, Colors.blue.shade700),
                          ],
                        ),
                      );
                    },
                  )
                : Container(
                    height: 90,
                    alignment: Alignment.center,
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.front_hand_outlined,
                            size: 28, color: Colors.grey),
                        SizedBox(height: 6),
                        Text(
                          'No Human Hand Detected',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _coord(String axis, double val, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$axis: ${val.toStringAsFixed(3)}',
        style: TextStyle(
          fontSize: 9.5,
          fontFamily: 'monospace',
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}
