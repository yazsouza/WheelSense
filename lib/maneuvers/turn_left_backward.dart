import '../models.dart';
import '../esp32_service.dart';

final turnLeftBackwardManeuver = Maneuver(
  name: 'Turning Left (Backward)',
  type: ManeuverType.turnLeft, // You can make a new enum if you want, or reuse this
  steps: [
    ManeuverStep(
      title: '01 - Backing up',
      text: 'Shoulder check to scan for obstacles in both directions. Pull back evenly and go slow.',
    ),
    ManeuverStep(
      title: '02 - Turn',
      text: 'Inside wheel (Left): Use to steer. Outside wheel (Right): Pull to keep moving.',
    ),
    ManeuverStep(
      title: '03 - Stop',
      text: 'Lean forward and brake gently.',
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

    final maxPitch = pool.map((d) => d.pitchDeg.abs()).reduce((a, b) => a > b ? a : b);

    // 1. TURN DETECTION (Left Backward is NEGATIVE Yaw Rate)
    if (avgYawRate >= -1.0) {
      score -= 30;
      feedback.add('Not enough left backward turning detected. Pull more on the left wheel.');
    } else {
      feedback.add('Good left backward turning motion detected.');
    }

    // 2. WOBBLE DETECTION
    if (wobble > 4.5) {
      score -= 15;
      feedback.add('Turn was uneven. Try smoother continuous pulls.');
    } else {
      feedback.add('Smooth turning motion.');
    }

    // 3. TOO STRAIGHT PENALTY
    if (avgAbsYawRate < 1.5) {
      score -= 20;
      feedback.add('Movement was mostly straight instead of turning.');
    }

    // 4. TILT CHECK (Braking gently check)
    if (maxPitch > 4.0) {
      score -= 20;
      feedback.add('Wheelchair tilted heavily. Remember to lean forward and brake gently to stop.');
    }

    return TestEvaluation(score.clamp(0, 100).round(), feedback.take(3).toList());
  },
);