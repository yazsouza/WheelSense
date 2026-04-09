import '../models.dart';
import '../esp32_service.dart';

final turnRightManeuver = Maneuver(
  name: 'Turning Right',
  type: ManeuverType.turnRight,
  steps: [
    ManeuverStep(
      title: 'Approach',
      text: 'Approach the turn with medium speed.',
      imagePath: 'assets/images/forwardturn2.png',
    ),
        ManeuverStep(
      title: 'Timing and Push',
      text: 'Axle of read wheel should line up with the where you are turning around. Push harder on the left wheel to initiate the turn.',
      imagePath: 'assets/images/forwardturn2.png',
   ),
    ManeuverStep(
      title: 'Follow Through',
      text: 'Maintain forward momentum while curving right.',
      imagePath: 'assets/images/forwardturn2.png',
    ),
  ],
evaluator: (List<WheelData> pool) {
    if (pool.length < 5) return TestEvaluation(0, ['Not enough data collected. Try again.']);

    double score = 100.0;
    List<String> feedback = [];

    double avgYawRate = pool.map((d) => d.yawRateDps).reduce((a, b) => a + b) / pool.length;
    double avgAbsYawRate = pool.map((d) => d.yawRateDps.abs()).reduce((a, b) => a + b) / pool.length;
    double wobble = pool.map((d) => (d.yawRateDps - avgYawRate).abs()).reduce((a, b) => a + b) / pool.length;
    final maxPitch = pool.map((d) => d.pitchDeg.abs()).reduce((a, b) => a > b ? a : b);

    double currentRotation = 0;
    double peakRotation = 0;
    for (int i = 0; i < pool.length - 1; i++) {
      double diff = pool[i + 1].yawDeg - pool[i].yawDeg;
      if (diff > 180) diff -= 360;
      if (diff < -180) diff += 360;
      currentRotation += diff;
      if (currentRotation.abs() > peakRotation) peakRotation = currentRotation.abs();
    }
    double finalRotation = currentRotation.abs();

    if (avgAbsYawRate < 1.5) {
      score -= 70;
      feedback.add('Movement was essentially a straight line instead of turning.');
    }

    if (finalRotation < 75) {
      double deficit = 90 - finalRotation;
      if (finalRotation < 20) {
        score -= 30; 
        if (!feedback.any((f) => f.contains('straight line'))) {
           feedback.add('Turn was far too shallow. Aim for a full 90° turn.');
        }
      } else {
        score -= (deficit * 0.8).clamp(0, 40);
        feedback.add('Incomplete turn. You turned ${finalRotation.round()}°. Aim for a full 90° turn.');
      }
    } else {
      feedback.add('Good right turning arc (${finalRotation.round()}°).');
    }

    double overshoot = peakRotation - finalRotation;
    if (overshoot > 10.0) {
      score -= (overshoot * 1.0).clamp(0, 20);
      feedback.add('You over-rotated and had to correct back. Try to stop smoothly exactly at 90°.');
    }

    // 4. RELAXED WOBBLE DETECTION
    if (wobble > 8.0) {
      score -= 10;
      feedback.add('Turn was a bit uneven. Try smoother continuous pushes.');
    }

    if (maxPitch > 4.0) {
      score -= 20;
      feedback.add('Wheelchair tilted during turn. Keep your weight forward for stability.');
    }

    return TestEvaluation(score.clamp(0, 100).round(), feedback.take(3).toList());
  }
);