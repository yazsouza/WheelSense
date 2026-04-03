import '../models.dart';
import '../esp32_service.dart';

final turnLeftBackwardManeuver = Maneuver(
  name: 'Turning Left (Backward)',
  type: ManeuverType.turnLeft, 
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

    // 1. TURN DETECTION (Left Backward = NEGATIVE Yaw)
    if (avgYawRate >= -2.0) {
      // Basically straight or drifting right
      score -= 70;
      feedback.add('No left turn detected. Make sure to pull the left wheel to steer.');
    } else if (avgYawRate > -6.0) {
      // Weak turn
      score -= 15;
      feedback.add('Turn was a bit shallow. Try pulling harder on the inside (left) wheel.');
    } else {
      feedback.add('Excellent left turning arc!');
    }

    // 2. STRAIGHTNESS PENALTY (Double jeopardy for rolling straight)
    if (avgAbsYawRate < 3.0) {
      score -= 20; 
      feedback.add('Movement was almost entirely straight.');
    }

    // 3. WOBBLE DETECTION (Relaxed for human pushing)
    if (wobble > 10.0) {
      score -= 15;
      feedback.add('Turn was a bit jerky. Try smoother, continuous pulls.');
    }

    // 4. TILT CHECK (Relaxed to allow for natural movement)
    if (maxPitch > 6.0) {
      score -= 15;
      feedback.add('Wheelchair tilted heavily. Remember to lean forward and brake gently to stop.');
    }

    return TestEvaluation(score.clamp(0, 100).round(), feedback.take(3).toList());
  },
);