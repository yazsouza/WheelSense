import '../models.dart';
import '../esp32_service.dart';

final turnRightManeuver = Maneuver(
  name: 'Turning Right',
  type: ManeuverType.turnRight,
  steps: [
    ManeuverStep(
      title: 'Asymmetrical Push',
      text: 'Push harder on the left wheel to initiate the turn.',
    ),
    ManeuverStep(
      title: 'Follow Through',
      text: 'Maintain forward momentum while curving right.',
    ),
  ],
  evaluator: (List<WheelData> pool) {
    if (pool.isEmpty) return TestEvaluation(0, ['No data recorded.']);

    double score = 100.0;
    List<String> feedback = [];

    if (pool.length < 5) {
      return TestEvaluation(0, ['Not enough data collected. Try again.']);
    }

    double avgYawRate = pool.map((d) => d.yawRateDps).reduce((a, b) => a + b) / pool.length;
    double avgAbsYawRate = pool.map((d) => d.yawRateDps.abs()).reduce((a, b) => a + b) / pool.length;
    double wobble = pool.map((d) => (d.yawRateDps - avgYawRate).abs()).reduce((a, b) => a + b) / pool.length;

    // FIX: PEAK TILT SENSITIVITY
    final maxPitch = pool.map((d) => d.pitchDeg.abs()).reduce((a, b) => a > b ? a : b);

    // 1. TURN DETECTION (Right is Negative Yaw)
    if (avgYawRate >= -1.0) {
      score -= 30;
      feedback.add('Not enough right turning detected. Push more on the left wheel.');
    } else {
      feedback.add('Good right turning motion detected (${avgYawRate.abs().toStringAsFixed(1)} deg/s).');
    }

    // 2. WOBBLE DETECTION
    if (wobble > 4.5) {
      score -= 15;
      feedback.add('Turn was uneven. Try smoother continuous pushes.');
    } else {
      feedback.add('Smooth turning motion.');
    }

    // 3. TOO STRAIGHT PENALTY
    if (avgAbsYawRate < 1.5) {
      score -= 20;
      feedback.add('Movement was mostly straight instead of turning.');
    }

    // 4. FIX: TILT CHECK (Harsher Peak Sensitivity)
    if (maxPitch > 4.0) {
      score -= 20;
      feedback.add('Wheelchair tilted during turn. Keep your weight forward for stability.');
    }

    return TestEvaluation(score.clamp(0, 100).round(), feedback.take(3).toList());
  },
);