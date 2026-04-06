import '../models.dart';
import '../esp32_service.dart';

final turnLeftManeuver = Maneuver(
  name: 'Turning Left',
  type: ManeuverType.turnLeft,
  steps: [
    ManeuverStep(
      title: 'Approach',
      text: 'Approach the turn with medium speed.',
      imagePath: 'assets/images/forwardturn.png',
    ),
        ManeuverStep(
      title: 'Timing and Push',
      text: 'Axle of read wheel should line up with the where you are turning around. Push harder on the right wheel to initiate the turn.',
      imagePath: 'assets/images/forwardturn.png',
   ),
    ManeuverStep(
      title: 'Follow Through',
      text: 'Maintain forward momentum while curving left.',
      imagePath: 'assets/images/forwardturn.png',
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

    // 1. TOO STRAIGHT PENALTY (-70 pts)
    if (avgAbsYawRate < 1.5) {
      score -= 70;
      feedback.add('Movement was essentially a straight line instead of turning.');
    }

    // 2. 90-DEGREE TURN CHECK (Left is Positive Rotation)
    if (totalRotation < 75) {
      double deficit = 90 - totalRotation;
      if (totalRotation < 20) {
        score -= 30; // Stacks with the straight penalty if it was really bad
        if (!feedback.any((f) => f.contains('straight line'))) {
           feedback.add('Turn was far too shallow. Aim for a full 90° turn.');
        }
      } else {
        score -= (deficit * 0.8).clamp(0, 40);
        feedback.add('Incomplete turn. You turned ${totalRotation.round()}°. Aim for a full 90° turn.');
      }
    } else {
      feedback.add('Good left turning arc (${totalRotation.round()}°).');
    }

    // 3. TILT CHECK
    if (maxPitch > 4.0) {
      score -= 20;
      feedback.add('Wheelchair tilted during turn. Keep your weight forward for stability.');
    }

    return TestEvaluation(score.clamp(0, 100).round(), feedback.take(3).toList());
  }
);