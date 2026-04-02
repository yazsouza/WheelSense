import '../models.dart';
import '../esp32_service.dart';

final downRampManeuver = Maneuver(
  name: 'Wheeling Down Ramps',
  type: ManeuverType.downRamp,
  steps: [
    ManeuverStep(
      title: 'Setup',
      text: 'Lean back! Keep weight over the rear wheels to prevent forward tipping.',
    ),
    ManeuverStep(
      title: 'Control Speed',
      text: 'Slide handrims smoothly through hands at 1 o\'clock. Speed of descent is controlled by how tightly you grip.',
    ),
    ManeuverStep(
      title: 'Maintain Path',
      text: 'Stay in the middle of the ramp. To stop or rest, grab one handrim to turn sideways.',
    ),
  ],
  evaluator: (List<WheelData> pool) {
    if (pool.length < 5) {
      return TestEvaluation(0, ['Not enough data. Ensure you capture the full descent.']);
    }

    double score = 100.0;
    final List<String> feedback = [];

    // 1. WRONG WAY DETECTION (Moving UP the ramp)
    // Backward roll means signed wheel speed is negative
    final wrongWayCount = pool.where((d) => d.signedR < -0.3 || d.signedL < -0.3).length;
    
    if (wrongWayCount > (pool.length * 0.5)) {
      return TestEvaluation(0, ['You traveled backward (up the ramp) the entire time!']);
    } else if (wrongWayCount > 2) {
      score -= (wrongWayCount * 8).clamp(0, 40);
      feedback.add('You momentarily rolled backward. Keep your momentum moving steadily down the ramp.');
    }

    // 2. CALCULATE RAMP ANGLE & FORWARD SPEED
    final avgIncline = pool.map((d) => d.pitchDeg.abs()).reduce((a, b) => a + b) / pool.length;
    
    // Removed the .abs() here so going backwards doesn't trigger "fast" forward speed
    final peakSpeed = pool.map((d) => d.speedMS).reduce((a, b) => a > b ? a : b);
    final avgSpeed = pool.map((d) => d.speedMS).reduce((a, b) => a + b) / pool.length;
    
    // 3. DYNAMIC SPEED BENCHMARK BASED ON DECLINE ANGLE
    double maxSafeSpeed = 1.2; // Safe speed for almost flat ground
    
    if (avgIncline > 8.0) {
      maxSafeSpeed = 0.5; // Very steep, must go slow
    } else if (avgIncline > 5.0) {
      maxSafeSpeed = 0.7; // Moderate steepness
    } else if (avgIncline > 2.0) {
      maxSafeSpeed = 0.9; // Mild incline
    }

    // 4. EVALUATE SPEED SAFETY
    if (peakSpeed > maxSafeSpeed) {
      double overage = peakSpeed - maxSafeSpeed;
      score -= (overage * 80).clamp(0, 50);
      feedback.add(
        'UNSAFE SPEED: Reached ${peakSpeed.toStringAsFixed(2)} m/s on a ${avgIncline.toStringAsFixed(1)}° decline. Grip the handrims tighter to slow down!'
      );
    } else if (avgSpeed < 0.05 && wrongWayCount == 0) {
      score -= 20;
      feedback.add('Movement was incredibly slow or completely stopped.');
    } else if (wrongWayCount == 0) {
      feedback.add('Great speed control for a ${avgIncline.toStringAsFixed(1)}° decline.');
    }

    // 5. SMOOTH BRAKING (Avoid sudden jerks)
    double totalAcceleration = 0;
    for (int i = 0; i < pool.length - 1; i++) {
      totalAcceleration += (pool[i + 1].speedMS.abs() - pool[i].speedMS.abs()).abs();
    }
    final avgJerk = totalAcceleration / pool.length;

    if (avgJerk > 0.10) { // Slight leniency added here
      score -= (avgJerk * 100).clamp(0, 20);
      feedback.add('Descent was jerky. Try to let the handrims slide continuously through your hands.');
    }

    // 6. DRIFT / STAY CENTERED
    final avgAbsYawRate = pool.map((d) => d.yawRateDps.abs()).reduce((a, b) => a + b) / pool.length;
    if (avgAbsYawRate > 2.5) {
      score -= (avgAbsYawRate * 3.0).clamp(0, 15);
      feedback.add('You drifted side-to-side. Apply friction evenly to both wheels.');
    }

    // 7. THE "ANTI-SARCASM" FILTER
    int finalScore = score.clamp(0, 100).round();
    if (finalScore < 50) {
      feedback.removeWhere((msg) => msg.contains('Great') || msg.contains('Excellent'));
    }

    return TestEvaluation(finalScore, feedback.take(3).toList());
  },
);