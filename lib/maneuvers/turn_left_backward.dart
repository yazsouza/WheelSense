import '../models.dart';
import '../esp32_service.dart';

final turnLeftBackwardManeuver = Maneuver(
  name: 'Turning Left (Backward)',
  type: ManeuverType.turnLeft, 
  steps: [
    ManeuverStep(
      title: 'Backing up',
      text: 'Shoulder check to scan for obstacles in both directions. Pull back evenly and go slow.',
      imagePath: 'assets/images/turningback1.png',
    ),
    ManeuverStep(
      title: 'Turn',
      text: 'Inside wheel (Left): Use to steer. Outside wheel (Right): Pull to keep moving.',
      imagePath: 'assets/images/turningback2.png',
    ),
    ManeuverStep(
      title: 'Stop',
      text: 'Lean forward and brake gently.',
      imagePath: 'assets/images/turningback3.png',
    ),
  ],
 evaluator: (List<WheelData> pool) {
    if (pool.length < 5) return TestEvaluation(0, ['Not enough data collected. Try again.']);

    double score = 100.0;
    List<String> feedback = [];

    double avgAbsYawRate = pool.map((d) => d.yawRateDps.abs()).reduce((a, b) => a + b) / pool.length;
    final maxPitch = pool.map((d) => d.pitchDeg.abs()).reduce((a, b) => a > b ? a : b);

    // Calculate Total Rotation
    double totalRotation = 0;
    for (int i = 0; i < pool.length - 1; i++) {
      double diff = pool[i + 1].yawDeg - pool[i].yawDeg;
      if (diff > 180) diff -= 360;
      if (diff < -180) diff += 360;
      totalRotation += diff;
    }

    // 1. STRAIGHTNESS PENALTY (-70 pts)
    if (avgAbsYawRate < 1.5) {
      score -= 70;
      feedback.add('Movement was almost entirely straight.');
    }

    // 2. 90-DEGREE CHECK (Left Backward = NEGATIVE Rotation)
    if (totalRotation > -75) {
      double deficit = 90 - totalRotation.abs();
      if (totalRotation > -20) {
        score -= 30;
        feedback.add('No distinct turn detected. Pull the inside (left) wheel harder.');
      } else {
        score -= (deficit * 0.8).clamp(0, 40);
        feedback.add('Incomplete turn. You turned ${totalRotation.abs().round()}°. Aim for a full 90° turn.');
      }
    } else {
      feedback.add('Excellent left turning arc (${totalRotation.abs().round()}°).');
    }

    // 3. STRICT TILT CHECK (-20 pts)
    if (maxPitch > 6.0) {
      score -= 20;
      feedback.add('Wheelchair tilted heavily. Remember to lean forward and brake gently to stop.');
    }

    return TestEvaluation(score.clamp(0, 100).round(), feedback.take(3).toList());
  }
);