class GlossResult {
  final String gloss;
  final String arabicText;
  final bool isFromCache;
  final int totalLatencyMs;
  final int firstTokenMs;
  final double tokensPerSec;
  final DateTime timestamp;

  const GlossResult({
    required this.gloss,
    required this.arabicText,
    this.isFromCache = false,
    this.totalLatencyMs = 0,
    this.firstTokenMs = 0,
    this.tokensPerSec = 0.0,
    required this.timestamp,
  });

  @override
  String toString() {
    return 'GlossResult(gloss: "$gloss", arabicText: "$arabicText", cached: $isFromCache, latency: ${totalLatencyMs}ms, speed: ${tokensPerSec.toStringAsFixed(1)} t/s)';
  }
}
