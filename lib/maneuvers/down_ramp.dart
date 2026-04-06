import '../models.dart';
import '../esp32_service.dart';

final downRampManeuver = Maneuver(
  name: 'Wheeling Down Ramps',
  type: ManeuverType.downRamp,
  steps: [
    ManeuverStep(
      title: 'Setup',
      text: 'Lean back! Keep weight over the rear wheels to prevent forward tipping.',
      imagePath: 'assets/images/rampdown1.png',
    ),
    ManeuverStep(
      title: 'Control Speed',
      text: 'Slide handrims smoothly through hands at 1 o\'clock. Speed of descent is controlled by how tightly you grip.',
      imagePath: 'assets/images/rampdown2.png',
    ),
    ManeuverStep(
      title: 'Maintain Path',
      text: 'Stay in the middle of the ramp.',
      imagePath: 'assets/images/rampdown2.png',
    ),
  ],
  evaluator: (List<WheelData> pool) {
    if (pool.length < 5) return TestEvaluation(0, ['Not enough data. Ensure you capture the full descent.']);

    double score = 100.0;
    final List<String> feedback = [];

    // 1. WRONG WAY DETECTION (Auto-Score 0)
    final wrongWayCount = pool.where((d) => d.signedR < -0.3 || d.signedL < -0.3).length;
    if (wrongWayCount > (pool.length * 0.5)) {
      return TestEvaluation(0, ['You traveled backward (up the ramp) the entire time!']);
    } else if (wrongWayCount > 2) {
      score -= (wrongWayCount * 8).clamp(0, 40);
      feedback.add('You momentarily rolled backward. Keep your momentum moving steadily down the ramp.');
    }

    final avgIncline = pool.map((d) => d.pitchDeg.abs()).reduce((a, b) => a + b) / pool.length;
    final peakSpeed = pool.map((d) => d.speedMS).reduce((a, b) => a > b ? a : b);
    final avgSpeed = pool.map((d) => d.speedMS).reduce((a, b) => a + b) / pool.length;

    // 2. DYNAMIC SPEED BENCHMARK
    double maxSafeSpeed = 1.2;
    if (avgIncline > 8.0) {
      maxSafeSpeed = 0.5;
    } else if (avgIncline > 5.0) {
      maxSafeSpeed = 0.7;
    } else if (avgIncline > 2.0) {
      maxSafeSpeed = 0.9;
    }

    if (peakSpeed > maxSafeSpeed) {
      double overage = peakSpeed - maxSafeSpeed;
      score -= (overage * 80).clamp(0, 50);
      feedback.add('UNSAFE SPEED: Reached ${peakSpeed.toStringAsFixed(2)} m/s. Grip the handrims tighter to slow down!');
    } else if (avgSpeed < 0.05 && wrongWayCount == 0) {
      score -= 20;
      feedback.add('Movement was incredibly slow or completely stopped.');
    }

    // 3. INCONSISTENT SPEED (Up to 30 pts off)
    final startIdx = (pool.length * 0.2).floor();
    final endIdx = (pool.length * 0.8).floor();
    if (endIdx > startIdx && endIdx <= pool.length) {
      final midPool = pool.sublist(startIdx, endIdx);
      final midAvgSpeed = midPool.map((d) => d.speedMS).reduce((a, b) => a + b) / midPool.length;
      double totalDev = 0.0;
      for (final d in midPool) { totalDev += (d.speedMS - midAvgSpeed).abs(); }
      final avgDeviation = totalDev / midPool.length;
      
      if (avgDeviation > 0.15) {
        score -= (avgDeviation * 120).clamp(0, 30);
        feedback.add('Descent speed varied too much. Slide handrims smoothly for a steady speed.');
      }
    }

    // 4. DRIFT / NOT CENTERED (-20 pts)
    final avgAbsYawRate = pool.map((d) => d.yawRateDps.abs()).reduce((a, b) => a + b) / pool.length;
    if (avgAbsYawRate > 2.5) {
      score -= (avgAbsYawRate * 3.0).clamp(0, 20);
      feedback.add('You drifted side-to-side. Apply friction evenly to both wheels to stay centered.');
    }

    int finalScore = score.clamp(0, 100).round();
    if (finalScore < 50) {
      feedback.removeWhere((msg) => msg.contains('Great') || msg.contains('Excellent'));
    }

    return TestEvaluation(finalScore, feedback.take(3).toList());
  }
);