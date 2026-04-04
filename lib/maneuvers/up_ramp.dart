import '../models.dart';
import '../esp32_service.dart';

final upRampManeuver = Maneuver(
  name: 'Wheeling Up Ramps',
  type: ManeuverType.upRamp,
  steps: [
    ManeuverStep(
      title: 'Approach',
      text: 'Wheel toward the ramp with speed and momentum.',
      imagePath: 'assets/images/rampup1.png',
    ),
    ManeuverStep(
      title: 'On Ramp',
      text: 'Lean forward! Use short, strong strokes (ARC stroke pattern) to keep hands close to the handrim and avoid rolling backward.',
      imagePath: 'assets/images/rampup2.png',
    ),
    ManeuverStep(
      title: 'Stay Centred',
      text: 'Keep the wheelchair in the middle of the ramp. Maintain forward momentum until you clear the top.',
      imagePath: 'assets/images/rampup3.png',
    ),
  ],
  evaluator: (List<WheelData> pool) {
    if (pool.length < 5) {
      return TestEvaluation(0, ['Not enough data. Make sure you complete the ramp ascent.']);
    }

    double score = 100.0;
    final List<String> feedback = [];

    final avgSpeed = pool.map((d) => d.speedMS).reduce((a, b) => a + b) / pool.length;
    final avgAbsYawRate = pool.map((d) => d.yawRateDps.abs()).reduce((a, b) => a + b) / pool.length;

    // 1. COMPLETELY WRONG WAY
    if (avgSpeed < -0.1) {
      return TestEvaluation(0, ['You moved backward down the ramp! Push forward to ascend.']);
    }

    if (avgSpeed > -0.1 && avgSpeed < 0.05) {
      return TestEvaluation(20, ['Minimal forward movement detected. Build more momentum before the ramp.']);
    }

    // 2. STRICT NO-ROLLBACK CHECK
    const double rollbackDeadband = -0.3; // Slight tolerance for sensor noise
    final rollbackCount = pool.where((d) => d.signedR < rollbackDeadband || d.signedL < rollbackDeadband).length;
    
    if (rollbackCount > (pool.length * 0.4)) {
       score -= 60;
       feedback.add('Significant backward rolling! Lean forward and push harder.');
    } else if (rollbackCount > 0) {
      score -= (rollbackCount * 8).clamp(0, 30);
      feedback.add('Backward rolling detected. Use quicker, shorter strokes to maintain forward momentum.');
    } else {
      feedback.add('Great job preventing any backward roll.');
    }

    // 3. CONSISTENT SPEED EMPHASIS (Momentum)
    final startIdx = (pool.length * 0.2).floor();
    final endIdx = (pool.length * 0.8).floor();
    
    if (endIdx > startIdx) {
      final midPool = pool.sublist(startIdx, endIdx);
      final midAvgSpeed = midPool.map((d) => d.speedMS).reduce((a, b) => a + b) / midPool.length;
      
      double totalDeviation = 0.0;
      for (final d in midPool) {
        totalDeviation += (d.speedMS - midAvgSpeed).abs();
      }
      final avgDeviation = totalDeviation / midPool.length;

      if (avgDeviation > 0.15) {
        score -= (avgDeviation * 120).clamp(0, 30);
        feedback.add('Speed fluctuated too much. Try to maintain a steady, powerful rhythm up the incline.');
      } else {
        feedback.add('Excellent job keeping a consistent momentum up the ramp.');
      }
    }

    // 4. DRIFT / STAY CENTERED
    if (avgAbsYawRate > 2.5) {
      score -= (avgAbsYawRate * 3.0).clamp(0, 20);
      feedback.add('You drifted side-to-side. Push evenly with both hands to stay centered.');
    }

    // 5. THE "ANTI-SARCASM" FILTER
    // If the score is failing, remove any "Great/Excellent" feedback so it doesn't sound confusing.
    int finalScore = score.clamp(0, 100).round();
    if (finalScore < 50) {
      feedback.removeWhere((msg) => msg.contains('Great') || msg.contains('Excellent'));
    }

    return TestEvaluation(finalScore, feedback.take(3).toList());
  },
);